import os
import re
import datetime
import json
import uuid
from typing import List, Optional
from fastapi import FastAPI, HTTPException, Request, UploadFile, File
from fastapi.responses import StreamingResponse, PlainTextResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import chromadb

# Internal Imports
from core.config import OBSIDIAN_INBOX_PATH, PROJECT_VAULT_PATH, AI_MODEL, AI_MODEL_PRIMARY, AI_MODEL_FALLBACK, AI_MODEL_CHAIN, TAGS_FILE
from core.state import ops_manager, get_url_index, save_url_index
from core.utils import clean_url, chunk_text, cleanup_temp_files, get_platform_from_url
from core.processors import process_reel, process_image_post, generate_content_with_fallback, process_pdf, process_web_article


import asyncio
import shutil

# --- QUEUE SYSTEM ---
task_queue = asyncio.Queue()

async def background_worker():
    while True:
        task_info = await task_queue.get()
        url = task_info.get("url")
        task_id = task_info.get("task_id")

        ops_manager.update_task(task_id, "Processing from queue", state="active")

        try:
            await _run_ingestion_logic(url, task_id)
        except Exception as e:
            pass
        finally:
            task_queue.task_done()

# --- INITIALIZATION ---
app = FastAPI(title="Second Brain API")
@app.on_event("startup")
async def startup_event():
    asyncio.create_task(background_worker())
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Startup Cleanup
cleanup_temp_files()

print("Initializing ChromaDB...")
chroma_client = chromadb.PersistentClient(path="./chroma_db")
vault_collection = chroma_client.get_or_create_collection(name="vault_embeddings")

# --- MODELS ---
class IngestRequest(BaseModel):
    url: str

class AskRequest(BaseModel):
    message: str
    session_id: str = None

class SaveAnswerRequest(BaseModel):
    title: str
    content: str

def get_unique_filename(filename: str, category: str = None) -> str:
    stem, ext = os.path.splitext(filename)
    candidate = filename
    counter = 2
    while True:
        project_path = os.path.join(PROJECT_VAULT_PATH, category, candidate) if category else os.path.join(PROJECT_VAULT_PATH, candidate)
        obsidian_path = os.path.join(OBSIDIAN_INBOX_PATH, category, candidate) if category else os.path.join(OBSIDIAN_INBOX_PATH, candidate)

        if os.path.exists(project_path) or os.path.exists(obsidian_path):
            candidate = f"{stem} ({counter}){ext}"
            counter += 1
        else:
            break
    return candidate

# --- ROUTES ---

@app.get("/")
async def root():
    return {"message": "🧠 Second Brain API is Online", "docs": "/docs"}

@app.get("/api/health")
async def health_check():
    return {"status": "ok"}

@app.get("/api/status")
async def get_system_status():
    return ops_manager.get_status()

@app.get("/api/logs")
async def get_error_logs():
    if os.path.exists("error_log.json"):
        with open("error_log.json", "r") as f:
            return json.load(f)
    return []

@app.post("/api/logs/clear")
async def clear_error_logs():
    if os.path.exists("error_log.json"):
        os.remove("error_log.json")
    return {"status": "cleared"}

@app.get("/api/notes")
async def get_notes():
    index = get_url_index()
    notes = []
    for url, data in index.items():
        if isinstance(data, dict):
            notes.append(data)
        else:
            notes.append({"title": data.replace(".md", ""), "fileName": data, "date": "Unknown"})
    return sorted(notes, key=lambda x: x.get('date', ''), reverse=True)

@app.get("/api/notes/{filename:path}")
async def get_note_content(filename: str):
    # Try both locations
    paths = [os.path.join(OBSIDIAN_INBOX_PATH, filename), os.path.join(PROJECT_VAULT_PATH, filename)]
    for p in paths:
        if os.path.exists(p):
            with open(p, "r", encoding="utf-8") as f:
                return PlainTextResponse(f.read(), media_type="text/markdown")
    raise HTTPException(status_code=404, detail="Note not found")

@app.get("/api/config")
async def get_config():
    index = get_url_index()
    return {
        "model": AI_MODEL,
        "primary_model": AI_MODEL_PRIMARY,
        "fallback_model": AI_MODEL_FALLBACK,
        "model_chain": AI_MODEL_CHAIN,
        "note_count": len(index),
    }

