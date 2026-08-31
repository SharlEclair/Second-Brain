"""
api/services/ingestion.py — URL ingestion pipeline and file naming service.
"""
import os
import re
import json
import uuid
import datetime
import asyncio
from typing import Optional, Callable, Awaitable

from core.config import OBSIDIAN_INBOX_PATH, PROJECT_VAULT_PATH, AI_MODEL
from core.state import ops_manager, get_url_index, save_url_index
from core.utils import chunk_text, get_platform_from_url
from core.processors import (
    process_reel,
    process_image_post,
    process_web_article,
)
from core.db import get_vault_collection
from api.services.vault import get_system_config, update_hierarchical_indexes


def get_unique_filename(filename: str, category: Optional[str] = None) -> str:
    """Generate a collision-free filename across both vaults."""
    stem, ext = os.path.splitext(filename)
    candidate = filename
    counter = 2
    while True:
        project_path = (
            os.path.join(PROJECT_VAULT_PATH, category, candidate)
            if category
            else os.path.join(PROJECT_VAULT_PATH, candidate)
        )
        obsidian_path = (
            os.path.join(OBSIDIAN_INBOX_PATH, category, candidate)
            if category
            else os.path.join(OBSIDIAN_INBOX_PATH, candidate)
        )

        if os.path.exists(project_path) or os.path.exists(obsidian_path):
            candidate = f"{stem} ({counter}){ext}"
            counter += 1
        else:
            break
    return candidate


async def _run_ingestion_logic(
    url: str,
    task_id: str,
    status_callback: Optional[Callable[[str], Awaitable[None]]] = None,
) -> dict:
    """
    Execute full ingestion lifecycle for a given URL:
    1. Duplicate check (URL index + disk)
    2. Platform-specific scraping & AI extraction (Instagram/YouTube/TikTok/Web)
    3. MD5 content fingerprint duplicate check
    4. Two-vault filesystem write (.md files)
    5. url_index.json update
    6. Optional Google Calendar sync (for Event category)
    7. ChromaDB vector embedding indexing
    8. Hierarchical librarian index regeneration
    """
    platform = get_platform_from_url(url)
    try:
        index = get_url_index()
        if url in index:
            note_data = index[url]
            fn = note_data['fileName'] if isinstance(note_data, dict) else note_data
            if any(
                os.path.exists(os.path.join(path, fn))
                for path in [OBSIDIAN_INBOX_PATH, PROJECT_VAULT_PATH]
            ):
                ops_manager.end_task(task_id, "Already exists", state="existing")
                return {
                    "status": "existing",
                    "task_id": task_id,
                    "note": note_data
                    if isinstance(note_data, dict)
                    else {"fileName": fn, "title": fn},
                }

        url_lower = url.lower()
        is_instagram = "instagram.com" in url_lower or "instagr.am" in url_lower
        is_instagram_reel = is_instagram and (
            "/reel/" in url_lower
            or "/reels/" in url_lower
            or "/share/reel/" in url_lower
            or "/tv/" in url_lower
        )
        is_instagram_post = is_instagram and (
            "/p/" in url_lower
            and not is_instagram_reel
        )

        if is_instagram_post:
            data = await process_image_post(url, task_id, status_callback)
        elif (
            platform == "youtube"
            or platform == "tiktok"
            or is_instagram_reel
            or is_instagram
        ):
            data = await process_reel(url, task_id, status_callback)
        else:
            data = await process_web_article(url, task_id, status_callback)

        # MD5 Duplicate Detection
        if status_callback:
            await status_callback("Checking content fingerprint")
        ops_manager.update_task(task_id, "Checking content fingerprint", progress=80)
        index = get_url_index()
        content_hash = data.get('content_hash')
        if content_hash:
            for existing_url, existing_data in index.items():
                if (
                    isinstance(existing_data, dict)
                    and existing_data.get('content_hash') == content_hash
                ):
                    ops_manager.end_task(task_id, "Duplicate content", state="existing")
                    return {
                        "status": "existing",
                        "task_id": task_id,
                        "message": "Content already exists in vault (detected via MD5)",
                        "note": existing_data,
                    }

        if status_callback:
            await status_callback("Saving to vaults")
        ops_manager.update_task(task_id, "Saving to vaults", progress=85)
        date_str = datetime.datetime.now().strftime("%Y-%m-%d")
        safe_uploader = re.sub(r'[\\/*?:"<>|]', "", data['uploader'])
        raw_category = data['ai_data'].get('category', 'Post')
        sys_config = get_system_config()
        if sys_config.get("inbox_mode", False):
            raw_category = "raw"
        safe_category = re.sub(r'[\\/*?:"<>|]', "-", raw_category)
        filename = get_unique_filename(
            f"{date_str} - {safe_category} from {data['platform'].capitalize()} ({safe_uploader}).md",
            category=safe_category,
        )

        # Subfolder structuring based on category
        project_category_path = os.path.join(PROJECT_VAULT_PATH, safe_category)
        obsidian_category_path = os.path.join(OBSIDIAN_INBOX_PATH, safe_category)
        os.makedirs(project_category_path, exist_ok=True)
        os.makedirs(obsidian_category_path, exist_ok=True)

        project_filepath = os.path.join(project_category_path, filename)
        obsidian_filepath = os.path.join(obsidian_category_path, filename)
        raw_transcript = (data.get("raw_transcript") or "").strip()
        transcript_status = data.get("transcript_status") or (
            "complete" if raw_transcript else "not_available"
        )
        transcript_section = ""
        if raw_transcript:
            transcript_section = f"""
## Raw Transcript
{raw_transcript}
"""
        elif data["type"].endswith("-video") or data["type"] == "instagram-carousel":
            transcript_section = f"""
## Raw Transcript
*Transcript status: {transcript_status}. No spoken transcript was captured for this media.*
"""

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
transcript_status: {transcript_status}
ai_model: {data['ai_data'].get('_model_used', AI_MODEL)}
processor: {data.get('processor', '')}
---
# {raw_category} by {data['uploader']}

