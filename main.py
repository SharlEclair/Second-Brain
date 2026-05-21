import math
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


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate the great-circle distance between two points on Earth (in km)."""
    R = 6371.0  # Earth's radius in km
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat / 2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon / 2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c


import asyncio
import shutil

# Safe Import of Firebase Admin SDK
try:
    import firebase_admin
    from firebase_admin import credentials, messaging
    HAS_FIREBASE = True
except ImportError:
    HAS_FIREBASE = False
    print("firebase-admin library not installed. FCM notifications are disabled.")

# Initialize Firebase Admin SDK
firebase_app = None
if HAS_FIREBASE:
    try:
        firebase_cred_path = "firebase_credentials.json"
        if os.path.exists(firebase_cred_path):
            cred = credentials.Certificate(firebase_cred_path)
            firebase_app = firebase_admin.initialize_app(cred)
            print("Firebase Admin SDK initialized successfully.")
        else:
            print("firebase_credentials.json not found in root. FCM notifications are disabled.")
    except Exception as e:
        print(f"Error initializing Firebase Admin SDK: {e}")

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

async def weekly_synthesis_scheduler():
    while True:
        await asyncio.sleep(3600)
        now = datetime.datetime.now()
        if now.weekday() == 6 and now.hour == 23:
            try:
                from core.synthesis_loop import run_weekly_synthesis
                await run_weekly_synthesis()
            except Exception as e:
                print(f"Error in scheduled weekly synthesis: {e}")

async def send_serendipity_notifications():
    try:
        notes = await get_serendipity()
        if not notes:
            print("[Serendipity] No notes available to send.")
            return
            
        tokens_file = "device_tokens.json"
        if not os.path.exists(tokens_file):
            print("[Serendipity] No registered device tokens.")
            return
            
        try:
            with open(tokens_file, "r", encoding="utf-8") as f:
                devices = json.load(f)
        except Exception as e:
            print(f"[Serendipity] Error loading device tokens: {e}")
            return
            
        tokens = [d["token"] for d in devices if d.get("token")]
        if not tokens:
            print("[Serendipity] No device tokens available.")
            return
            
        if not HAS_FIREBASE or not firebase_app:
            print("[Serendipity] Firebase Admin SDK is not initialized/installed. Cannot send push notifications.")
            return

        now = datetime.datetime.now()

        for note in notes:
            # Determine notification title based on event proximity
            is_upcoming_event = False
            note_category = note.get("category", "")
            note_event_date = note.get("event_date")
            if note_category == "Event" and note_event_date:
                try:
                    evt_dt = datetime.datetime.fromisoformat(str(note_event_date).replace("Z", "+00:00")).replace(tzinfo=None)
                    days_until = (evt_dt - now).days
                    if 0 <= days_until <= 7:
                        is_upcoming_event = True
                except Exception:
                    pass

            if is_upcoming_event:
                title = f"📅 Upcoming Event: {note['title']}"
            else:
                title = f"🧠 Daily Spark: {note['title']}"
            body = note.get("summary") or "Review this note from your Second Brain."
            if len(body) > 150:
                body = body[:147] + "..."
                
            message = messaging.MulticastMessage(
                notification=messaging.Notification(
                    title=title,
                    body=body
                ),
                data={
                    "route": "/note",
                    "fileName": note["fileName"]
                },
                tokens=tokens
            )
            
            try:
                response = messaging.send_multicast(message)
                print(f"[Serendipity] Sent notification for {note['title']}: {response.success_count} success, {response.failure_count} failure")
            except Exception as ex:
                print(f"[Serendipity] Failed to send multicast message: {ex}")
    except Exception as e:
        print(f"[Serendipity] Error in send_serendipity_notifications: {e}")

async def daily_serendipity_scheduler():
    while True:
        # Check every 30 minutes
        await asyncio.sleep(1800)
        try:
            now = datetime.datetime.now()
            # We want to run daily at 08:30 AM local time.
            if now.hour == 8 and now.minute >= 30:
                today_str = now.strftime("%Y-%m-%d")
                state_file = "serendipity_state.json"
                last_run = ""
                if os.path.exists(state_file):
                    try:
                        with open(state_file, "r") as f:
                            state = json.load(f)
                            last_run = state.get("last_run", "")
                    except Exception:
                        pass
                
                if last_run != today_str:
                    await send_serendipity_notifications()
                    try:
                        with open(state_file, "w") as f:
                            json.dump({"last_run": today_str}, f)
                    except Exception as e:
                        print(f"[Serendipity] Failed to save state: {e}")
        except Exception as e:
            print(f"[Serendipity] Error in scheduler loop: {e}")

async def retroactive_backlink_scheduler():
    while True:
        # Check every 6 hours
        await asyncio.sleep(21600)
        now = datetime.datetime.now()
        # Run weekly on Sunday at 02:00 AM
        if now.weekday() == 6 and now.hour == 2:
            try:
                from core.retroactive_backlink import run_retroactive_scan
                await asyncio.to_thread(run_retroactive_scan)
            except Exception as e:
                print(f"Error in scheduled retroactive backlink: {e}")

# --- INITIALIZATION ---
app = FastAPI(title="Second Brain API")
@app.on_event("startup")
async def startup_event():
    asyncio.create_task(background_worker())
    asyncio.create_task(weekly_synthesis_scheduler())
    asyncio.create_task(daily_serendipity_scheduler())
    asyncio.create_task(retroactive_backlink_scheduler())
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
SYSTEM_CONFIG_FILE = "system_config.json"

def get_system_config():
    if os.path.exists(SYSTEM_CONFIG_FILE):
        try:
            with open(SYSTEM_CONFIG_FILE, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return {"inbox_mode": False}

def save_system_config(config):
    with open(SYSTEM_CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2)

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

@app.get("/api/geofences")
async def get_geofences():
    index = get_url_index()
    spots = []
    for url, note in index.items():
        if not isinstance(note, dict):
            continue
        category = note.get("category")
        filename = note.get("fileName", "")
        if category == "Spot to Visit" or "Spot to Visit" in filename:
            lat = note.get("latitude")
            lng = note.get("longitude")
            if lat is not None and lng is not None:
                spots.append({
                    "title": note.get("title"),
                    "fileName": filename,
                    "latitude": float(lat),
                    "longitude": float(lng),
                })
    return spots

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
    sys_config = get_system_config()
    return {
        "model": AI_MODEL,
        "primary_model": AI_MODEL_PRIMARY,
        "fallback_model": AI_MODEL_FALLBACK,
        "model_chain": AI_MODEL_CHAIN,
        "note_count": len(index),
        "inbox_mode": sys_config.get("inbox_mode", False)
    }

class ToggleInboxModeRequest(BaseModel):
    inbox_mode: bool

@app.post("/api/config/inbox_mode")
async def toggle_inbox_mode(request: ToggleInboxModeRequest):
    config = get_system_config()
    config["inbox_mode"] = request.inbox_mode
    save_system_config(config)
    return {"status": "success", "inbox_mode": config["inbox_mode"]}

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
        sys_config = get_system_config()
        if sys_config.get("inbox_mode", False):
            raw_category = "raw"
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
        
        latitude = data.get('ai_data', {}).get('latitude')
        longitude = data.get('ai_data', {}).get('longitude')
        lat_str = f"latitude: {latitude}\n" if latitude is not None else ""
        lng_str = f"longitude: {longitude}\n" if longitude is not None else ""

        content = f"""---