@app.post("/api/sync")
async def sync_vault():
    import subprocess
    try:
        subprocess.run(["git", "add", "."], cwd=PROJECT_VAULT_PATH, check=True, capture_output=True, timeout=10)
        subprocess.run(["git", "commit", "-m", f"Auto-sync {datetime.datetime.now().isoformat()}"], cwd=PROJECT_VAULT_PATH, capture_output=True, timeout=10)
        subprocess.run(["git", "push"], cwd=PROJECT_VAULT_PATH, capture_output=True, timeout=30)
        return {"status": "success", "message": "Vault synced to GitHub"}
    except Exception as e:
        return {"status": "warning", "message": f"Sync attempted: {str(e)}"}

@app.post("/api/notes/{filename}/summarize")
async def summarize_note(filename: str):
    paths = [os.path.join(OBSIDIAN_INBOX_PATH, filename), os.path.join(PROJECT_VAULT_PATH, filename)]
    content = None
    for p in paths:
        if os.path.exists(p):
            with open(p, "r", encoding="utf-8") as f:
                content = f.read()
            break
    if not content:
        raise HTTPException(status_code=404, detail="Note not found")
    
    prompt = f"Provide a concise 3-5 bullet point summary of this note. Focus on actionable takeaways:\n\n{content}"
    response, model_used = generate_content_with_fallback(prompt, purpose="note_summary")
    return {"summary": response.text, "model": model_used}

@app.post("/api/notes/{filename}/deep_dive")
async def deep_dive_note(filename: str):
    paths = [os.path.join(OBSIDIAN_INBOX_PATH, filename), os.path.join(PROJECT_VAULT_PATH, filename)]
    content = None
    for p in paths:
        if os.path.exists(p):
            with open(p, "r", encoding="utf-8") as f:
                content = f.read()
            break
    if not content:
        raise HTTPException(status_code=404, detail="Note not found")
    
    prompt = f"Provide a detailed analysis of this note. Include: (1) Key concepts explained, (2) Connections to broader topics, (3) Questions worth exploring further, (4) Practical applications. Format with markdown headers:\n\n{content}"
    response, model_used = generate_content_with_fallback(prompt, purpose="note_deep_dive")
    return {"deep_dive": response.text, "model": model_used}

@app.post("/api/ingest")
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
        ops_manager.start_task(task_id, url, "Queued", platform=platform, progress=0, state="queued")
        await task_queue.put({"url": url, "task_id": task_id})
        return {"status": "queued", "task_id": task_id, "message": "Task added to background queue"}

    async def _run_ingestion(url: str, status_callback=None):
        task_id = f"task_{uuid.uuid4().hex[:8]}"
        platform = get_platform_from_url(url)
        if status_callback: await status_callback("Checking index")
        ops_manager.start_task(task_id, url, "Checking index", platform=platform, progress=5)
        return await _run_ingestion_logic(url, task_id, status_callback)

    if wants_stream:
        async def stream():
            try:
                async def on_status(msg):
                    nonlocal stream_queue
                    await stream_queue.put(json.dumps({"status": "status", "message": f"{msg}..."}) + "\n")

                import asyncio
                stream_queue = asyncio.Queue()
                
                async def run_task():
                    try:
                        res = await _run_ingestion(url, on_status)
                        await stream_queue.put(json.dumps(res) + "\n")
                    except Exception as e:
                        await stream_queue.put(json.dumps({"status": "error", "message": str(e)}) + "\n")
                    finally:
                        await stream_queue.put(None)

                asyncio.create_task(run_task())
                
                while True:
                    item = await stream_queue.get()
                    if item is None: break
                    yield item
            except Exception as e:
                yield json.dumps({"status": "error", "message": str(e)}) + "\n"
        return StreamingResponse(stream(), media_type="application/x-ndjson")
    
    try:
        return await _run_ingestion(url)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
        
