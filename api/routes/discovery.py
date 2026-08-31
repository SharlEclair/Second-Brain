"""
api/routes/discovery.py — Knowledge discovery endpoints (weekly brief, upcoming events, suggestions, serendipity, knowledge graph, inbox counts).
"""
import os
import re
import random
import datetime
from fastapi import APIRouter, HTTPException

from core.config import OBSIDIAN_INBOX_PATH, PROJECT_VAULT_PATH
from core.state import get_url_index, save_url_index
from core.utils import chunk_text
from core.processors import generate_content_with_fallback
from core.db import get_vault_collection

router = APIRouter(tags=["discovery"])


@router.get("/api/weekly_brief")
async def generate_weekly_brief():
    # 1. Gather all notes created in the last 7 days
    index = get_url_index()
    seven_days_ago = datetime.datetime.now() - datetime.timedelta(days=7)

    recent_notes = []
    for url, data in index.items():
        if isinstance(data, dict):
            try:
                note_date = datetime.datetime.fromisoformat(data.get('date'))
                if note_date >= seven_days_ago:
                    recent_notes.append(data)
            except Exception:
                pass

    if not recent_notes:
        raise HTTPException(
            status_code=400,
            detail="No new notes ingested in the last 7 days to generate a brief.",
        )

    # 2. Build summary of recent notes
    brief_content = ""
    for note in recent_notes:
        brief_content += f"- **{note.get('title')}** (Category: {note.get('category')})\n  * Link: [[{note.get('title')}]]\n"

    prompt = (
        "Generate a professional, beautiful, and structured 'Weekly Brief' summarizing the following newly ingested knowledge entries. "
        "Create sections based on categories (e.g., Recipe, Spot to Visit, Job/Career, etc.), summarize the key learnings/takeaways from these entries, "
        "and suggest connections or action steps. Use elegant markdown styling with headers and bullet points:\n\n"
        f"{brief_content}"
    )

    response, model_used = generate_content_with_fallback(
        prompt, purpose="weekly_brief"
    )
    brief_text = response.text.strip()

    # 3. Save the weekly brief note to vault
    date_str = datetime.datetime.now().strftime("%Y-%m-%d")
    brief_filename = f"Weekly Brief - {date_str}.md"
    safe_category = "Weekly Brief"

    project_category_path = os.path.join(PROJECT_VAULT_PATH, safe_category)
    obsidian_category_path = os.path.join(OBSIDIAN_INBOX_PATH, safe_category)
    os.makedirs(project_category_path, exist_ok=True)
    os.makedirs(obsidian_category_path, exist_ok=True)

    project_filepath = os.path.join(project_category_path, brief_filename)
    obsidian_filepath = os.path.join(obsidian_category_path, brief_filename)

    full_content = f"""---
type: weekly-brief
date: {date_str}
category: Weekly Brief
tags: ["#weekly-brief", "#intelligence"]
ai_model: {model_used}
---
# Weekly Brief - {date_str}

{brief_text}
"""

    with open(project_filepath, "w", encoding="utf-8") as f:
        f.write(full_content)
    with open(obsidian_filepath, "w", encoding="utf-8") as f:
        f.write(full_content)

    relative_filename = os.path.join(safe_category, brief_filename).replace("\\", "/")

    note_data = {
        "title": brief_filename.replace(".md", ""),
        "fileName": relative_filename,
        "date": datetime.datetime.now().isoformat(),
        "url": f"local://weekly-brief-{date_str}",
        "category": "Weekly Brief",
        "tags": ["#weekly-brief", "#intelligence"],
        "ai_model": model_used,
    }

    index[f"local://weekly-brief-{date_str}"] = note_data
    save_url_index(index)

    # Also index the Weekly Brief in ChromaDB
    chunks = [chunk for chunk in chunk_text(brief_text) if chunk.strip()]
    if chunks:
        get_vault_collection().add(
            documents=chunks,
            metadatas=[
                {
                    "filename": relative_filename,
                    "url": f"local://weekly-brief-{date_str}",
                    "content_hash": "",
                }
                for _ in chunks
            ],
            ids=[f"weekly_brief_{date_str}_chunk_{i}" for i in range(len(chunks))],
        )

    return {"status": "success", "note": note_data}