type: {data['type']}
date: {date_str}
author: {data['uploader']}
url: {data['url']}
category: {raw_category}
tags: {data['ai_data'].get('tags', [])}
{event_date_str}{lat_str}{lng_str}content_hash: {data.get('content_hash', '')}
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
            "category": raw_category,
            "latitude": latitude,
            "longitude": longitude,
        }
        index = get_url_index()
        index[url] = note_data
        save_url_index(index)

        event_date = data.get("ai_data", {}).get("event_date")
        if event_date and str(event_date).lower() != "null" and data['ai_data'].get('category') == "Event":
            ops_manager.update_task(task_id, "Syncing to Calendar", progress=90)
            try:
                from core.calendar_sync import create_calendar_event
                await asyncio.to_thread(
                    create_calendar_event,
                    title=f"Event: {data['ai_data'].get('summary', 'New Event')[:50]}",
                    event_date_str=str(event_date),
                    source_url=data['url'],
                    description=data['ai_data'].get('formatted_content', '')
                )
            except Exception as e:
                print(f"Calendar sync failed: {e}")

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
        sys_config = get_system_config()
        if sys_config.get("inbox_mode", False):
            raw_category = "raw"
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

        latitude = data.get('ai_data', {}).get('latitude')
        longitude = data.get('ai_data', {}).get('longitude')
        lat_str = f"latitude: {latitude}\n" if latitude is not None else ""
        lng_str = f"longitude: {longitude}\n" if longitude is not None else ""

        content = f"""---
type: {data['type']}
date: {date_str}
author: {data['uploader']}
url: {data['url']}
category: {raw_category}
tags: {data['ai_data'].get('tags', [])}
{event_date_str}{lat_str}{lng_str}content_hash: {data.get('content_hash', '')}
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
            "category": raw_category,
            "latitude": latitude,
            "longitude": longitude,
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
        sys_config = get_system_config()
        if sys_config.get("inbox_mode", False):
            raw_category = "raw"
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

        latitude = data.get('ai_data', {}).get('latitude')
        longitude = data.get('ai_data', {}).get('longitude')
        lat_str = f"latitude: {latitude}\n" if latitude is not None else ""
        lng_str = f"longitude: {longitude}\n" if longitude is not None else ""

        content = f"""---
