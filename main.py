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
from core.processors import process_reel, process_image_post, generate_content_with_fallback, process_pdf, process_web_article, process_text_file, process_raw_text, process_audio_file, process_uploaded_image


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
    session_id: Optional[str] = None
    note_context: Optional[str] = None

class SaveAnswerRequest(BaseModel):
    title: str
    content: str

class ReviewRequest(BaseModel):
    fileName: str

class AppendTasksRequest(BaseModel):
    tasks: str



CATEGORY_SUMMARIES_CACHE = {}

def extract_summary_from_md(filepath):
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()
        match = re.search(r'> \*\*AI Summary:\*\* (.*)', content)
        if match:
            return match.group(1).strip()
        body = content
        if content.startswith("---\n"):
            end_idx = content.find("\n---\n", 4)
            if end_idx != -1:
                body = content[end_idx+5:]
        
        lines = [l.strip() for l in body.split("\n") if l.strip() and not l.strip().startswith("#") and not l.strip().startswith(">")]
        if lines:
            summary = lines[0]
            if len(summary) > 100:
                summary = summary[:97] + "..."
            return summary
    except Exception:
        pass
    return "No summary available."

def update_hierarchical_indexes():
    """Generates _master-index.md and _index.md for each category to maintain the AI Librarian structure."""
    global CATEGORY_SUMMARIES_CACHE
    for vault_path in [PROJECT_VAULT_PATH, OBSIDIAN_INBOX_PATH]:
        if not os.path.exists(vault_path):
            continue
            
        categories = {}
        for item in os.listdir(vault_path):
            cat_path = os.path.join(vault_path, item)
            if os.path.isdir(cat_path):
                md_files = [f for f in os.listdir(cat_path) if f.endswith('.md') and f != '_index.md']
                if not md_files:
                    continue
                categories[item] = len(md_files)
                
                # Extract summaries for each file in this category
                file_summaries = {}
                for md in md_files:
                    filepath = os.path.join(cat_path, md)
                    summary = extract_summary_from_md(filepath)
                    file_summaries[md.replace(".md", "")] = summary
                
                # Get or generate category summary
                cache_key = f"{item}:{','.join(sorted(md_files))}"
                if cache_key in CATEGORY_SUMMARIES_CACHE:
                    cat_summary = CATEGORY_SUMMARIES_CACHE[cache_key]
                else:
                    prompt = (
                        f"Describe the category/topic '{item}' in one brief, engaging sentence based on "
                        f"the following articles inside it:\n"
                        + "\n".join([f"- {title}: {sum_val}" for title, sum_val in file_summaries.items()])
                    )
                    try:
                        res, _ = generate_content_with_fallback(prompt, purpose="category_summary")
                        cat_summary = res.text.strip()
                    except Exception:
                        cat_summary = f"Articles related to {item}."
                    CATEGORY_SUMMARIES_CACHE[cache_key] = cat_summary
                
                index_content = f"# {item} Index\n\n{cat_summary}\n\nThis folder contains {len(md_files)} articles related to {item}.\n\n## Articles\n"
                for title, summary in file_summaries.items():
                    index_content += f"- [[{title}]]: {summary}\n"
                
                with open(os.path.join(cat_path, "_index.md"), "w", encoding="utf-8") as f:
                    f.write(index_content)
        
        master_content = "# Knowledge Base Master Index\n\nTopics appear here as they're created.\n\n"
        for cat, count in categories.items():
            # Try to get the category summary from cache
            cat_summary = ""
            for k, val in CATEGORY_SUMMARIES_CACHE.items():
                if k.startswith(f"{cat}:"):
                    cat_summary = val
                    break
            if not cat_summary:
                cat_summary = f"Articles related to {cat}."
                
            master_content += f"- **[[{cat}/_index|{cat}]]**: {count} articles\n  *{cat_summary}*\n"
            
        with open(os.path.join(vault_path, "_master-index.md"), "w", encoding="utf-8") as f:
            f.write(master_content)


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

@app.post("/api/notes/{filename:path}/summarize")
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

@app.post("/api/notes/{filename:path}/deep_dive")
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