async def _run_ingestion_logic(url: str, task_id: str, status_callback=None):
    platform = get_platform_from_url(url)
    try:
        index = get_url_index()
        if url in index:
            note_data = index[url]
            fn = note_data['fileName'] if isinstance(note_data, dict) else note_data
            if any(os.path.exists(os.path.join(path, fn)) for path in [OBSIDIAN_INBOX_PATH, PROJECT_VAULT_PATH]):
                ops_manager.end_task(task_id, "Already exists", state="existing")
                return {
                    "status": "existing",
                    "task_id": task_id,
                    "note": note_data if isinstance(note_data, dict) else {"fileName": fn, "title": fn},
                }

        if "instagram.com" in url and ("/reel/" not in url and "/p/" in url):
            data = await process_image_post(url, task_id, status_callback)
        elif platform == "youtube" or platform == "tiktok" or ("instagram.com" in url and "/reel/" in url):
            data = await process_reel(url, task_id, status_callback)
        else:
            data = await process_web_article(url, task_id, status_callback)

        # MD5 Duplicate Detection
        if status_callback: await status_callback("Checking content fingerprint")
        ops_manager.update_task(task_id, "Checking content fingerprint", progress=80)
        index = get_url_index()
        content_hash = data.get('content_hash')
        if content_hash:
            for existing_url, existing_data in index.items():
                if isinstance(existing_data, dict) and existing_data.get('content_hash') == content_hash:
                    ops_manager.end_task(task_id, "Duplicate content", state="existing")
                    return {
                        "status": "existing",
                        "task_id": task_id,
                        "message": "Content already exists in vault (detected via MD5)",
                        "note": existing_data
                    }

        if status_callback: await status_callback("Saving to vaults")
        ops_manager.update_task(task_id, "Saving to vaults", progress=85)
        date_str = datetime.datetime.now().strftime("%Y-%m-%d")
        safe_uploader = re.sub(r'[\\/*?:"<>|]', "", data['uploader'])
        raw_category = data['ai_data'].get('category', 'Post')
        safe_category = re.sub(r'[\\/*?:"<>|]', "-", raw_category)
        filename = get_unique_filename(f"{date_str} - {safe_category} from {data['platform'].capitalize()} ({safe_uploader}).md", category=safe_category)

        # Subfolder structuring based on category
        project_category_path = os.path.join(PROJECT_VAULT_PATH, safe_category)
        obsidian_category_path = os.path.join(OBSIDIAN_INBOX_PATH, safe_category)
        os.makedirs(project_category_path, exist_ok=True)
        os.makedirs(obsidian_category_path, exist_ok=True)

        project_filepath = os.path.join(project_category_path, filename)
        obsidian_filepath = os.path.join(obsidian_category_path, filename)
        raw_transcript = (data.get("raw_transcript") or "").strip()
        transcript_status = data.get("transcript_status") or ("complete" if raw_transcript else "not_available")
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
        event_date_str = f"event_date: {event_date}\n" if event_date and str(event_date).lower() != "null" else ""

        content = f"""---
type: {data['type']}
date: {date_str}
author: {data['uploader']}
url: {data['url']}
category: {raw_category}
tags: {data['ai_data'].get('tags', [])}
{event_date_str}content_hash: {data.get('content_hash', '')}
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
        with open(project_filepath, "w", encoding="utf-8") as f: f.write(content)
        with open(obsidian_filepath, "w", encoding="utf-8") as f: f.write(content)

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
        }
        index = get_url_index()
        index[url] = note_data
        save_url_index(index)

        if status_callback: await status_callback("Updating AI index")
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
            vault_collection.add(
                documents=chunks,
                metadatas=[{"filename": relative_filename, "url": url, "content_hash": data.get("content_hash")} for _ in chunks],
                ids=[f"{content_hash or uuid.uuid4().hex}_chunk_{i}" for i in range(len(chunks))]
            )
        ops_manager.end_task(task_id, "Completed", state="completed")
        return {"status": "success", "task_id": task_id, "note": note_data}
    except Exception as e:
        import traceback
        ops_manager.log_error(url, str(e), detail=traceback.format_exc())
        ops_manager.end_task(task_id, "Failed", state="failed", error=str(e))
        raise e

# --- CHAT HISTORY STORAGE ---
CHAT_HISTORY_FILE = "chat_history.json"

def load_chat_history():
    if os.path.exists(CHAT_HISTORY_FILE):
        with open(CHAT_HISTORY_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}

def save_chat_history(history):
    with open(CHAT_HISTORY_FILE, "w", encoding="utf-8") as f:
        json.dump(history, f, indent=2)

@app.post("/api/chat")
async def chat(request: AskRequest):
    try:
        session_id = request.session_id or str(uuid.uuid4())

        # Determine chat history context
        chat_history_db = load_chat_history()
        session_history = chat_history_db.get(session_id, [])

        # Build context from previous messages (up to 5 recent)
        history_context = ""
        if session_history:
            history_context = "Previous conversation:\n"
            for msg in session_history[-5:]:
                history_context += f"User: {msg['query']}\nAI: {msg['response']}\n"
            history_context += "\n"

        results = vault_collection.query(query_texts=[request.message], n_results=5)
        ctx = "\n".join(results['documents'][0]) if results['documents'] and results['documents'][0] else ""

        prompt = f"Answer based on these notes:\n\n{ctx}\n\n{history_context}Question: {request.message}"
        response, model_used = generate_content_with_fallback(prompt, purpose="rag_chat")

        # Save to history
        chat_entry = {
            "timestamp": datetime.datetime.now().isoformat(),
            "query": request.message,
            "response": response.text,
            "model_used": model_used
        }
        if session_id not in chat_history_db:
            chat_history_db[session_id] = []
        chat_history_db[session_id].append(chat_entry)
        save_chat_history(chat_history_db)

        return {
            "response": response.text,
            "model": model_used,
            "session_id": session_id
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/upload")
async def upload_file(file: UploadFile = File(...)):
    if not file.filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Only PDF files are currently supported")

    task_id = f"task_{uuid.uuid4().hex[:8]}"
    ops_manager.start_task(task_id, file.filename, "Uploading file", platform="local", progress=5)

    import shutil
    safe_filename = os.path.basename(file.filename)
    temp_path = f"temp_upload_{uuid.uuid4().hex}_{safe_filename}"
    try:
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        data = await process_pdf(temp_path, safe_filename, task_id)

        # Save to vaults
        ops_manager.update_task(task_id, "Saving to vaults", progress=85)
        date_str = datetime.datetime.now().strftime("%Y-%m-%d")
        safe_uploader = re.sub(r'[\/*?:"<>|]', "", data['uploader'])
        raw_category = data['ai_data'].get('category', 'Document')
        safe_category = re.sub(r'[\/*?:"<>|]', "-", raw_category)
        filename = get_unique_filename(f"{date_str} - {safe_category} ({safe_uploader}).md", category=safe_category)

        project_category_path = os.path.join(PROJECT_VAULT_PATH, safe_category)
        obsidian_category_path = os.path.join(OBSIDIAN_INBOX_PATH, safe_category)
        os.makedirs(project_category_path, exist_ok=True)
        os.makedirs(obsidian_category_path, exist_ok=True)

        project_filepath = os.path.join(project_category_path, filename)
        obsidian_filepath = os.path.join(obsidian_category_path, filename)

        event_date = data.get('ai_data', {}).get('event_date')
        event_date_str = f"event_date: {event_date}\n" if event_date and str(event_date).lower() != "null" else ""

        content = f"""---