type: {data['type']}
date: {date_str}
author: {data['uploader']}
url: {data['url']}
category: {raw_category}
tags: {data['ai_data'].get('tags', [])}
{event_date_str}{lat_str}{lng_str}content_hash: {data.get('content_hash', '')}
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
            "category": raw_category,
            "latitude": latitude,
            "longitude": longitude,
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

        # Update AI Librarian indexes
        update_hierarchical_indexes()

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
        urgent_event_notes = []
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
                
                note_entry = {
                    "url": url,
                    "title": data.get("title", ""),
                    "fileName": data.get("fileName", ""),
                    "date": date_str,
                    "last_reviewed": data.get("last_reviewed"),
                    "category": data.get("category"),
                    "event_date": data.get("event_date"),
                    "dt": dt
                }
                all_notes.append(note_entry)

                # Check for urgent event notes (Event category with event_date 0, 3, or 7 days away)
                if data.get("category") == "Event" and data.get("event_date"):
                    try:
                        evt_dt = datetime.datetime.fromisoformat(
                            str(data["event_date"]).replace("Z", "+00:00")
                        ).replace(tzinfo=None)
                        days_away = (evt_dt.date() - now.date()).days
                        if days_away in (0, 3, 7):
                            urgent_event_notes.append(note_entry)
                    except Exception:
                        pass
        
        if not all_notes:
            return []

        # Build final selection: urgent events first, then fill remaining slots randomly
        max_results = 3
        selected = []
        urgent_urls = set()

        for note in urgent_event_notes[:max_results]:
            selected.append(note)
            urgent_urls.add(note["url"])

        remaining_slots = max_results - len(selected)
        if remaining_slots > 0:
            # Use the existing prioritization logic for the random pool
            def sort_key(note):
                last_rev = note["last_reviewed"]
                has_rev = 1 if last_rev else 0
                rev_time = last_rev if last_rev else ""
                return (has_rev, rev_time, note["date"])

            pool_candidates = [n for n in all_notes if n["url"] not in urgent_urls]
            sorted_notes = sorted(pool_candidates, key=sort_key)

            import random
            pool = sorted_notes[:min(15, len(sorted_notes))]
            random_picks = random.sample(pool, min(remaining_slots, len(pool)))
            selected.extend(random_picks)
        
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
                "summary": summary,
                "category": note.get("category"),
                "event_date": note.get("event_date")
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
        # Get existing categories and note titles to pass to the LLM
        existing_categories = []
        existing_titles = []
        if os.path.exists(PROJECT_VAULT_PATH):
            for item in os.listdir(PROJECT_VAULT_PATH):
                cat_path = os.path.join(PROJECT_VAULT_PATH, item)
                if os.path.isdir(cat_path) and not item.startswith("_") and item != "raw":
                    existing_categories.append(item)
                    for f in os.listdir(cat_path):
                        if f.endswith(".md") and not f.startswith("_"):
                            existing_titles.append(f.replace(".md", ""))

        existing_categories_str = ", ".join(existing_categories)
        existing_titles_str = "\n".join([f"- {t}" for t in existing_titles])

        prompt = f"""
You are an expert AI Librarian organizing a knowledge base.
We are saving a synthesized chat answer to our wiki. 

Title of the article: {request.title}
Content:
{request.content}

Here are the existing categories in our vault: {existing_categories_str}
Here are the existing note titles in our vault:
{existing_titles_str}

Please perform the following operations:
1. Select the most appropriate category for this note. Choose from the existing categories, or define a new category if none fits.
2. Refine the note: format it with clear, professional markdown (headers, lists, tables).
3. Identify and inject Obsidian-style wiki links like [[Note Title]] for any concepts, topics, or terms in the content that match any of our existing note titles. Ensure links are injected naturally and accurately.

Format your response as a valid JSON object matching the following structure:
{{
  "category": "Selected Category",
  "formatted_content": "The refined markdown content with appropriate [[wiki links]]"
}}

Ensure the output is ONLY valid JSON, with no markdown code fences, leading/trailing backticks, or extra text.
"""
        category = "Synthesis"
        formatted_content = request.content
        model_used = AI_MODEL

        try:
            response, model_used = generate_content_with_fallback(prompt, purpose="save_answer")
            cleaned_text = response.text.strip()
            if cleaned_text.startswith("```json"):
                cleaned_text = cleaned_text[7:]
            if cleaned_text.endswith("```"):
                cleaned_text = cleaned_text[:-3]
            cleaned_text = cleaned_text.strip()
            ai_data = json.loads(cleaned_text)

            category = ai_data.get("category", "Synthesis")
            formatted_content = ai_data.get("formatted_content", request.content)
        except Exception as e:
            print(f"Error calling LLM for save_answer: {e}")

        date_str = datetime.datetime.now().strftime("%Y-%m-%d")
        safe_title = re.sub(r'[\\/*?:"<>|]', "", request.title)
        safe_category = re.sub(r'[\\/*?:"<>|]', "-", category)
        
        project_category_path = os.path.join(PROJECT_VAULT_PATH, safe_category)
        obsidian_category_path = os.path.join(OBSIDIAN_INBOX_PATH, safe_category)
        os.makedirs(project_category_path, exist_ok=True)
        os.makedirs(obsidian_category_path, exist_ok=True)

        filename = get_unique_filename(f"Synthesis - {safe_title}.md", category=safe_category)
        project_filepath = os.path.join(project_category_path, filename)
        obsidian_filepath = os.path.join(obsidian_category_path, filename)

        full_content = f"""---
type: synthesized_note
date: {date_str}
category: {category}
ai_model: {model_used}
---
# {request.title}

{formatted_content}
"""
        with open(project_filepath, "w", encoding="utf-8") as f:
            f.write(full_content)
        with open(obsidian_filepath, "w", encoding="utf-8") as f:
            f.write(full_content)

        relative_filename = os.path.join(safe_category, filename).replace("\\", "/")
        note_data = {
            "title": filename.replace(".md", ""),
            "fileName": relative_filename,
            "date": datetime.datetime.now().isoformat(),
            "url": f"local://{relative_filename}",
            "category": category
        }

        # Add to index mapping
        index = get_url_index()
        index[f"local://{relative_filename}"] = note_data
        save_url_index(index)

        # Also index in ChromaDB
        chunks = [chunk for chunk in chunk_text(formatted_content) if chunk.strip()]
        if chunks:
            vault_collection.add(
                documents=chunks,
                metadatas=[{"filename": relative_filename, "url": f"local://{relative_filename}", "content_hash": ""} for _ in chunks],
                ids=[f"synthesis_{uuid.uuid4().hex}_chunk_{i}" for i in range(len(chunks))]
            )

        update_hierarchical_indexes()

        return {"status": "success", "fileName": relative_filename, "note": note_data}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/inbox/pending")
