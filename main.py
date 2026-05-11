import os
import re
import datetime
import json
import uuid
from typing import List, Optional
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse, PlainTextResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import chromadb

# Internal Imports
from core.config import GEMINI_API_KEY, OBSIDIAN_INBOX_PATH, PROJECT_VAULT_PATH, AI_MODEL
from core.state import ops_manager, get_url_index, save_url_index
from core.utils import clean_url, chunk_text, cleanup_temp_files
from core.processors import process_reel, process_image_post, client

# --- INITIALIZATION ---
app = FastAPI(title="Second Brain API")
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

class SaveAnswerRequest(BaseModel):
    title: str
    content: str

# --- ROUTES ---

@app.get("/")
async def root():
    return {"message": "🧠 Second Brain API is Online", "docs": "/docs"}

@app.get("/api/health")
async def health_check():
    return {"status": "ok"}

@app.get("/api/status")
async def get_system_status():
    return {
        "active_tasks": list(ops_manager.active_tasks.values()),
        "task_count": len(ops_manager.active_tasks)
    }

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

@app.get("/api/notes/{filename}")
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
    return {"model": AI_MODEL, "note_count": len(index)}

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
    response = client.models.generate_content(model=AI_MODEL, contents=prompt)
    return {"summary": response.text}

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
    response = client.models.generate_content(model=AI_MODEL, contents=prompt)
    return {"deep_dive": response.text}

@app.post("/api/ingest")
async def ingest_url(request: Request):
    body = await request.json()
    url = clean_url(body.get('url', ''))
    if not url:
        raise HTTPException(status_code=400, detail="URL is required")
    
    wants_stream = request.headers.get("X-Stream", "") == "true"

    async def _run_ingestion(url: str, status_callback=None):
        task_id = f"task_{uuid.uuid4().hex[:8]}"
        if status_callback: await status_callback("Checking Index")
        ops_manager.start_task(task_id, url, "Checking Index")
        
        try:
            index = get_url_index()
            if url in index:
                note_data = index[url]
                fn = note_data['fileName'] if isinstance(note_data, dict) else note_data
                if os.path.exists(os.path.join(OBSIDIAN_INBOX_PATH, fn)):
                    ops_manager.end_task(task_id)
                    return {"status": "existing", "note": note_data if isinstance(note_data, dict) else {"fileName": fn, "title": fn}}

            if "instagram.com" in url and ("/reel/" not in url and "/p/" in url):
                data = await process_image_post(url, task_id, status_callback)
            else:
                data = await process_reel(url, task_id, status_callback)
            
            # MD5 Duplicate Detection
            content_hash = data.get('content_hash')
            if content_hash:
                for existing_url, existing_data in index.items():
                    if isinstance(existing_data, dict) and existing_data.get('content_hash') == content_hash:
                        ops_manager.end_task(task_id)
                        return {
                            "status": "existing", 
                            "message": "Content already exists in vault (detected via MD5)",
                            "note": existing_data
                        }
            
            if status_callback: await status_callback("Saving to Vaults")
            ops_manager.update_task(task_id, "Saving to Vaults")
            date_str = datetime.datetime.now().strftime("%Y-%m-%d")
            safe_uploader = re.sub(r'[\\/*?:"<>|]', "", data['uploader'])
            raw_category = data['ai_data'].get('category', 'Post')
            safe_category = re.sub(r'[\\/*?:"<>|]', "-", raw_category)
            filename = f"{date_str} - {safe_category} from {data['platform'].capitalize()} ({safe_uploader}).md"
            
            project_filepath = os.path.join(PROJECT_VAULT_PATH, filename)
            obsidian_filepath = os.path.join(OBSIDIAN_INBOX_PATH, filename)

            content = f"""---
type: {data['type']}
date: {date_str}
author: {data['uploader']}
url: {data['url']}
category: {raw_category}
tags: {data['ai_data'].get('tags', [])}
---
# {raw_category} by {data['uploader']}

> **AI Summary:** {data['ai_data'].get('summary', '')}

## Extracted Content
{data['ai_data'].get('formatted_content', '')}

---
### Original Caption
* {data['description']}
"""
            with open(project_filepath, "w", encoding="utf-8") as f: f.write(content)
            with open(obsidian_filepath, "w", encoding="utf-8") as f: f.write(content)

            note_data = {
                "title": filename.replace(".md", ""), 
                "fileName": filename, 
                "date": datetime.datetime.now().isoformat(), 
                "url": url,
                "content_hash": data.get('content_hash')
            }
            index[url] = note_data
            save_url_index(index)

            if status_callback: await status_callback("Updating AI Index")
            ops_manager.update_task(task_id, "Updating AI Index")
            chunks = chunk_text(data['ai_data'].get('formatted_content', ''))
            vault_collection.add(
                documents=chunks,
                metadatas=[{"filename": filename, "url": url} for _ in chunks],
                ids=[f"{url}_chunk_{i}" for i in range(len(chunks))]
            )
            ops_manager.end_task(task_id)
            return {"status": "success", "note": note_data}
        except Exception as e:
            import traceback
            ops_manager.log_error(url, str(e), detail=traceback.format_exc())
            ops_manager.end_task(task_id)
            raise e

    if wants_stream:
        async def stream():
            try:
                async def on_status(msg):
                    nonlocal stream_queue
                    await stream_queue.put(json.dumps({"status": "status", "message": f"⬇️ {msg}..."}) + "\n")

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
        return StreamingResponse(stream(), media_type="text/event-stream")
    
    try:
        return await _run_ingestion(url)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/chat")
async def chat(request: AskRequest):
    try:
        results = vault_collection.query(query_texts=[request.message], n_results=5)
        ctx = "\n".join(results['documents'][0]) if results['documents'] and results['documents'][0] else ""
        prompt = f"Answer based on these notes:\n\n{ctx}\n\nQuestion: {request.message}"
        response = client.models.generate_content(model=AI_MODEL, contents=prompt)
        return {"response": response.text}
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