@app.post("/api/notes/{filename:path}/extract_tasks")
async def extract_tasks(filename: str):
    paths = [os.path.join(OBSIDIAN_INBOX_PATH, filename), os.path.join(PROJECT_VAULT_PATH, filename)]
    content = None
    for p in paths:
        if os.path.exists(p):
            with open(p, "r", encoding="utf-8") as f:
                content = f.read()
            break
    if not content:
        raise HTTPException(status_code=404, detail="Note not found")
    
    prompt = (
        "Analyze the following note content and extract a clean list of actionable checklist items (tasks/next steps). "
        "Format them using Obsidian Markdown task syntax (- [ ] Task description). "
        "Keep them highly specific and concise. Respond ONLY with the list of tasks (no headers, intro, or wrap-up text):\n\n"
        f"{content}"
    )
    response, model_used = generate_content_with_fallback(prompt, purpose="task_extraction")
    return {"tasks": response.text.strip(), "model": model_used}

@app.post("/api/notes/{filename:path}/append_tasks")
async def append_tasks(filename: str, request: AppendTasksRequest):
    paths = [os.path.join(OBSIDIAN_INBOX_PATH, filename), os.path.join(PROJECT_VAULT_PATH, filename)]
    filepaths_found = [p for p in paths if os.path.exists(p)]
    if not filepaths_found:
        raise HTTPException(status_code=404, detail="Note not found")
    
    for path in filepaths_found:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
        
        # Append tasks before the original caption or at the end
        new_content = content + f"\n\n## Actionable Tasks\n{request.tasks}\n"
        with open(path, "w", encoding="utf-8") as f:
            f.write(new_content)
            
    return {"status": "success", "message": "Tasks successfully appended to note"}

@app.get("/api/weekly_brief")
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
        raise HTTPException(status_code=400, detail="No new notes ingested in the last 7 days to generate a brief.")
        
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
    
    response, model_used = generate_content_with_fallback(prompt, purpose="weekly_brief")
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
        "ai_model": model_used
    }
    
    index[f"local://weekly-brief-{date_str}"] = note_data
    save_url_index(index)
    
    # Also index the Weekly Brief in ChromaDB
    chunks = [chunk for chunk in chunk_text(brief_text) if chunk.strip()]
    if chunks:
        vault_collection.add(
            documents=chunks,
            metadatas=[{"filename": relative_filename, "url": f"local://weekly-brief-{date_str}", "content_hash": ""} for _ in chunks],
            ids=[f"weekly_brief_{date_str}_chunk_{i}" for i in range(len(chunks))]
        )
        
    return {"status": "success", "note": note_data}



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
        
        # Update AI Librarian indexes
        update_hierarchical_indexes()
        
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

        note_context_text = ""
        if request.note_context:
            paths = [
                os.path.join(OBSIDIAN_INBOX_PATH, request.note_context),
                os.path.join(PROJECT_VAULT_PATH, request.note_context)
            ]
            for p in paths:
                if os.path.exists(p):
                    try:
                        with open(p, "r", encoding="utf-8") as f:
                            note_content = f.read()
                            note_context_text = f"Context from active note ({request.note_context}):\n{note_content}\n\n"
                    except Exception:
                        pass
                    break

        results = vault_collection.query(query_texts=[request.message], n_results=5)
        ctx = "\n".join(results['documents'][0]) if results['documents'] and results['documents'][0] else ""

        prompt = f"Answer based on these notes:\n\n{note_context_text}{ctx}\n\n{history_context}Question: {request.message}\n\nIMPORTANT INSTRUCTION: When referencing important concepts, people, or topics in your answer, wrap them in Obsidian-style wiki links like [[Concept Name]]."
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
    filename_lower = file.filename.lower()
    IMAGE_EXTS = (".jpg", ".jpeg", ".png", ".webp")
    AUDIO_EXTS = (".mp3", ".wav", ".m4a", ".ogg", ".aac")
    TEXT_EXTS = (".txt", ".md")
    
    is_valid = (
        filename_lower.endswith(".pdf") or
        any(filename_lower.endswith(ext) for ext in IMAGE_EXTS) or
        any(filename_lower.endswith(ext) for ext in AUDIO_EXTS) or
        any(filename_lower.endswith(ext) for ext in TEXT_EXTS)
    )
    if not is_valid:
        raise HTTPException(
            status_code=400, 
            detail="Unsupported format. Only PDF, images (JPG/PNG/WEBP), audio (MP3/WAV/M4A), and text (TXT/MD) files are supported."
        )

    task_id = f"task_{uuid.uuid4().hex[:8]}"
    ops_manager.start_task(task_id, file.filename, "Uploading file", platform="local", progress=5)

    import shutil
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

class IngestTextRequest(BaseModel):
    text: str
    title: Optional[str] = "Shared Text"

