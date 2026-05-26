import asyncio
from api.celery_app import celery_app
from core.state import ops_manager

@celery_app.task(name="api.tasks.ingest_url_task")
def ingest_url_task(url: str, task_id: str):
    """Celery task to run the ingestion logic for a given URL."""
    # Set the state to active in Redis/in-memory
    ops_manager.update_task(task_id, "Processing from Celery queue", state="active")
    
    # Import main ingestion logic dynamically to avoid circular imports
    from main import _run_ingestion_logic
    
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