type: {data['type']}
date: {date_str}
author: {data['uploader']}
url: {data['url']}
category: {raw_category}
tags: {data['ai_data'].get('tags', [])}
{event_date_str}content_hash: {data.get('content_hash', '')}
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
        with open(project_filepath, "w", encoding="utf-8") as f: f.write(content)
        with open(obsidian_filepath, "w", encoding="utf-8") as f: f.write(content)

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
        }

        # Update JSON index
        index = get_url_index()
        index[data['url']] = note_data
        save_url_index(index)

        # Update Vector DB
        ops_manager.update_task(task_id, "Updating AI index", progress=95)
        index_text = "\n\n".join([data['ai_data'].get('formatted_content', ''), data.get('raw_transcript', '')])
        chunks = [chunk for chunk in chunk_text(index_text) if chunk.strip()]
        if chunks:
            vault_collection.add(
                documents=chunks,
                metadatas=[{"filename": relative_filename, "url": data['url'], "content_hash": data.get("content_hash")} for _ in chunks],
                ids=[f"{data.get('content_hash') or uuid.uuid4().hex}_chunk_{i}" for i in range(len(chunks))]
            )

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

@app.get("/api/chats")
async def get_chats():
    try:
        chat_history_db = load_chat_history()
        sessions = []
        for session_id, messages in chat_history_db.items():
            if messages:
                # Use the first query as the session title
                title = messages[0]["query"][:50] + ("..." if len(messages[0]["query"]) > 50 else "")
                last_updated = messages[-1]["timestamp"]
                sessions.append({
                    "session_id": session_id,
                    "title": title,
                    "last_updated": last_updated,
                    "message_count": len(messages)
                })
        # Sort by most recent
        sessions.sort(key=lambda x: x["last_updated"], reverse=True)
        return {"sessions": sessions}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/chats/{session_id}")