@app.post("/api/ingest_text")
async def ingest_text(request: IngestTextRequest):
    if not request.text.strip():
        raise HTTPException(status_code=400, detail="Text content is required")

    task_id = f"task_{uuid.uuid4().hex[:8]}"
    ops_manager.start_task(task_id, request.title, "Ingesting raw text", platform="local", progress=10)

    try:
        # Process raw text using our helper
        data = await process_raw_text(request.text, request.title, task_id)

        # Save to vaults
        ops_manager.update_task(task_id, "Saving to vaults", progress=85)
        date_str = datetime.datetime.now().strftime("%Y-%m-%d")
        raw_category = data['ai_data'].get('category', 'General')
        safe_category = re.sub(r'[\/*?:"<>|]', "-", raw_category)
        filename = get_unique_filename(f"{date_str} - {safe_category} (Shared Text).md", category=safe_category)

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

## Original Text
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
        ops_manager.log_error(request.title, str(e), detail=traceback.format_exc())
        ops_manager.end_task(task_id, "Failed", state="failed", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

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

@app.get("/api/serendipity")
async def get_serendipity():
    try:
        index = get_url_index()
        all_notes = []
        now = datetime.datetime.now()
        
        for url, data in index.items():
            if isinstance(data, dict):
                date_str = data.get("date")
                if date_str:
                    try:
                        dt = datetime.datetime.fromisoformat(date_str.replace("Z", "+00:00"))
                    except Exception:
                        dt = now
                else:
                    dt = now
                
                all_notes.append({
                    "url": url,
                    "title": data.get("title", ""),
                    "fileName": data.get("fileName", ""),
                    "date": date_str,
                    "last_reviewed": data.get("last_reviewed"),
                    "dt": dt
                })
        
        if not all_notes:
            return []
            
        def sort_key(note):
            last_rev = note["last_reviewed"]
            has_rev = 1 if last_rev else 0
            rev_time = last_rev if last_rev else ""
            return (has_rev, rev_time, note["date"])
            
        sorted_notes = sorted(all_notes, key=sort_key)
        
        import random
        pool = sorted_notes[:min(15, len(sorted_notes))]
        selected = random.sample(pool, min(3, len(pool)))
        
        results = []
        for note in selected:
            summary = ""
            filename = note["fileName"]
            paths = [
                os.path.join(OBSIDIAN_INBOX_PATH, filename),
                os.path.join(PROJECT_VAULT_PATH, filename)
            ]
            for p in paths:
                if os.path.exists(p):
                    try:
                        with open(p, "r", encoding="utf-8") as f:
                            content = f.read()
                        match = re.search(r'> \*\*AI Summary:\*\* (.*)', content)
                        if match:
                            summary = match.group(1).strip()
                        else:
                            match_body = re.search(r'# .*\n\n> (.*)', content)
                            if match_body:
                                summary = match_body.group(1).strip()
                    except Exception:
                        pass
                    break
            
            results.append({
                "url": note["url"],
                "title": note["title"],
                "fileName": filename,
                "date": note["date"],
                "last_reviewed": note["last_reviewed"],
                "summary": summary
            })
            
        return results
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/notes/reviewed")
async def mark_note_reviewed(request: ReviewRequest):
    try:
        index = get_url_index()
        target_url = None
        for url, data in index.items():
            if isinstance(data, dict) and data.get("fileName") == request.fileName:
                target_url = url
                break
                
        if not target_url:
            raise HTTPException(status_code=404, detail="Note not found in index")
            
        now_str = datetime.datetime.now().isoformat()
        index[target_url]["last_reviewed"] = now_str
        save_url_index(index)
        
        paths = [
            os.path.join(OBSIDIAN_INBOX_PATH, request.fileName),
            os.path.join(PROJECT_VAULT_PATH, request.fileName)
        ]
        for p in paths:
            if os.path.exists(p):
                with open(p, "r", encoding="utf-8") as f:
                    content = f.read()
                
                if content.startswith("---\n"):
                    end_idx = content.find("\n---\n", 4)
                    if end_idx != -1:
                        frontmatter = content[4:end_idx]
                        body = content[end_idx+5:]
                        
                        if "last_reviewed:" in frontmatter:
                            frontmatter = re.sub(r'last_reviewed:.*', f'last_reviewed: {now_str}', frontmatter)
                        else:
                            frontmatter += f"\nlast_reviewed: {now_str}"
                            
                        new_content = f"---\n{frontmatter}\n---\n{body}"
                        with open(p, "w", encoding="utf-8") as f:
                            f.write(new_content)
                            
        return {"status": "success", "message": "Note marked as reviewed"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/graph")
async def get_vault_graph():
    try:
        nodes_dict = {}
        edges = []
        category_map = {}
        cat_counter = 1

        import glob
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
                        "category": category
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
                                    "category": "Reference"
                                }
                            
                            edges.append({"source": node_id, "target": link_target})
                            connection_counts[node_id] = connection_counts.get(node_id, 0) + 1
                            connection_counts[link_target] = connection_counts.get(link_target, 0) + 1

        for node_id, count in connection_counts.items():
            if node_id in nodes_dict:
                nodes_dict[node_id]["val"] = 1 + count * 2

        return {
            "nodes": list(nodes_dict.values()),
            "links": edges,
            "categories": list(category_map.keys())
        }
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

def find_ghost_topics():
    existing_titles = set()
    note_to_path = {}
    
    for root, _, files in os.walk(PROJECT_VAULT_PATH):
        for file in files:
            if file.endswith(".md") and not file.startswith("_"):
                title = file.replace(".md", "")
                existing_titles.add(title.lower())
                existing_titles.add(title)
                note_to_path[title.lower()] = os.path.relpath(os.path.join(root, file), PROJECT_VAULT_PATH).replace("\\", "/")
                
    ghost_topics = {}
    
    for root, _, files in os.walk(PROJECT_VAULT_PATH):
        for file in files:
            if file.endswith(".md") and not file.startswith("_"):
                filepath = os.path.join(root, file)
                rel_path = os.path.relpath(filepath, PROJECT_VAULT_PATH).replace("\\", "/")
                try:
                    with open(filepath, "r", encoding="utf-8") as f:
                        content = f.read()
                    
                    links = re.findall(r'\[\[(.*?)\]\]', content)
                    for link in links:
                        target = link.split("|")[0].strip()
                        if not target or target.endswith("_index") or target == "_master-index":
                            continue
                        
                        target_clean = target.split("/")[-1]
                        if target_clean.lower() not in existing_titles and target.lower() not in existing_titles:
                            if target_clean not in ghost_topics:
                                ghost_topics[target_clean] = []
                            if rel_path not in ghost_topics[target_clean]:
                                ghost_topics[target_clean].append(rel_path)
                except Exception as e:
                    print(f"Error scanning links in {file}: {e}")
                    
    ghost_list = []
    for title, sources in ghost_topics.items():
        ghost_list.append({
            "title": title,
            "sources": sources
        })
    return ghost_list

@app.post("/api/audit")
async def audit_vault():
    try:
        # Find ghost topics programmatically
        ghost_list = find_ghost_topics()
        
        # Gather note titles and summaries
        notes_summary_list = []
        for root, _, files in os.walk(PROJECT_VAULT_PATH):
            for file in files:
                if file.endswith(".md") and not file.startswith("_"):
                    title = file.replace(".md", "")
                    filepath = os.path.join(root, file)
                    summary = extract_summary_from_md(filepath)
                    notes_summary_list.append(f"Title: {title}\nSummary: {summary}\n---")
                    
        notes_summary_str = "\n".join(notes_summary_list)
        
        prompt = f"""
You are an expert AI Librarian. Analyze the following list of articles and summaries from our Knowledge Base Vault.

Check for:
1. Conflicting claims or outdated information across articles (e.g. contradictions in facts, dates, advice).
2. Gaps in coverage (suggest 3-5 specific articles to add to round out the topics).

Articles list:
{notes_summary_str}

Format your response as a valid JSON object matching the following structure:
{{
  "inconsistencies": [
    {{
      "articles": ["Article Title A", "Article Title B"],
      "conflict": "Description of the contradiction or outdated info"
    }}
  ],
  "gaps": [
    {{
      "suggested_title": "Suggested Article Title",
      "reason": "Why this is a gap and what it should cover"
    }}
  ]
}}

Ensure the output is ONLY valid JSON, with no markdown code fences, leading/trailing backticks, or extra text.
"""
        response, model_used = generate_content_with_fallback(prompt, purpose="vault_audit")
        
        # Parse JSON
        ai_analysis = {"inconsistencies": [], "gaps": []}
        try:
            cleaned_text = response.text.strip()
            if cleaned_text.startswith("```json"):
                cleaned_text = cleaned_text[7:]
            if cleaned_text.endswith("```"):
                cleaned_text = cleaned_text[:-3]
            cleaned_text = cleaned_text.strip()
            ai_analysis = json.loads(cleaned_text)
        except Exception as e:
            print(f"Error parsing AI audit JSON: {e}")
            
        inconsistencies = ai_analysis.get("inconsistencies", [])
        gaps = ai_analysis.get("gaps", [])
        
        # Save results to output/Vault-Audit-[Date].md
        date_str = datetime.datetime.now().strftime("%Y-%m-%d")
        os.makedirs("output", exist_ok=True)
        filepath = os.path.join("output", f"Vault-Audit-{date_str}.md")
        
        # Build markdown report
        ghosts_md = ""
        if not ghost_list:
            ghosts_md = "*No missing articles referenced via [[links]] found.*\n"
        else:
            for g in ghost_list:
                sources_str = ", ".join([f"[[{s.replace('.md', '')}]]" for s in g['sources']])
                ghosts_md += f"- [ ] **[[{g['title']}]]** - referenced in: {sources_str}\n"
                
        inconsistencies_md = ""
        if not inconsistencies:
            inconsistencies_md = "*No conflicting claims or outdated information detected.*\n"
        else:
            for inc in inconsistencies:
                articles_str = " and ".join([f"[[{art}]]" for art in inc['articles']])
                inconsistencies_md += f"- **Conflict between {articles_str}**: {inc['conflict']}\n"
                
        gaps_md = ""
        if not gaps:
            gaps_md = "*No significant coverage gaps detected.*\n"
        else:
            for gap in gaps:
                gaps_md += f"- **[[{gap['suggested_title']}]]**: {gap['reason']}\n"
                
        markdown_content = f"""---
type: audit-report
date: {date_str}
category: Audit
---
# Vault Audit Report - {date_str}

## Programmatic Analysis

### Ghost Topics (Missing Articles referenced via [[links]])
{ghosts_md}

## AI Analysis

### Conflicting Claims & Outdated Information
{inconsistencies_md}

### Gaps in Coverage (Suggested Articles to Add)
{gaps_md}
"""
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(markdown_content)
            
        update_hierarchical_indexes()
        
        return {
            "status": "success",
            "fileName": f"output/Vault-Audit-{date_str}.md",
            "ghost_topics": ghost_list,
            "inconsistencies": inconsistencies,
            "gaps": gaps
        }
    except Exception as e:
        import traceback
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=str(e))