> **AI Summary:** {data['ai_data'].get('summary', '')}

## Extracted Content
{data['ai_data'].get('formatted_content', '')}
{transcript_section}

---
### Original Caption
* {data['description']}
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
            "url": url,
            "content_hash": data.get('content_hash'),
            "platform": data.get("platform"),
            "type": data.get("type"),
            "transcript_status": transcript_status,
            "ai_model": data['ai_data'].get('_model_used', AI_MODEL),
            "event_date": data.get("ai_data", {}).get("event_date"),
            "category": raw_category,
            "latitude": latitude,
            "longitude": longitude,
            "locations": locations,
            "hidden_locations": hidden_locations,
        }
        index = get_url_index()
        index[url] = note_data
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

        if status_callback:
            await status_callback("Updating AI index")
        ops_manager.update_task(task_id, "Updating AI index", progress=95)
        index_text = "\n\n".join(
            part.strip()
            for part in [
                data['ai_data'].get('formatted_content', ''),
                raw_transcript,
                data.get('description', ''),
            ]
            if part and part.strip()
        )
        chunks = [chunk for chunk in chunk_text(index_text) if chunk.strip()]
        if chunks:
            get_vault_collection().add(
                documents=chunks,
                metadatas=[
                    {
                        "filename": relative_filename,
                        "url": url,
                        "content_hash": data.get("content_hash"),
                    }
                    for _ in chunks
                ],
                ids=[
                    f"{content_hash or uuid.uuid4().hex}_chunk_{i}"
                    for i in range(len(chunks))
                ],
            )

        # Update AI Librarian indexes
        update_hierarchical_indexes()

        ops_manager.end_task(task_id, "Completed", state="completed")
        return {"status": "success", "task_id": task_id, "note": note_data}
    except Exception as e:
        import traceback

        ops_manager.log_error(url, str(e), detail=traceback.format_exc())
        ops_manager.end_task(task_id, "Failed", state="failed", error=str(e))
        raise e
