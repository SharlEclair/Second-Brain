"""
api/routes/ingest.py — Ingestion endpoints for URLs, file uploads, and raw text.
"""
import os
import re
import json
import uuid
import shutil
import datetime
import asyncio
from fastapi import APIRouter, HTTPException, Request, UploadFile, File
from fastapi.responses import StreamingResponse

from api.models import IngestTextRequest
from core.config import OBSIDIAN_INBOX_PATH, PROJECT_VAULT_PATH, AI_MODEL
from core.state import ops_manager, get_url_index, save_url_index
from core.utils import clean_url, chunk_text, get_platform_from_url
from core.processors import (
    process_pdf,
    process_uploaded_image,
    process_audio_file,
    process_text_file,
    process_raw_text,
)
from core.db import get_vault_collection
from api.services.ingestion import _run_ingestion_logic, get_unique_filename
from api.services.vault import get_system_config, update_hierarchical_indexes

router = APIRouter(tags=["ingest"])


@router.post("/api/ingest")
async def ingest_url(request: Request):
    body = await request.json()
    url = clean_url(body.get('url', ''))
    if not url:
        raise HTTPException(status_code=400, detail="URL is required")

    wants_stream = request.headers.get("X-Stream", "") == "true"
    is_queued = request.headers.get("X-Queue", "") == "true"

    if is_queued:
        task_id = f"task_{uuid.uuid4().hex[:8]}"
        platform = get_platform_from_url(url)
        ops_manager.start_task(
            task_id, url, "Queued", platform=platform, progress=0, state="queued"
        )
        from api.tasks import ingest_url_task

        ingest_url_task.delay(url, task_id)
        return {
            "status": "queued",
            "task_id": task_id,
            "message": "Task added to background queue",
        }

    async def _run_ingestion(url: str, status_callback=None):
        task_id = f"task_{uuid.uuid4().hex[:8]}"
        platform = get_platform_from_url(url)
        if status_callback:
            await status_callback("Checking index")
        ops_manager.start_task(
            task_id, url, "Checking index", platform=platform, progress=5
        )
        return await _run_ingestion_logic(url, task_id, status_callback)

    if wants_stream:

        async def stream():
            try:
                stream_queue = asyncio.Queue()

                async def on_status(msg):
                    await stream_queue.put(
                        json.dumps({"status": "status", "message": f"{msg}..."}) + "\n"
                    )

                async def run_task():
                    try:
                        res = await _run_ingestion(url, on_status)
                        await stream_queue.put(json.dumps(res) + "\n")
                    except Exception as e:
                        await stream_queue.put(
                            json.dumps({"status": "error", "message": str(e)}) + "\n"
                        )
                    finally:
                        await stream_queue.put(None)

                asyncio.create_task(run_task())

                while True:
                    item = await stream_queue.get()
                    if item is None:
                        break
                    yield item
            except Exception as e:
                yield json.dumps({"status": "error", "message": str(e)}) + "\n"

        return StreamingResponse(stream(), media_type="application/x-ndjson")

    try:
        return await _run_ingestion(url)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/ingest/file")
async def ingest_file(file: UploadFile = File(...)):
    """
    Accepts raw file drops/uploads, saves to temporary storage,
    enqueues an async ingestion Celery task (ingest_file_task),
    and returns the task_id.
    """
    if not file.filename:
        raise HTTPException(status_code=400, detail="Filename missing")

    temp_dir = os.path.join(os.getcwd(), "temp")
    os.makedirs(temp_dir, exist_ok=True)

    safe_filename = os.path.basename(file.filename)
    temp_file_path = os.path.join(temp_dir, f"drop_{uuid.uuid4().hex}_{safe_filename}")

    try:
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to save temp file: {e}")

    task_id = f"task_{uuid.uuid4().hex[:8]}"
    ops_manager.start_task(
        task_id, file.filename, "Queued", platform="local", progress=0, state="queued"
    )

    from api.tasks import ingest_file_task
    ingest_file_task.delay(temp_file_path, file.filename, task_id)

    return {
        "status": "queued",
        "task_id": task_id,
        "filename": file.filename,
        "message": "File queued for background processing",
    }