async def get_pending_inbox():
    try:
        raw_dir = os.path.join(PROJECT_VAULT_PATH, "raw")
        if not os.path.exists(raw_dir):
            return {"count": 0, "files": []}
        files = [f for f in os.listdir(raw_dir) if f.endswith(".md") and not f.startswith("_")]
        return {"count": len(files), "files": files}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/raw_count")
async def get_raw_count():
    try:
        raw_dir = os.path.join(PROJECT_VAULT_PATH, "raw")
        if not os.path.exists(raw_dir):
            return {"raw_count": 0}
        files = [f for f in os.listdir(raw_dir) if f.endswith(".md") and not f.startswith("_")]
        return {"raw_count": len(files)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/analytics")
async def save_analytics(request: Request):
    try:
        data = await request.json()
        analytics_file = os.path.join(PROJECT_VAULT_PATH, "analytics.json")
        
        existing_data = []
        if os.path.exists(analytics_file):
            try:
                with open(analytics_file, "r", encoding="utf-8") as f:
                    existing_data = json.load(f)
                    if not isinstance(existing_data, list):
                        existing_data = []
            except Exception:
                existing_data = []
                
        if isinstance(data, list):
            existing_data.extend(data)
        else:
            existing_data.append(data)
            
        os.makedirs(PROJECT_VAULT_PATH, exist_ok=True)
        with open(analytics_file, "w", encoding="utf-8") as f:
            json.dump(existing_data, f, indent=2, ensure_ascii=False)
            
        return {"status": "success", "message": "Analytics uploaded successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
def update_note_tasks(filename: str, markdown_content: str):
    tasks_file = os.path.join(PROJECT_VAULT_PATH, "_tasks.json")
    existing_tasks = []
    if os.path.exists(tasks_file):
        try:
            with open(tasks_file, "r", encoding="utf-8") as f:
                existing_tasks = json.load(f)
        except Exception as e:
            print(f"Error loading tasks: {e}")
            
    # Map existing tasks for this filename by text to retain their IDs and Todoist mappings
    existing_map = {t["text"]: t for t in existing_tasks if t.get("filename") == filename}
    
    cleaned_tasks = [t for t in existing_tasks if t.get("filename") != filename]
    
    new_tasks = []
    lines = markdown_content.splitlines()
    for line in lines:
        match = re.search(r'^\s*-\s*\[\s*\]\s*(.+)$', line)
        if match:
            task_text = match.group(1).strip()
            due_date = None
            date_match = re.search(r'(?:due:|@due|by:?)\s*(\d{4}-\d{2}-\d{2})', task_text, re.IGNORECASE)
            if date_match:
                due_date = date_match.group(1)
            
            # Re-use existing task metadata if it was already tracked
            if task_text in existing_map:
                new_tasks.append(existing_map[task_text])
            else:
                # Push new task to Todoist
                from core.task_sync import push_task_to_todoist
                todoist_id = push_task_to_todoist(task_text, due_date, filename)
                
                new_tasks.append({
                    "id": str(uuid.uuid4()),
                    "text": task_text,
                    "due_date": due_date,
                    "filename": filename,
                    "completed": False,
                    "todoist_task_id": todoist_id,
                    "created_at": datetime.datetime.now().isoformat()
                })
            
    cleaned_tasks.extend(new_tasks)
    try:
        with open(tasks_file, "w", encoding="utf-8") as f:
            json.dump(cleaned_tasks, f, indent=2, ensure_ascii=False)
    except Exception as e:
        print(f"Error saving tasks: {e}")

@app.get("/api/tasks")
async def get_all_tasks():
    tasks_file = os.path.join(PROJECT_VAULT_PATH, "_tasks.json")
    if not os.path.exists(tasks_file):
        return []
    try:
        with open(tasks_file, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading tasks file: {e}")
        return []

@app.post("/api/webhooks/todoist")
async def todoist_webhook(request: Request):
    import hmac
    import hashlib
    import base64

    # 1. Enforce signature verification
    signature = request.headers.get("X-Todoist-Hmac-SHA256")
    body = await request.body()
    
    todoist_client_secret = os.getenv("TODOIST_CLIENT_SECRET")
    if todoist_client_secret:
        if not signature:
            raise HTTPException(status_code=401, detail="X-Todoist-Hmac-SHA256 header missing")
        
        # Calculate HMAC
        computed_hash = hmac.new(todoist_client_secret.encode('utf-8'), body, hashlib.sha256).digest()
        computed_sig = base64.b64encode(computed_hash).decode('utf-8')
        if not hmac.compare_digest(computed_sig, signature):
            raise HTTPException(status_code=401, detail="Invalid HMAC signature")
    else:
        print("[Todoist Webhook] Warning: TODOIST_CLIENT_SECRET not configured. Skipping signature validation.")

    # 2. Parse payload
    try:
        payload = json.loads(body)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON payload")

    event_name = payload.get("event_name")
    if event_name != "item:completed":
        return {"status": "ignored", "event": event_name}

    event_data = payload.get("event_data", {})
    todoist_task_id = str(event_data.get("id") or event_data.get("item_id", ""))
    if not todoist_task_id:
        raise HTTPException(status_code=400, detail="Todoist task ID not found in payload")

    # 3. Read and search tasks
    tasks_file = os.path.join(PROJECT_VAULT_PATH, "_tasks.json")
    if not os.path.exists(tasks_file):
        return {"status": "ignored", "reason": "No tasks database found"}

    try:
        with open(tasks_file, "r", encoding="utf-8") as f:
            tasks = json.load(f)
    except Exception as e:
        print(f"[Todoist Webhook] Error loading tasks list: {e}")
        raise HTTPException(status_code=500, detail="Failed to load tasks list")

    target_task = None
    for task in tasks:
        # Match todoist task ID (checking string conversion)
        if task.get("todoist_task_id") and str(task["todoist_task_id"]) == todoist_task_id:
            target_task = task
            break

    if not target_task:
        print(f"[Todoist Webhook] No matching local task found for Todoist ID: {todoist_task_id}")
        return {"status": "ignored", "reason": f"No task found for Todoist ID {todoist_task_id}"}

    filename = target_task.get("filename")
    task_text = target_task.get("text")
    if not filename or not task_text:
        return {"status": "ignored", "reason": "Invalid task data stored locally"}

    # 4. Modify physical files
    updated_files = 0
    # Update files in PROJECT_VAULT_PATH and OBSIDIAN_INBOX_PATH
    paths = [
        os.path.join(PROJECT_VAULT_PATH, filename),
        os.path.join(OBSIDIAN_INBOX_PATH, filename)
    ]
    
    escaped_text = re.escape(task_text)
    pattern = re.compile(rf'^(\s*-\s*\[)\s*(\]\s*{escaped_text})', re.MULTILINE)

    for p in paths:
        if os.path.exists(p):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    content = f.read()
                
                # Replace checkmark
                new_content = pattern.sub(r'\1x\2', content)
                if new_content != content:
                    with open(p, "w", encoding="utf-8") as f:
                        f.write(new_content)
                    updated_files += 1
            except Exception as e:
                print(f"[Todoist Webhook] Failed to update markdown file at {p}: {e}")

    # 5. Update state in _tasks.json
    target_task["completed"] = True
    try:
        with open(tasks_file, "w", encoding="utf-8") as f:
            json.dump(tasks, f, indent=2, ensure_ascii=False)
    except Exception as e:
        print(f"[Todoist Webhook] Failed to write updated tasks list: {e}")

    return {"status": "success", "task_text": task_text, "updated_files": updated_files}

class DeviceTokenRequest(BaseModel):
    token: str
    device: str

@app.post("/api/device_token")
async def register_device_token(req: DeviceTokenRequest):
    tokens_file = "device_tokens.json"
    tokens = []
    if os.path.exists(tokens_file):
        try:
            with open(tokens_file, "r", encoding="utf-8") as f:
                tokens = json.load(f)
        except Exception:
            tokens = []
            
    # Prevent duplicates
    if not any(t.get("token") == req.token for t in tokens):
        tokens.append({
            "token": req.token,
            "device": req.device,
            "registered_at": datetime.datetime.now().isoformat()
        })
        try:
            with open(tokens_file, "w", encoding="utf-8") as f:
                json.dump(tokens, f, indent=2)
        except Exception as e:
            print(f"Error saving device tokens: {e}")
            raise HTTPException(status_code=500, detail="Failed to save token")
            
    return {"status": "success", "message": "Device token registered"}



@app.post("/api/synthesis/weekly")
async def trigger_weekly_synthesis():
    from core.synthesis_loop import run_weekly_synthesis
    result = await run_weekly_synthesis(manual=True)
    if result["status"] == "error":
        raise HTTPException(status_code=500, detail=result["message"])
    return result

@app.post("/api/maintenance/backlink")
async def trigger_retroactive_backlink():
    try:
        from core.retroactive_backlink import run_retroactive_scan
        result = await asyncio.to_thread(run_retroactive_scan)
        if result.get("status") == "error":
            raise HTTPException(status_code=500, detail=result.get("message"))
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/compile")
async def compile_inbox():
    try:
        raw_dir = os.path.join(PROJECT_VAULT_PATH, "raw")
        if not os.path.exists(raw_dir):
            return {"status": "success", "compiled_count": 0, "notes": []}

        compiled_notes = []
        files = [f for f in os.listdir(raw_dir) if f.endswith(".md") and not f.startswith("_")]

        if not files:
            return {"status": "success", "compiled_count": 0, "notes": []}

        # Get existing categories and note titles to pass to the LLM
        existing_categories = []
        existing_titles = []
        if os.path.exists(PROJECT_VAULT_PATH):
            for item in os.listdir(PROJECT_VAULT_PATH):
                cat_path = os.path.join(PROJECT_VAULT_PATH, item)
                if os.path.isdir(cat_path) and not item.startswith("_") and item != "raw":
                    existing_categories.append(item)
                    for f in os.listdir(cat_path):
                        if f.endswith(".md") and not f.startswith("_"):
                            existing_titles.append(f.replace(".md", ""))

        existing_categories_str = ", ".join(existing_categories)
        existing_titles_str = "\n".join([f"- {t}" for t in existing_titles])

        for file in files:
            filepath = os.path.join(raw_dir, file)
            obsidian_filepath = os.path.join(OBSIDIAN_INBOX_PATH, "raw", file)

            with open(filepath, "r", encoding="utf-8") as f:
                raw_content = f.read()

            prompt = f"""
You are an expert AI Librarian. Clean up, refine, and compile this raw note/clipping into a structured, categorized wiki article.

Note content:
{raw_content}

Here are the existing categories in our vault: {existing_categories_str}
Here are the existing note titles in our vault:
{existing_titles_str}

Please perform the following operations:
1. Select the most appropriate category for this note. Choose from the existing categories, or define a new category if none fits.
2. Refine the note: format it with clear, professional markdown. Start the content with a short summary section using format: > **AI Summary:** [Brief summary]
3. Extract relevant tags (e.g. ["#tag1", "#tag2"]).
4. Identify and inject Obsidian-style wiki links like [[Note Title]] for any concepts, topics, or terms in the content that match any of our existing note titles.

Format your response as a valid JSON object matching the following structure:
{{
  "category": "Selected Category",
  "title": "Optimized Note Title",
  "tags": ["#tag1", "#tag2"],
  "summary": "Brief 1-sentence summary",
  "formatted_content": "The refined markdown content with appropriate [[wiki links]]"
}}

Ensure the output is ONLY valid JSON, with no markdown code fences, leading/trailing backticks, or extra text.
"""
            category = "General"
            title = file.replace(".md", "")
            tags = ["#inbox"]
            summary = "Compiled note."
            formatted_content = raw_content
            model_used = AI_MODEL

            try:
                response, model_used = generate_content_with_fallback(prompt, purpose="compile_note")
                cleaned_text = response.text.strip()
                if cleaned_text.startswith("```json"):
                    cleaned_text = cleaned_text[7:]
                if cleaned_text.endswith("```"):
                    cleaned_text = cleaned_text[:-3]
                cleaned_text = cleaned_text.strip()
                ai_data = json.loads(cleaned_text)

                category = ai_data.get("category", "General")
                title = ai_data.get("title", title)
                tags = ai_data.get("tags", tags)
                summary = ai_data.get("summary", summary)
                formatted_content = ai_data.get("formatted_content", formatted_content)
            except Exception as e:
                print(f"Error parsing compile response for {file}: {e}")

            # Query vector database for similar notes to generate auto-backlinks
            related_insights_str = ""
            try:
                query_text = summary if (summary and len(summary) > 10) else raw_content[:500]
                results = vault_collection.query(query_texts=[query_text], n_results=5)
                
                similar_notes = []
                seen_files = set()
                
                if results and 'documents' in results and results['documents']:
                    docs = results['documents'][0]
                    metas = results['metadatas'][0] if 'metadatas' in results else []
                    
                    for idx, doc in enumerate(docs):
                        meta = metas[idx] if idx < len(metas) else {}
                        fn = meta.get('filename') if isinstance(meta, dict) else None
                        if fn and fn != f"raw/{file}" and not fn.startswith("raw/"):
                            note_title = os.path.basename(fn).replace(".md", "")
                            if note_title not in seen_files:
                                seen_files.add(note_title)
                                similar_notes.append({
                                    "title": note_title,
                                    "excerpt": doc[:300]
                                })
                
                if similar_notes:
                    backlink_prompt = f"""
You are an expert AI Librarian. Analyze the relationship between the new note and these potentially related notes in the vault:

New Note:
Title: {title}
Summary: {summary}
Content:
{formatted_content}

Potentially Related Notes:
"""
                    for i, sn in enumerate(similar_notes):
                        backlink_prompt += f"\n{i+1}. Title: {sn['title']}\nExcerpt: {sn['excerpt']}\n"
                        
                    backlink_prompt += """
Decide which of these notes are genuinely relevant and connected. For each relevant connection, generate a single Markdown list item with:
- The Obsidian backlink to the note (e.g. [[Note Title]])
- A concise, one-sentence rationale explaining the connection.

Format the output ONLY as a list of bullet points:
* [[Note Title]]: [Your rationale here]

If none are relevant, output nothing. Do not include markdown code fences, backticks, or other text.
"""
                    response_links, _ = generate_content_with_fallback(backlink_prompt, purpose="backlinks")
                    links_text = response_links.text.strip()
                    if links_text and not links_text.lower().startswith("none") and "[[url" not in links_text.lower():
                        clean_links = []
                        for line in links_text.splitlines():
                            line_stripped = line.strip()
                            if line_stripped.startswith("*") or line_stripped.startswith("-"):
                                clean_links.append(line_stripped)
                        if clean_links:
                            related_insights_str = "\n## Related Vault Insights\n" + "\n".join(clean_links) + "\n"
            except Exception as e:
                print(f"Error generating auto-backlinks for {file}: {e}")

            date_str = datetime.datetime.now().strftime("%Y-%m-%d")
            safe_category = re.sub(r'[\\/*?:"<>|]', "-", category)
            project_category_path = os.path.join(PROJECT_VAULT_PATH, safe_category)
            obsidian_category_path = os.path.join(OBSIDIAN_INBOX_PATH, safe_category)
            os.makedirs(project_category_path, exist_ok=True)
            os.makedirs(obsidian_category_path, exist_ok=True)

            new_filename = get_unique_filename(f"{date_str} - {safe_category} ({title}).md", category=safe_category)
            new_project_filepath = os.path.join(project_category_path, new_filename)
            new_obsidian_filepath = os.path.join(obsidian_category_path, new_filename)

            full_content = f"""---
type: note
date: {date_str}
category: {category}
tags: {tags}
ai_model: {model_used}
---
# {title}

> **AI Summary:** {summary}

## Extracted Content
{formatted_content}
{related_insights_str}"""
            with open(new_project_filepath, "w", encoding="utf-8") as f:
                f.write(full_content)
            with open(new_obsidian_filepath, "w", encoding="utf-8") as f:
                f.write(full_content)

            relative_filename = os.path.join(safe_category, new_filename).replace("\\", "/")

            try:
                update_note_tasks(relative_filename, full_content)
            except Exception as e:
                print(f"Error updating tasks for {new_filename}: {e}")

            # Find the original URL from index mapping if it exists
            index = get_url_index()
            original_url = None
            for url, val in index.items():
                if isinstance(val, dict) and val.get("fileName") == f"raw/{file}":
                    original_url = url
                    break

            # Remove old index entry
            if original_url:
                index.pop(original_url, None)

            # Add new index entry
            new_url = original_url or f"local://{relative_filename}"
            note_data = {
                "title": new_filename.replace(".md", ""),
                "fileName": relative_filename,
                "date": datetime.datetime.now().isoformat(),
                "url": new_url,
                "category": category,
                "tags": tags
            }
            index[new_url] = note_data
            save_url_index(index)

            # Update Vector DB (Delete raw note chunks and add compiled note chunks)
            try:
                # Delete by filename
                vault_collection.delete(where={"filename": f"raw/{file}"})
            except Exception as e:
                print(f"Error deleting old chunks from vector db: {e}")

            chunks = [chunk for chunk in chunk_text(formatted_content) if chunk.strip()]
            if chunks:
                vault_collection.add(
                    documents=chunks,
                    metadatas=[{"filename": relative_filename, "url": new_url, "content_hash": ""} for _ in chunks],
                    ids=[f"compile_{uuid.uuid4().hex}_chunk_{i}" for i in range(len(chunks))]
                )

            # Clean up the raw files
            try:
                if os.path.exists(filepath):
                    os.remove(filepath)
                if os.path.exists(obsidian_filepath):
                    os.remove(obsidian_filepath)
            except Exception as e:
                print(f"Error removing raw files: {e}")

            compiled_notes.append(note_data)

        update_hierarchical_indexes()

        return {
            "status": "success",
            "compiled_count": len(compiled_notes),
            "notes": compiled_notes
        }
    except Exception as e:
        import traceback
        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/nearby")
async def get_nearby_notes(lat: float, lng: float, radius_km: float = 5.0):
    """Find notes with geo-coordinates within a given radius of a point."""
    try:
        index = get_url_index()
        nearby = []

        for url, data in index.items():
            if not isinstance(data, dict):
                continue
            note_lat = data.get("latitude")
            note_lng = data.get("longitude")
            if note_lat is None or note_lng is None:
                continue
            try:
                note_lat = float(note_lat)
                note_lng = float(note_lng)
            except (ValueError, TypeError):
                continue

            distance = haversine_distance(lat, lng, note_lat, note_lng)
            if distance <= radius_km:
                nearby.append({
                    "title": data.get("title", ""),
                    "fileName": data.get("fileName", ""),
                    "category": data.get("category"),
                    "latitude": note_lat,
                    "longitude": note_lng,
                    "distance_km": round(distance, 3)
                })

        nearby.sort(key=lambda x: x["distance_km"])
        return nearby
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
