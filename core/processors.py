import os
import json
import uuid
import io
import shutil
import datetime
from PIL import Image
from google import genai
from google.genai import types
from faster_whisper import WhisperModel
import hashlib
import yt_dlp
import instaloader
from .config import GEMINI_API_KEY, AI_MODEL, TAGS_LIST
from .state import ops_manager, get_url_index, save_url_index
from .utils import get_platform_from_url

def calculate_md5(file_path):
    hash_md5 = hashlib.md5()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_md5.update(chunk)
    return hash_md5.hexdigest()

# --- INITIALIZATION ---
print("Configuring AI & Transcription Models...")
client = genai.Client(api_key=GEMINI_API_KEY)

try:
    # Optimized: Using float16 for better speed/memory efficiency
    whisper_model = WhisperModel("large-v3-turbo", device="auto", compute_type="float16")
except Exception as e:
    print(f"Fallback to int8: {e}")
    whisper_model = WhisperModel("base", device="auto", compute_type="int8")

L = instaloader.Instaloader(download_video_thumbnails=False, save_metadata=False, post_metadata_txt_pattern="")

SYSTEM_PROMPT = f"""
You are an AI organizing data for a personal Obsidian Second Brain.
Categorize the content into one of these types: [Recipe, Spot to Visit, Event, Job/Career, General].
You MUST prioritize categorizing this content using the following existing tags: {TAGS_LIST}.
Format the 'formatted_content' precisely based on the category:
- Recipe: Use Markdown checklists (- [ ]) for ingredients, numbered lists for steps.
- Spot to Visit: List Location Name, Vibe, and Highlights.
- Event: List Date/Time, Location, and Expectations.
- Job/Career: Extract key skills and actionable advice.
- General: Provide a clean, readable version with a 3-bullet summary.

Wrap important entities in double brackets for Obsidian wiki-links (e.g., [[Machine Learning]]).

You MUST respond strictly with this JSON structure:
{{
  "category": "The Category",
  "tags": ["#tag1", "#tag2"],
  "summary": "A 1-2 sentence quick summary",
  "formatted_content": "The beautifully formatted markdown text"
}}
"""

import asyncio

# --- Sync helpers (run in thread pool to avoid blocking event loop) ---

def _sync_download_reel(url, ydl_opts, temp_audio):
    """Synchronous yt-dlp download — runs in thread pool."""
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url, download=True)
    content_hash = calculate_md5(temp_audio)
    return {
        'description': info.get('description', ''),
        'uploader': info.get('uploader', 'Unknown'),
        'content_hash': content_hash,
    }

def _sync_transcribe(temp_audio):
    """Synchronous whisper transcription — runs in thread pool."""
    segments, _ = whisper_model.transcribe(temp_audio)
    return "".join([s.text for s in segments]).strip()

def _sync_download_images(post_shortcode, download_path):
    """Synchronous Instaloader download — runs in thread pool."""
    cookies_file = "cookies.txt"
    if os.path.exists(cookies_file):
        try:
            import http.cookiejar
            cj = http.cookiejar.MozillaCookieJar(cookies_file)
            cj.load(ignore_discard=True, ignore_expires=True)
            for cookie in cj:
                L.context._session.cookies.set_cookie(cookie)
        except Exception as e:
            print(f"Cookie load warning: {e}")
    
    post = instaloader.Post.from_shortcode(L.context, post_shortcode)
    L.download_post(post, target=download_path)
    images = [os.path.join(download_path, f) for f in os.listdir(download_path) if f.endswith(('.jpg', '.jpeg', '.webp'))]
    return post, images