class CreateNoteRequest(BaseModel):
    title: str
    category: str
    content: Optional[str] = ""

@app.post("/api/notes/create")
async def create_note(request: CreateNoteRequest):
    try:
        date_str = datetime.datetime.now().strftime("%Y-%m-%d")
        safe_title = re.sub(r'[\\/*?:"<>|]', "", request.title)
        safe_category = re.sub(r'[\\/*?:"<>|]', "-", request.category)
        
        filename = f"{safe_title}.md"
        project_category_path = os.path.join(PROJECT_VAULT_PATH, safe_category)
        obsidian_category_path = os.path.join(OBSIDIAN_INBOX_PATH, safe_category)
        os.makedirs(project_category_path, exist_ok=True)
        os.makedirs(obsidian_category_path, exist_ok=True)
        
        project_filepath = os.path.join(project_category_path, filename)
        obsidian_filepath = os.path.join(obsidian_category_path, filename)
        
        if os.path.exists(project_filepath) or os.path.exists(obsidian_filepath):
             raise HTTPException(status_code=400, detail="Note already exists")
             
        content = f"""---
type: note
date: {date_str}
category: {request.category}
tags: ["#inbox"]
---
# {request.title}

{request.content or "Draft article created via Vault Audit."}
"""
        with open(project_filepath, "w", encoding="utf-8") as f:
            f.write(content)
        with open(obsidian_filepath, "w", encoding="utf-8") as f:
            f.write(content)
            
        relative_filename = os.path.join(safe_category, filename).replace("\\", "/")
        note_data = {
            "title": request.title,
            "fileName": relative_filename,
            "date": datetime.datetime.now().isoformat(),
            "url": f"local://{relative_filename}",
            "category": request.category,
            "tags": ["#inbox"]
        }
        
        index = get_url_index()
        index[f"local://{relative_filename}"] = note_data
        save_url_index(index)
        
        update_hierarchical_indexes()
        
        return {"status": "success", "note": note_data}
    except HTTPException:
        raise
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
        
        # Add to index mapping
        index = get_url_index()
        index[filename] = {
            "title": request.title,
            "fileName": filename,
            "date": date_str,
            "category": "Synthesis"
        }
        save_url_index(index)
        
        # Trigger hierarchical indexing update
        update_hierarchical_indexes()
        
        return {"status": "success", "fileName": filename}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