@router.post("/api/upload")
async def upload_file(file: UploadFile = File(...)):

    filename_lower = file.filename.lower()
    IMAGE_EXTS = (".jpg", ".jpeg", ".png", ".webp")
    AUDIO_EXTS = (".mp3", ".wav", ".m4a", ".ogg", ".aac")
    TEXT_EXTS = (".txt", ".md")

    is_valid = (
        filename_lower.endswith(".pdf")
        or any(filename_lower.endswith(ext) for ext in IMAGE_EXTS)
        or any(filename_lower.endswith(ext) for ext in AUDIO_EXTS)
        or any(filename_lower.endswith(ext) for ext in TEXT_EXTS)
    )
    if not is_valid:
        raise HTTPException(
            status_code=400,
            detail="Unsupported format. Only PDF, images (JPG/PNG/WEBP), audio (MP3/WAV/M4A), and text (TXT/MD) files are supported.",
        )

    task_id = f"task_{uuid.uuid4().hex[:8]}"
    ops_manager.start_task(
        task_id, file.filename, "Uploading file", platform="local", progress=5
    )

    safe_filename = os.path.basename(file.filename)
    temp_path = f"temp_upload_{uuid.uuid4().hex}_{safe_filename}"
    try:
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        if filename_lower.endswith(".pdf"):
            data = await process_pdf(temp_path, safe_filename, task_id)
        elif any(filename_lower.endswith(ext) for ext in IMAGE_EXTS):
            data = await process_uploaded_image(temp_path, safe_filename, task_id)
        elif any(filename_lower.endswith(ext) for ext in AUDIO_EXTS):
            data = await process_audio_file(temp_path, safe_filename, task_id)
        else:
            data = await process_text_file(temp_path, safe_filename, task_id)

        # Save to vaults
        ops_manager.update_task(task_id, "Saving to vaults", progress=85)
        date_str = datetime.datetime.now().strftime("%Y-%m-%d")
        safe_uploader = re.sub(r'[\/*?:"<>|]', "", data['uploader'])
        raw_category = data['ai_data'].get('category', 'Document')
        sys_config = get_system_config()
        if sys_config.get("inbox_mode", False):
            raw_category = "raw"
        safe_category = re.sub(r'[\/*?:"<>|]', "-", raw_category)
        filename = get_unique_filename(
            f"{date_str} - {safe_category} ({safe_uploader}).md",
            category=safe_category,
        )

        project_category_path = os.path.join(PROJECT_VAULT_PATH, safe_category)
        obsidian_category_path = os.path.join(OBSIDIAN_INBOX_PATH, safe_category)
        os.makedirs(project_category_path, exist_ok=True)
        os.makedirs(obsidian_category_path, exist_ok=True)

        project_filepath = os.path.join(project_category_path, filename)
        obsidian_filepath = os.path.join(obsidian_category_path, filename)

        event_date = data.get('ai_data', {}).get('event_date')
        event_date_str = (
            f"event_date: {event_date}\n"
            if event_date and str(event_date).lower() != "null"
            else ""
        )

        latitude = data.get('ai_data', {}).get('latitude')
        longitude = data.get('ai_data', {}).get('longitude')
        lat_str = f"latitude: {latitude}\n" if latitude is not None else ""
        lng_str = f"longitude: {longitude}\n" if longitude is not None else ""

        locations = data.get('ai_data', {}).get('locations', [])
        hidden_locations = data.get('ai_data', {}).get('hidden_locations', [])
        locations_str = f"locations: {json.dumps(locations)}\n"
        hidden_locs_str = f"hidden_locations: {json.dumps(hidden_locations)}\n"

        content = f"""---
type: {data['type']}
date: {date_str}
author: {data['uploader']}
url: {data['url']}
category: {raw_category}
tags: {data['ai_data'].get('tags', [])}
{event_date_str}{lat_str}{lng_str}{locations_str}{hidden_locs_str}content_hash: {data.get('content_hash', '')}
ai_model: {data['ai_data'].get('_model_used', AI_MODEL)}
processor: {data.get('processor', '')}
---
# {raw_category} - {data['description']}

> **AI Summary:** {data['ai_data'].get('summary', '')}

## Extracted Content
{data['ai_data'].get('formatted_content', '')}

## Raw Transcript
{data['raw_transcript']}
"""
        with open(project_filepath, "w", encoding="utf-8") as f:
            f.write(content)
        with open(obsidian_filepath, "w", encoding="utf-8") as f:
            f.write(content)

        relative_filename = os.path.join(safe_category, filename).replace("\\", "/")
        note_data = {
            "title": filename.replace(".md", ""),
            "fileName": relative_filename,
            "date": datetime.datetime.now().isoformat(),
            "url": data['url'],
            "content_hash": data.get('content_hash'),
            "platform": data.get("platform"),
            "type": data.get("type"),
            "ai_model": data['ai_data'].get('_model_used', AI_MODEL),
            "event_date": data.get("ai_data", {}).get("event_date"),
            "category": raw_category,
            "latitude": latitude,
            "longitude": longitude,
            "locations": locations,
            "hidden_locations": hidden_locations,
        }

        # Update JSON index
        index = get_url_index()
        index[data['url']] = note_data
        save_url_index(index)

        event_date = data.get("ai_data", {}).get("event_date")
        if (
            event_date
            and str(event_date).lower() != "null"
            and data['ai_data'].get('category') == "Event"
        ):
            ops_manager.update_task(task_id, "Syncing to Calendar", progress=90)
            try:
                from core.calendar_sync import create_calendar_event

                await asyncio.to_thread(
                    create_calendar_event,
                    title=f"Event: {data['ai_data'].get('summary', 'New Event')[:50]}",
                    event_date_str=str(event_date),
                    source_url=data['url'],
                    description=data['ai_data'].get('formatted_content', ''),
                )
            except Exception as e:
                print(f"Calendar sync failed: {e}")

        # Update Vector DB
        ops_manager.update_task(task_id, "Updating AI index", progress=95)
        index_text = "\n\n".join(
            [data['ai_data'].get('formatted_content', ''), data.get('raw_transcript', '')]
        )
        chunks = [chunk for chunk in chunk_text(index_text) if chunk.strip()]
        if chunks:
            get_vault_collection().add(
                documents=chunks,
                metadatas=[
                    {
                        "filename": relative_filename,
                        "url": data['url'],
                        "content_hash": data.get("content_hash"),
                    }
                    for _ in chunks
                ],
                ids=[
                    f"{data.get('content_hash') or uuid.uuid4().hex}_chunk_{i}"
                    for i in range(len(chunks))
                ],
            )

        # Update AI Librarian indexes
        update_hierarchical_indexes()

        ops_manager.end_task(task_id, "Completed", state="completed")
        return {"status": "success", "task_id": task_id, "note": note_data}

    except Exception as e:
        import traceback

        ops_manager.log_error(file.filename, str(e), detail=traceback.format_exc())
        ops_manager.end_task(task_id, "Failed", state="failed", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)