def _sync_analyze_images(images):
    """Synchronous image analysis via Gemini — runs in thread pool."""
    content_parts = [f"{SYSTEM_PROMPT}\n\nExtract knowledge from these images."]
    for img_path in images:
        with Image.open(img_path) as img:
            img.thumbnail((1024, 1024))
            if img.mode != "RGB": img = img.convert("RGB")
            buf = io.BytesIO()
            img.save(buf, format='JPEG')
            content_parts.append(types.Part.from_bytes(data=buf.getvalue(), mime_type="image/jpeg"))

    response = client.models.generate_content(model=AI_MODEL, contents=content_parts, config=types.GenerateContentConfig(response_mime_type="application/json"))
    return json.loads(response.text.strip())

def _sync_analyze_text(raw_text):
    """Synchronous text analysis via Gemini — runs in thread pool."""
    prompt = f"{SYSTEM_PROMPT}\n\nTranscript:\n{raw_text}"
    response = client.models.generate_content(model=AI_MODEL, contents=prompt, config=types.GenerateContentConfig(response_mime_type="application/json"))
    return json.loads(response.text.strip())

# --- Async processors (non-blocking, event loop stays free) ---

async def process_image_post(url: str, task_id: str = None, status_callback=None) -> dict:
    if status_callback: await status_callback("Downloading Images")
    if task_id: ops_manager.update_task(task_id, "Downloading Images")
    
    parts = url.split("/")
    post_shortcode = parts[-2] if len(parts[-2]) > 3 else parts[-3]
    download_path = f"temp_{post_shortcode}"

    try:
        # Stage 1: Download (in thread — non-blocking)
        post, images = await asyncio.to_thread(_sync_download_images, post_shortcode, download_path)
        
        # Stage 2: AI Analysis (in thread — non-blocking)
        if status_callback: await status_callback("AI Analyzing Images")
        if task_id: ops_manager.update_task(task_id, "AI Analyzing Images")
        ai_data = await asyncio.to_thread(_sync_analyze_images, images)
        
        content_hash = calculate_md5(images[0])
        
        if os.path.exists(download_path): shutil.rmtree(download_path)
        return {"uploader": post.owner_username, "description": post.caption or "", "url": url, "type": "instagram-carousel", "platform": "instagram", "ai_data": ai_data, "content_hash": content_hash}
    except Exception as e:
        if os.path.exists(download_path): shutil.rmtree(download_path)
        raise e

async def process_reel(url: str, task_id: str = None, status_callback=None) -> dict:
    if status_callback: await status_callback("Downloading Audio")
    if task_id: ops_manager.update_task(task_id, "Downloading Audio")
    temp_audio = f"temp_audio_{uuid.uuid4().hex}.m4a"
    platform = get_platform_from_url(url)
    ydl_opts = {'format': 'm4a/bestaudio/best', 'outtmpl': temp_audio, 'quiet': True}
    
    if os.path.exists("cookies.txt"):
        ydl_opts['cookiefile'] = "cookies.txt"

    try:
        # Stage 1: Download (in thread — non-blocking)
        dl_result = await asyncio.to_thread(_sync_download_reel, url, ydl_opts, temp_audio)
        description = dl_result['description']
        uploader = dl_result['uploader']
        content_hash = dl_result['content_hash']

        # Stage 2: Transcribe (in thread — non-blocking)
        if status_callback: await status_callback("Transcribing Audio")
        if task_id: ops_manager.update_task(task_id, "Transcribing Audio")
        raw_text = await asyncio.to_thread(_sync_transcribe, temp_audio)
        
        # Stage 3: AI Analysis (in thread — non-blocking)
        if status_callback: await status_callback("AI Analyzing Transcript")
        if task_id: ops_manager.update_task(task_id, "AI Analyzing Transcript")
        ai_data = await asyncio.to_thread(_sync_analyze_text, raw_text)

        if os.path.exists(temp_audio): os.remove(temp_audio)
        return {"uploader": uploader, "description": description, "url": url, "type": f"{platform}-video", "platform": platform, "ai_data": ai_data, "content_hash": content_hash}
    except Exception as e:
        if os.path.exists(temp_audio): os.remove(temp_audio)
        raise e
