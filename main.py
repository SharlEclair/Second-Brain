import os
import re
import datetime
import asyncio
import json
import uuid
import io
import shutil
import subprocess
from typing import List, Optional
from PIL import Image
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Body
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import chromadb
from google import genai
from google.genai import types
from faster_whisper import WhisperModel
import yt_dlp
import instaloader

# --- CONFIGURATION ---
load_dotenv()
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
OBSIDIAN_INBOX_PATH = os.getenv("OBSIDIAN_VAULT_PATH") or os.getenv("OBSIDIAN_INBOX_PATH") or "./vault"
URL_INDEX_FILE = "url_index.json"
TAGS_FILE = "tags.txt"

# Load tags
TAGS_LIST = []
if os.path.exists(TAGS_FILE):
    try:
        with open(TAGS_FILE, "r", encoding="utf-8") as f:
            TAGS_LIST = [line.strip() for line in f if line.strip()]
    except Exception as e:
        print(f"Error loading tags.txt: {e}")

# --- INITIALIZATION ---
app = FastAPI(title="Second Brain API")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

if not os.path.exists(OBSIDIAN_INBOX_PATH):
    os.makedirs(OBSIDIAN_INBOX_PATH, exist_ok=True)

print("Configuring Gemini AI...")
client = genai.Client(api_key=GEMINI_API_KEY)
AI_MODEL = 'models/gemini-2.5-flash' 

print("Initializing ChromaDB...")
chroma_client = chromadb.PersistentClient(path="./chroma_db")
vault_collection = chroma_client.get_or_create_collection(name="vault_embeddings")

print("Loading Faster-Whisper model...")
try:
    # Attempting turbo model
    whisper_model = WhisperModel("large-v3-turbo", device="auto", compute_type="int8")
except Exception as e:
    print(f"Falling back to base model: {e}")
    whisper_model = WhisperModel("base", device="auto", compute_type="int8")

print("Initializing Instaloader...")
L = instaloader.Instaloader(download_video_thumbnails=False, save_metadata=False, post_metadata_txt_pattern="")

# --- UTILS ---

def get_platform_from_url(url: str) -> str:
    if "tiktok.com" in url: return "tiktok"
    if "youtube.com" in url or "youtu.be" in url: return "youtube"
    if "instagram.com" in url: return "instagram"
    return "web"

def clean_url(url: str) -> str:
    if "?" in url: url = url.split("?")[0]
    return url.rstrip("/")