@router.post("/api/ingest_text")
async def ingest_text(request: IngestTextRequest):
    if not request.text.strip():
        raise HTTPException(status_code=400, detail="Text content is required")

    task_id = f"task_{uuid.uuid4().hex[:8]}"
    ops_manager.start_task(
        task_id, request.title, "Ingesting raw text", platform="local", progress=10
    )

    try:
        # Process raw text using our helper
        data = await process_raw_text(request.text, request.title, task_id)

        # Save to vaults
        ops_manager.update_task(task_id, "Saving to vaults", progress=85)
        date_str = datetime.datetime.now().strftime("%Y-%m-%d")
        raw_category = data['ai_data'].get('category', 'General')
        sys_config = get_system_config()
        if sys_config.get("inbox_mode", False):
            raw_category = "raw"
        safe_category = re.sub(r'[\/*?:"<>|]', "-", raw_category)
        filename = get_unique_filename(
            f"{date_str} - {safe_category} (Shared Text).md", category=safe_category
        )

        project_category_path = os.path.join(PROJECT_VAULT_PATH, safe_category)
        obsidian_category_path = os.path.join(OBSIDIAN_INBOX_PATH, safe_category)
        os.makedirs(project_category_path, exist_ok=True)
        os.makedirs(obsidian_category_path, exist_ok=True)

        project_filepath = os.path.join(project_category_path, filename)
        obsidian_filepath = os.path.join(obsidian_category_path, filename)

        event_date = data.get('ai_data', {}).get('event_date')
        event_date_str = (
            f"event_date: {event_date}\n"
            if event_date and str(event_date).lower() != "null"
            else ""
        )

        latitude = data.get('ai_data', {}).get('latitude')
        longitude = data.get('ai_data', {}).get('longitude')
        lat_str = f"latitude: {latitude}\n" if latitude is not None else ""
        lng_str = f"longitude: {longitude}\n" if longitude is not None else ""

        locations = data.get('ai_data', {}).get('locations', [])
        hidden_locations = data.get('ai_data', {}).get('hidden_locations', [])
        locations_str = f"locations: {json.dumps(locations)}\n"
        hidden_locs_str = f"hidden_locations: {json.dumps(hidden_locations)}\n"

        content = f"""---
type: {data['type']}
date: {date_str}
author: {data['uploader']}
url: {data['url']}
category: {raw_category}
tags: {data['ai_data'].get('tags', [])}
{event_date_str}{lat_str}{lng_str}{locations_str}{hidden_locs_str}content_hash: {data.get('content_hash', '')}
ai_model: {data['ai_data'].get('_model_used', AI_MODEL)}
processor: {data.get('processor', '')}
---
# {raw_category} - {data['description']}

> **AI Summary:** {data['ai_data'].get('summary', '')}

## Extracted Content
{data['ai_data'].get('formatted_content', '')}

## Original Text
{data['raw_transcript']}
"""
        with open(project_filepath, "w", encoding="utf-8") as f:
            f.write(content)
        with open(obsidian_filepath, "w", encoding="utf-8") as f:
            f.write(content)

        relative_filename = os.path.join(safe_category, filename).replace("\\", "/")
        note_data = {
            "title": filename.replace(".md", ""),
            "fileName": relative_filename,
            "date": datetime.datetime.now().isoformat(),
            "url": data['url'],
            "content_hash": data.get('content_hash'),
            "platform": data.get("platform"),
            "type": data.get("type"),
            "ai_model": data['ai_data'].get('_model_used', AI_MODEL),
            "event_date": data.get("ai_data", {}).get("event_date"),
            "category": raw_category,
            "latitude": latitude,
            "longitude": longitude,
            "locations": locations,
            "hidden_locations": hidden_locations,
        }

        # Update JSON index
        index = get_url_index()
        index[data['url']] = note_data
        save_url_index(index)

        event_date = data.get("ai_data", {}).get("event_date")
        if (
            event_date
            and str(event_date).lower() != "null"
            and data['ai_data'].get('category') == "Event"
        ):
            ops_manager.update_task(task_id, "Syncing to Calendar", progress=90)
            try:
                from core.calendar_sync import create_calendar_event

                await asyncio.to_thread(
                    create_calendar_event,
                    title=f"Event: {data['ai_data'].get('summary', 'New Event')[:50]}",
                    event_date_str=str(event_date),
                    source_url=data['url'],
                    description=data['ai_data'].get('formatted_content', ''),
                )
            except Exception as e:
                print(f"Calendar sync failed: {e}")

        # Update Vector DB
        ops_manager.update_task(task_id, "Updating AI index", progress=95)
        index_text = "\n\n".join(
            [data['ai_data'].get('formatted_content', ''), data.get('raw_transcript', '')]
        )
        chunks = [chunk for chunk in chunk_text(index_text) if chunk.strip()]
        if chunks:
            get_vault_collection().add(
                documents=chunks,
                metadatas=[
                    {
                        "filename": relative_filename,
                        "url": data['url'],
                        "content_hash": data.get("content_hash"),
                    }
                    for _ in chunks
                ],
                ids=[
                    f"{data.get('content_hash') or uuid.uuid4().hex}_chunk_{i}"
                    for i in range(len(chunks))
                ],
            )

        # Update AI Librarian indexes
        update_hierarchical_indexes()

        ops_manager.end_task(task_id, "Completed", state="completed")
        return {"status": "success", "task_id": task_id, "note": note_data}

    except Exception as e:
        import traceback

        ops_manager.log_error(request.title, str(e), detail=traceback.format_exc())
        ops_manager.end_task(task_id, "Failed", state="failed", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))