@router.get("/api/events/upcoming")
async def get_upcoming_events():
    try:
        index = get_url_index()
        events = []
        current_time = datetime.datetime.now(datetime.timezone.utc).isoformat()

        for url, data in index.items():
            if isinstance(data, dict) and data.get("event_date"):
                try:
                    if data["event_date"] >= current_time[:10]:
                        events.append(data)
                except:
                    pass

        events.sort(key=lambda x: x.get("event_date", ""))
        return events
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/suggestions")
async def get_suggestions():
    try:
        index = get_url_index()
        all_notes = []
        for url, data in index.items():
            if isinstance(data, dict):
                all_notes.append(data)

        if not all_notes:
            return []

        selected = random.sample(all_notes, min(3, len(all_notes)))
        return selected
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/serendipity")
async def get_serendipity():
    try:
        from core.serendipity import _get_serendipity_picks

        return _get_serendipity_picks()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/graph")
async def get_vault_graph():
    try:
        nodes_dict = {}
        edges = []
        category_map = {}
        cat_counter = 1

        for root, _, files in os.walk(PROJECT_VAULT_PATH):
            for file in files:
                if file.endswith(".md"):
                    filepath = os.path.join(root, file)
                    rel_path = os.path.relpath(filepath, PROJECT_VAULT_PATH)
                    parts = rel_path.split(os.sep)
                    if len(parts) > 1:
                        category = parts[0]
                    else:
                        category = "General"

                    if category not in category_map:
                        category_map[category] = cat_counter
                        cat_counter += 1

                    node_id = file.replace(".md", "")
                    nodes_dict[node_id] = {
                        "id": node_id,
                        "group": category_map[category],
                        "val": 1,
                        "category": category,
                    }

        connection_counts = {}
        for root, _, files in os.walk(PROJECT_VAULT_PATH):
            for file in files:
                if file.endswith(".md"):
                    node_id = file.replace(".md", "")
                    filepath = os.path.join(root, file)

                    with open(filepath, "r", encoding="utf-8") as f:
                        content = f.read()

                        links = re.findall(r'\[\[(.*?)\]\]', content)
                        for link in links:
                            link_target = link.split("|")[0].strip()
                            if not link_target:
                                continue

                            if link_target not in nodes_dict:
                                if "Linked" not in category_map:
                                    category_map["Linked"] = 0
                                nodes_dict[link_target] = {
                                    "id": link_target,
                                    "group": 0,
                                    "val": 1,
                                    "category": "Reference",
                                }

                            edges.append({"source": node_id, "target": link_target})
                            connection_counts[node_id] = (
                                connection_counts.get(node_id, 0) + 1
                            )
                            connection_counts[link_target] = (
                                connection_counts.get(link_target, 0) + 1
                            )

        for node_id, count in connection_counts.items():
            if node_id in nodes_dict:
                nodes_dict[node_id]["val"] = 1 + count * 2

        return {
            "nodes": list(nodes_dict.values()),
            "links": edges,
            "categories": list(category_map.keys()),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/inbox/pending")
async def get_pending_inbox():
    try:
        raw_dir = os.path.join(PROJECT_VAULT_PATH, "raw")
        if not os.path.exists(raw_dir):
            return {"count": 0, "files": []}
        files = [
            f for f in os.listdir(raw_dir) if f.endswith(".md") and not f.startswith("_")
        ]
        return {"count": len(files), "files": files}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/raw_count")
async def get_raw_count():
    try:
        raw_dir = os.path.join(PROJECT_VAULT_PATH, "raw")
        if not os.path.exists(raw_dir):
            return {"raw_count": 0}
        files = [
            f for f in os.listdir(raw_dir) if f.endswith(".md") and not f.startswith("_")
        ]
        return {"raw_count": len(files)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