def get_url_index() -> dict:
    if os.path.exists(URL_INDEX_FILE):
        try:
            with open(URL_INDEX_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except: pass
    return {}

def save_url_index(index: dict):
    with open(URL_INDEX_FILE, "w", encoding="utf-8") as f:
        json.dump(index, f, indent=4)

def chunk_text(text: str, chunk_size: int = 300, overlap: int = 50) -> list[str]:
    words = text.split()
    if len(words) <= chunk_size: return [text]
    chunks = []
    i = 0
    while i < len(words):
        chunk = " ".join(words[i:i + chunk_size])
        chunks.append(chunk)
        i += (chunk_size - overlap)
    return chunks

# --- CORE LOGIC ---

SYSTEM_PROMPT = f"""
You are an AI organizing data for a personal Obsidian Second Brain.
Categorize the content into one of these types: [Recipe, Spot to Visit, Event, Job/Career, General].
You MUST prioritize categorizing this content using the following existing tags: {TAGS_LIST}. Only invent a new tag if absolutely none of these apply.
Provide 3-5 relevant, hierarchical Obsidian tags (e.g., #recipe/dinner, #location/melbourne, #career/tips).
Format the 'formatted_content' precisely based on the category:
- Recipe: Use Markdown checklists (- [ ]) for ingredients, numbered lists for steps.
- Spot to Visit: List Location Name, Vibe/Atmosphere, and Key Highlights/What to order.
- Event: List Date/Time, Location, Ticket info, and What to expect.
- Job/Career: Extract key skills, actionable advice, and industry trends.
- General: Provide a clean, readable version of the text with a 3-bullet-point summary.

Wrap important entities in double brackets for Obsidian wiki-links (e.g., [[Machine Learning]]).

You MUST respond strictly with this JSON structure:
{{
  "category": "The Category",
  "tags": ["#tag1", "#tag2"],
  "summary": "A 1-2 sentence quick summary",
  "formatted_content": "The beautifully formatted markdown text"
}}
"""

async def process_image_post(url: str) -> dict:
    post_shortcode = url.split("/")[-2] if len(url.split("/")[-2]) > 3 else url.split("/")[-3]
    download_path = f"temp_{post_shortcode}"
    try:
        post = instaloader.Post.from_shortcode(L.context, post_shortcode)
        L.download_post(post, target=download_path)
        images = [os.path.join(download_path, f) for f in os.listdir(download_path) if f.endswith(('.jpg', '.jpeg', '.webp'))]
        if not images: raise Exception("No images found.")

        content_parts = [f"{SYSTEM_PROMPT}\n\nExtract knowledge from these images and structure it as JSON."]
        for img_path in images:
            with Image.open(img_path) as img:
                img.thumbnail((1024, 1024))
                if img.mode != "RGB": img = img.convert("RGB")
                img_byte_arr = io.BytesIO()
                img.save(img_byte_arr, format='JPEG')
                content_parts.append(types.Part.from_bytes(data=img_byte_arr.getvalue(), mime_type="image/jpeg"))

        response = client.models.generate_content(model=AI_MODEL, contents=content_parts, config=types.GenerateContentConfig(response_mime_type="application/json"))
        ai_data = json.loads(response.text.strip())
        shutil.rmtree(download_path)
        return {"uploader": post.owner_username, "description": post.caption or "", "url": url, "type": "instagram-carousel", "platform": "instagram", "ai_data": ai_data}
    except Exception as e:
        if os.path.exists(download_path): shutil.rmtree(download_path)
        raise e

async def process_reel(url: str) -> dict:
    temp_audio_file = f"temp_audio_{uuid.uuid4().hex}.m4a"
    platform = get_platform_from_url(url)
    ydl_opts = {'format': 'm4a/bestaudio/best', 'outtmpl': temp_audio_file, 'quiet': True}
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info_dict = ydl.extract_info(url, download=True)
            description = info_dict.get('description', '')
            uploader = info_dict.get('uploader', 'Unknown')

        segments, _ = whisper_model.transcribe(temp_audio_file)
        raw_text = "".join([s.text for s in segments]).strip()
        
        prompt = f"{SYSTEM_PROMPT}\n\nRaw Audio Transcript:\n{raw_text}"
        response = client.models.generate_content(model=AI_MODEL, contents=prompt, config=types.GenerateContentConfig(response_mime_type="application/json"))
        ai_data = json.loads(response.text.strip())

        if os.path.exists(temp_audio_file): os.remove(temp_audio_file)
        return {"uploader": uploader, "description": description, "url": url, "type": f"{platform}-video", "platform": platform, "ai_data": ai_data}
    except Exception as e:
        if os.path.exists(temp_audio_file): os.remove(temp_audio_file)
        raise e

# --- MODELS ---

class IngestRequest(BaseModel):
    url: str

class AskRequest(BaseModel):
    message: str

class SaveAnswerRequest(BaseModel):
    title: str
    content: str

from fastapi.responses import StreamingResponse

# --- ROUTES ---

@app.post("/api/ingest")
async def ingest_url(request: IngestRequest):
    url = clean_url(request.url)
    
    async def stream_progress():
        try:
            index = get_url_index()
            if url in index:
                note_data = index[url]
                filename = note_data['fileName'] if isinstance(note_data, dict) else note_data
                filepath = os.path.join(OBSIDIAN_INBOX_PATH, filename)
                if os.path.exists(filepath):
                    yield json.dumps({"status": "existing", "note": note_data if isinstance(note_data, dict) else {"fileName": filename, "title": filename}}) + "\n"
                    return

            yield json.dumps({"status": "status", "message": "⬇️ Downloading media..."}) + "\n"
            await asyncio.sleep(0.1) # Small sleep to ensure the UI gets the event

            if "instagram.com" in url and ("/p/" in url or "/post/" in url):
                data = await process_image_post(url)
            else:
                data = await process_reel(url)

            yield json.dumps({"status": "status", "message": "🧠 Analyzing & Saving..."}) + "\n"
            
            # Save to Obsidian
            date_str = datetime.datetime.now().strftime("%Y-%m-%d")
            safe_uploader = re.sub(r'[\\/*?:"<>|]', "", data['uploader'])
            raw_category = data['ai_data'].get('category', 'Post')
            safe_category = re.sub(r'[\\/*?:"<>|]', "-", raw_category)
            filename = f"{date_str} - {safe_category} from {data['platform'].capitalize()} ({safe_uploader}).md"
            filepath = os.path.join(OBSIDIAN_INBOX_PATH, filename)

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
            with open(filepath, "w", encoding="utf-8") as f: f.write(content)

            # Update index
            note_data = {"title": filename.replace(".md", ""), "fileName": filename, "date": datetime.datetime.now().isoformat()}
            index[url] = note_data
            save_url_index(index)

            # Embed and Save to Chroma
            chunks = chunk_text(data['ai_data'].get('formatted_content', ''))
            vault_collection.add(
                documents=chunks,
                metadatas=[{"filename": filename, "url": url} for _ in chunks],
                ids=[f"{url}_chunk_{i}" for i in range(len(chunks))]
            )

            yield json.dumps({"status": "success", "note": note_data}) + "\n"
        except Exception as e:
            yield json.dumps({"status": "error", "message": str(e)}) + "\n"

    return StreamingResponse(stream_progress(), media_type="text/event-stream")

@app.post("/api/chat")
async def chat_with_brain(request: AskRequest):
    try:
        results = vault_collection.query(query_texts=[request.message], n_results=5)
        context = ""
        if results['documents'] and results['documents'][0]:
            context = "\n".join(results['documents'][0])
        
        prompt = f"Answer the following question based on these notes retrieved from my Second Brain. If the context doesn't contain the answer, say so.\n\nContext:\n{context}\n\nQuestion: {request.message}"
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
        
        # Embed and Save
        chunks = chunk_text(content)
        vault_collection.add(
            documents=chunks,
            metadatas=[{"filename": filename} for _ in chunks],
            ids=[f"{filename}_chunk_{i}" for i in range(len(chunks))]
        )
        return {"status": "success", "fileName": filename}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/sync")
async def sync_vault():
    try:
        subprocess.run(["git", "add", "."], cwd=OBSIDIAN_INBOX_PATH, check=True)
        subprocess.run(["git", "commit", "-m", "Auto-sync"], cwd=OBSIDIAN_INBOX_PATH, check=True)
        subprocess.run(["git", "push"], cwd=OBSIDIAN_INBOX_PATH, check=True)
        return {"status": "success", "message": "Synced successfully"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

@app.get("/api/notes")
async def get_notes():
    index = get_url_index()
    notes = []
    for url, filename in index.items():
        notes.append({"url": url, "fileName": filename, "title": filename.replace(".md", "")})
    return notes

@app.get("/api/notes/{filename}")
async def get_note_content(filename: str):
    filepath = os.path.join(OBSIDIAN_INBOX_PATH, filename)
    if os.path.exists(filepath):
        with open(filepath, "r", encoding="utf-8") as f:
            return f.read()
    raise HTTPException(status_code=404, detail="Note not found")

@app.post("/api/notes/{filename}/summarize")
async def summarize_note(filename: str):
    filepath = os.path.join(OBSIDIAN_INBOX_PATH, filename)
    if not os.path.exists(filepath):
        raise HTTPException(status_code=404, detail="Note not found")
    
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    
    prompt = f"Provide a very concise, 3-bullet-point summary of the following note. Use bolding for key terms. Wrap important entities in [[double brackets]].\n\nContent:\n{content}"
    response = client.models.generate_content(model=AI_MODEL, contents=prompt)
    return {"summary": response.text}

@app.post("/api/notes/{filename}/deep_dive")
async def deep_dive_note(filename: str):
    filepath = os.path.join(OBSIDIAN_INBOX_PATH, filename)
    if not os.path.exists(filepath):
        raise HTTPException(status_code=404, detail="Note not found")
    
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    
    prompt = f"Perform an exhaustive deep-dive analysis of the following note. Explore every key theme, technical detail, and actionable insight. Provide detailed context and synthesise the information for a high-level researcher. Use clear sections with headers. Wrap important entities in [[double brackets]].\n\nContent:\n{content}"
    response = client.models.generate_content(model=AI_MODEL, contents=prompt)
    return {"deep_dive": response.text}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
