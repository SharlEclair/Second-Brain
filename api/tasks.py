import asyncio
from api.celery_app import celery_app
from core.state import ops_manager

@celery_app.task(name="api.tasks.ingest_url_task")
def ingest_url_task(url: str, task_id: str):
    """Celery task to run the ingestion logic for a given URL."""
    # Set the state to active in Redis/in-memory
    ops_manager.update_task(task_id, "Processing from Celery queue", state="active")
    
    # Import ingestion logic from service layer (clean decoupling from main.py)
    from api.services.ingestion import _run_ingestion_logic
    
    # Run the async ingestion logic inside an event loop
    try:
        loop = asyncio.get_event_loop()
    except RuntimeError:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        
    if loop.is_closed():
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        
    try:
        result = loop.run_until_complete(_run_ingestion_logic(url, task_id))
        return result
    except Exception as e:
        import traceback
        error_msg = str(e)
        detail = traceback.format_exc()
        ops_manager.log_error(url, error_msg, detail=detail)
        ops_manager.end_task(task_id, "Failed", state="failed", error=error_msg)
        raise e


@celery_app.task(name="api.tasks.ingest_file_task")
def ingest_file_task(file_path: str, filename: str, task_id: str):
    """Celery task to run the local file ingestion logic for dropped/uploaded files."""
    import os
    ops_manager.update_task(task_id, "Processing file from Celery queue", state="active")
    from core.processors import process_local_file

    try:
        loop = asyncio.get_event_loop()
    except RuntimeError:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

    if loop.is_closed():
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

    try:
        result = loop.run_until_complete(process_local_file(file_path, filename, task_id))
        return result
    except Exception as e:
        import traceback
        error_msg = str(e)
        detail = traceback.format_exc()
        ops_manager.log_error(filename, error_msg, detail=detail)
        ops_manager.end_task(task_id, "Failed", state="failed", error=error_msg)
        raise e
    finally:
        if os.path.exists(file_path):
            try:
                os.remove(file_path)
            except Exception as e:
                print(f"[Celery] Failed to remove temp file {file_path}: {e}")


@celery_app.task(name="api.tasks.weekly_synthesis_task")

def weekly_synthesis_task():
    """Periodic Celery task for weekly synthesis loop."""
    from core.synthesis_loop import run_weekly_synthesis
    try:
        loop = asyncio.get_event_loop()
    except RuntimeError:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        
    loop.run_until_complete(run_weekly_synthesis())

@celery_app.task(name="api.tasks.daily_serendipity_task")
def daily_serendipity_task():
    """Periodic Celery task to send daily serendipity notifications."""
    from core.serendipity import send_serendipity_notifications
    try:
        loop = asyncio.get_event_loop()
    except RuntimeError:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        
    loop.run_until_complete(send_serendipity_notifications())

@celery_app.task(name="api.tasks.retroactive_backlink_task")
def retroactive_backlink_task():
    """Periodic Celery task to trigger retroactive backlink scan."""
    from core.retroactive_backlink import run_retroactive_scan
    # run_retroactive_scan is a synchronous function
    run_retroactive_scan()


@celery_app.task(name="api.tasks.nightly_vault_synthesis_task")
def nightly_vault_synthesis_task():
    """
    Nightly Celery task that walks the vault, identifies notes missing
    semantic footers ('## Related Notes'), and appends related notes and
    unlinked mention suggestions.
    """
    import os
    from core.config import PROJECT_VAULT_PATH
    from core.synthesis import get_all_vault_note_titles, process_note_synthesis

    if not os.path.exists(PROJECT_VAULT_PATH):
        print(f"[Nightly Synthesis] Vault path does not exist: {PROJECT_VAULT_PATH}")
        return {"status": "error", "message": "Vault path does not exist"}

    print(f"[Nightly Synthesis] Starting vault synthesis scan in {PROJECT_VAULT_PATH}...")
    all_titles = get_all_vault_note_titles(PROJECT_VAULT_PATH)
    processed_count = 0
    modified_count = 0
    skipped_count = 0

    for root, dirs, files in os.walk(PROJECT_VAULT_PATH):
        if ".git" in root or "raw" in root:
            continue
        for file in files:
            if file.endswith(".md") and not file.startswith((".", "_")):
                filepath = os.path.join(root, file)
                try:
                    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                        text = f.read()

                    if "## Related Notes" in text:
                        skipped_count += 1
                        continue

                    modified = process_note_synthesis(filepath, all_titles=all_titles)
                    processed_count += 1
                    if modified:
                        modified_count += 1
                except Exception as e:
                    print(f"[Nightly Synthesis] Error processing {file}: {e}")

    print(
        f"[Nightly Synthesis] Complete. Processed: {processed_count}, "
        f"Modified: {modified_count}, Skipped (Already have footer): {skipped_count}"
    )
    return {
        "status": "success",
        "processed": processed_count,
        "modified": modified_count,
        "skipped": skipped_count,
    }


@celery_app.task(name="api.tasks.nightly_taxonomy_task")
def nightly_taxonomy_task():
    """
    Nightly Celery task for the Autonomous Librarian:
    Unifies tags via Gemini semantic clustering and generates Maps of Content.
    """
    from core.taxonomy import run_taxonomy_and_moc_pipeline
    return run_taxonomy_and_moc_pipeline()


@celery_app.task(name="api.tasks.backfill_knowledge_graph_task")
def backfill_knowledge_graph_task():
    """
    Celery task to backfill Neo4j Knowledge Graph across all markdown notes
    in PROJECT_VAULT_PATH.
    """
    import os
    from core.config import PROJECT_VAULT_PATH
    from core.graph_db import get_graph_driver
    from core.graph_rag import extract_knowledge_graph, upsert_note_graph

    driver = get_graph_driver()
    if driver is None:
        print("[Graph Backfill] Neo4j driver not available. Skipping backfill.")
        return {"status": "error", "message": "Neo4j unavailable"}

    existing_notes = set()
    try:
        with driver.session() as session:
            res = session.run("MATCH (n:Note) RETURN n.title AS title")
            for record in res:
                existing_notes.add(record["title"])
    except Exception as e:
        print(f"[Graph Backfill] Failed to fetch existing Note nodes: {e}")

    ingested_count = 0
    skipped_count = 0

    for root, dirs, files in os.walk(PROJECT_VAULT_PATH):
        if ".git" in root or "Maps" in root or "raw" in root:
            continue
        for file in files:
            if file.endswith(".md") and not file.startswith((".", "_")):
                note_title = file[:-3].strip()
                if note_title in existing_notes:
                    skipped_count += 1
                    continue

                filepath = os.path.join(root, file)
                try:
                    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                        text = f.read()

                    kg_data = extract_knowledge_graph(text)
                    if kg_data.get("entities") or kg_data.get("relationships"):
                        upsert_note_graph(
                            note_title=note_title,
                            entities=kg_data.get("entities", []),
                            relationships=kg_data.get("relationships", []),
                            driver=driver,
                        )
                        ingested_count += 1
                except Exception as e:
                    print(f"[Graph Backfill] Error ingesting {file} into Neo4j: {e}")

    print(f"[Graph Backfill] Complete. Ingested: {ingested_count}, Skipped (Already in graph): {skipped_count}")
    return {
        "status": "success",
        "ingested": ingested_count,
        "skipped": skipped_count,
    }