async def get_chat_session(session_id: str):
    try:
        chat_history_db = load_chat_history()
        if session_id not in chat_history_db:
            raise HTTPException(status_code=404, detail="Chat session not found")
        return {"session_id": session_id, "messages": chat_history_db[session_id]}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/events/upcoming")
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

@app.get("/api/suggestions")
async def get_suggestions():
    try:
        index = get_url_index()
        all_notes = []
        for url, data in index.items():
            if isinstance(data, dict):
                all_notes.append(data)

        if not all_notes:
            return []

        import random
        selected = random.sample(all_notes, min(3, len(all_notes)))
        return selected
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/graph")
async def get_vault_graph():
    try:
        nodes = []
        edges = []
        node_ids = set()

        def add_node(node_id, group=1):
            if node_id not in node_ids:
                nodes.append({"id": node_id, "group": group})
                node_ids.add(node_id)

        import glob
        for root, _, files in os.walk(PROJECT_VAULT_PATH):
            for file in files:
                if file.endswith(".md"):
                    filepath = os.path.join(root, file)
                    node_id = file.replace(".md", "")
                    add_node(node_id, group=1)

                    with open(filepath, "r", encoding="utf-8") as f:
                        content = f.read()

                        links = re.findall(r'\[\[(.*?)\]\]', content)
                        for link in links:
                            link_target = link.split("|")[0]
                            add_node(link_target, group=2)
                            edges.append({"source": node_id, "target": link_target})

        return {"nodes": nodes, "links": edges}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

class RenameTagRequest(BaseModel):
    old_tag: str
    new_tag: str

@app.get("/api/tags")
async def get_tags():
    try:
        tags = []
        if os.path.exists(TAGS_FILE):
            with open(TAGS_FILE, "r", encoding="utf-8") as f:
                tags = [line.strip() for line in f if line.strip()]

        return {"tags": tags}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.put("/api/tags/rename")
async def rename_tag(request: RenameTagRequest):
    try:
        old_t = request.old_tag
        new_t = request.new_tag

        if not old_t or not new_t:
             raise HTTPException(status_code=400, detail="Both old and new tags are required")

        if os.path.exists(TAGS_FILE):
            with open(TAGS_FILE, "r", encoding="utf-8") as f:
                tags = [line.strip() for line in f if line.strip()]

            tags = [new_t if t == old_t else t for t in tags]
            tags = sorted(list(set(tags)))

            with open(TAGS_FILE, "w", encoding="utf-8") as f:
                for t in tags:
                    f.write(f"{t}\n")

        updated_count = 0
        for vault_dir in [PROJECT_VAULT_PATH, OBSIDIAN_INBOX_PATH]:
            for root, _, files in os.walk(vault_dir):
                for file in files:
                    if file.endswith(".md"):
                        filepath = os.path.join(root, file)
                        with open(filepath, "r", encoding="utf-8") as f:
                            content = f.read()
                        if old_t in content:
                            content = re.sub(rf'(?<!\S)#{re.escape(old_t)}\b', f'#{new_t}', content)
                            with open(filepath, "w", encoding="utf-8") as f:
                                f.write(content)
                            if vault_dir == PROJECT_VAULT_PATH:
                                updated_count += 1

        return {"status": "success", "message": f"Updated tag in {updated_count} files"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/save_answer")
async def save_answer(request: SaveAnswerRequest):
    try:
        date_str = datetime.datetime.now().strftime("%Y-%m-%d")
        safe_title = re.sub(r'[\\/*?:"<>|]', "", request.title)
        filename = f"Synthesis - {safe_title}.md"
        filepath = os.path.join(OBSIDIAN_INBOX_PATH, filename)
        content = f"---\ntype: saved_answer\ndate: {date_str}\ncategory: Synthesis\n---\n# {request.title}\n\n{request.content}"
        with open(filepath, "w", encoding="utf-8") as f: f.write(content)
        return {"status": "success", "fileName": filename}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
