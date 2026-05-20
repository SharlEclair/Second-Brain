import asyncio
import glob
import hashlib
import io
import json
import os
import random
import re
import shutil
import time
import uuid
from typing import Any

from PIL import Image
from google import genai
from google.genai import types
from faster_whisper import WhisperModel
import instaloader
import yt_dlp

from .config import GEMINI_API_KEY, AI_MODEL_CHAIN, TAGS_LIST
from .state import ops_manager
from .utils import get_platform_from_url


IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png", ".webp")
MEDIA_EXTENSIONS = IMAGE_EXTENSIONS + (".mp4", ".m4a", ".mp3", ".webm", ".mov", ".wav", ".ogg", ".aac")
VIDEO_EXTENSIONS = (".mp4", ".webm", ".mov")
AUDIO_EXTENSIONS = (".m4a", ".mp3", ".wav", ".ogg", ".aac", ".webm", ".mp4", ".mov")
RETRYABLE_GEMINI_STATUS_CODES = {429, 500, 502, 503, 504}


def calculate_md5(file_path):
    hash_md5 = hashlib.md5()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_md5.update(chunk)
    return hash_md5.hexdigest()


def calculate_composite_md5(file_paths):
    hash_md5 = hashlib.md5()
    for file_path in sorted(file_paths):
        hash_md5.update(os.path.basename(file_path).encode("utf-8"))
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hash_md5.update(chunk)
    return hash_md5.hexdigest()


def _find_files(folder, extensions=MEDIA_EXTENSIONS):
    if not os.path.exists(folder):
        return []
    files = []
    for root, _, names in os.walk(folder):
        for name in names:
            if name.lower().endswith(extensions):
                files.append(os.path.join(root, name))
    return sorted(files)


def _find_downloaded_media(prefix):
    return sorted(path for path in glob.glob(f"{prefix}.*") if os.path.isfile(path))


def _build_ytdlp_opts(outtmpl, quiet=True):
    opts = {
        "outtmpl": outtmpl,
        "quiet": quiet,
        "no_warnings": quiet,
        "retries": 2,
        "fragment_retries": 2,
        "windowsfilenames": True,
    }
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    cookies_file = os.path.join(project_root, "cookies.txt")
    if os.path.exists(cookies_file):
        opts["cookiefile"] = cookies_file
    return opts


def _metadata_from_info(info):
    if not isinstance(info, dict):
        return {"description": "", "uploader": "Unknown"}

    entries = info.get("entries") or []
    first_entry = next((entry for entry in entries if isinstance(entry, dict)), {})

    return {
        "description": (
            info.get("description")
            or info.get("title")
            or first_entry.get("description")
            or first_entry.get("title")
            or ""
        ),
        "uploader": (
            info.get("uploader")
            or info.get("uploader_id")
            or info.get("channel")
            or first_entry.get("uploader")
            or first_entry.get("uploader_id")
            or "Unknown"
        ),
    }


# --- INITIALIZATION ---
print("Configuring AI & Transcription Models...")
client = genai.Client(api_key=GEMINI_API_KEY)

try:
    whisper_model = WhisperModel("large-v3-turbo", device="auto", compute_type="float16")
except Exception as e:
    print(f"Fallback to int8: {e}")
    whisper_model = WhisperModel("base", device="auto", compute_type="int8")


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

If the content contains a specific upcoming date, time, or deadline (especially for Events or Job/Career items), extract that date and provide it in the 'event_date' field as an ISO 8601 string (e.g., "2024-12-31T19:00:00Z"). If there is no specific date mentioned, leave the field null.

If the category is "Spot to Visit", try to extract the approximate latitude and longitude coordinates of the spot based on your knowledge base.

You MUST respond strictly with this JSON structure:
{{
  "category": "The Category",
  "tags": ["#tag1", "#tag2"],
  "summary": "A 1-2 sentence quick summary",
  "formatted_content": "The beautifully formatted markdown text",
  "event_date": "ISO-8601 string or null",
  "latitude": float or null,
  "longitude": float or null
}}
"""


def _is_retryable_gemini_error(error: Exception) -> bool:
    status_code = getattr(error, "status_code", None) or getattr(error, "code", None)
    if status_code in RETRYABLE_GEMINI_STATUS_CODES:
        return True

    message = str(error).lower()
    retryable_markers = (
        "429",
        "500",
        "502",
        "503",
        "504",
        "resource_exhausted",
        "unavailable",
        "deadline",
        "timeout",
        "temporarily",
        "busy",
        "overloaded",
    )
    return any(marker in message for marker in retryable_markers)


def generate_content_with_fallback(contents: Any, config=None, purpose="generate_content"):
    last_error = None

    for model_index, model in enumerate(AI_MODEL_CHAIN):
        attempts = 3 if model_index == 0 else 2
        for attempt in range(1, attempts + 1):
            try:
                response = client.models.generate_content(model=model, contents=contents, config=config)
                return response, model
            except Exception as error:
                last_error = error
                if not _is_retryable_gemini_error(error):
                    raise

                is_last_attempt_for_model = attempt == attempts
                is_last_model = model_index == len(AI_MODEL_CHAIN) - 1
                if is_last_attempt_for_model and is_last_model:
                    break

                delay = min(8, (2 ** (attempt - 1)) + random.random())
                print(f"Gemini {purpose} failed on {model} attempt {attempt}: {error}. Retrying in {delay:.1f}s")
                time.sleep(delay)

    raise last_error


def _parse_json_response(text, fallback_content):
    raw_text = (text or "").strip()
    if not raw_text:
        return fallback_content

    candidates = [raw_text]
    brace_start = raw_text.find("{")
    brace_end = raw_text.rfind("}")
    if brace_start >= 0 and brace_end > brace_start:
        candidates.append(raw_text[brace_start : brace_end + 1])

    for candidate in candidates:
        try:
            return json.loads(candidate)
        except json.JSONDecodeError:
            cleaned = re.sub(r"[\x00-\x1f]+", " ", candidate)
            try:
                return json.loads(cleaned)
            except json.JSONDecodeError:
                continue

    return fallback_content


def _fallback_ai_data(source_text, reason="AI formatting failed"):
    source_text = (source_text or "").strip()
    summary = "Content was captured, but AI formatting could not be completed."
    formatted = source_text if source_text else "*No extractable text was found.*"
    return {
        "category": "General",
        "tags": ["#uncategorized"],
        "summary": summary,
        "formatted_content": f"*(Note: {reason}; preserved source text below.)*\n\n{formatted}",
    }


# --- Sync helpers (run in thread pool to avoid blocking event loop) ---

def _sync_download_reel(url, ydl_opts, temp_prefix):
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url, download=True)

    media_files = _find_downloaded_media(temp_prefix)
    audio_candidates = [path for path in media_files if path.lower().endswith(AUDIO_EXTENSIONS)]
    if not audio_candidates:
        raise RuntimeError("Media download completed, but no audio/video file was created.")

    audio_path = max(audio_candidates, key=lambda path: os.path.getsize(path))
    if os.path.getsize(audio_path) == 0:
        raise RuntimeError("Downloaded audio/video file is empty.")

    metadata = _metadata_from_info(info)
    return {
        "audio_path": audio_path,
        "description": metadata["description"],
        "uploader": metadata["uploader"],
        "content_hash": calculate_md5(audio_path),
        "media_size": os.path.getsize(audio_path),
    }


def _sync_transcribe(media_path):
    try:
        segments, _ = whisper_model.transcribe(media_path)
        texts = [segment.text.strip() for segment in segments if segment.text and segment.text.strip()]
        return " ".join(texts).strip()
    except Exception as e:
        import subprocess
        import tempfile
        print(f"Direct whisper transcribe failed on {media_path}: {e}. Retrying via FFmpeg audio extraction...")
        
        temp_wav = tempfile.mktemp(suffix=".wav")
        try:
            cmd = ["ffmpeg", "-y", "-i", media_path, "-vn", "-acodec", "pcm_s16le", "-ar", "16000", "-ac", "1", temp_wav]
            result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if result.returncode == 0 and os.path.exists(temp_wav) and os.path.getsize(temp_wav) > 0:
                segments, _ = whisper_model.transcribe(temp_wav)
                texts = [segment.text.strip() for segment in segments if segment.text and segment.text.strip()]
                return " ".join(texts).strip()
            else:
                print(f"FFmpeg extraction failed (code {result.returncode}). Stderr: {result.stderr.decode('utf-8', errors='ignore')}")
                raise e
        except Exception as ex:
            print(f"FFmpeg extraction fallback failed: {ex}")
            raise e
        finally:
            if os.path.exists(temp_wav):
                try:
                    os.remove(temp_wav)
                except:
                    pass


def _sync_download_instagram_with_ytdlp(url, download_path):
    os.makedirs(download_path, exist_ok=True)
    outtmpl = os.path.join(download_path, "%(id)s_%(autonumber)s.%(ext)s")
    ydl_opts = _build_ytdlp_opts(outtmpl)

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url, download=True)

    media_files = _find_files(download_path)
    if not media_files:
        raise RuntimeError("yt-dlp did not download any Instagram carousel media.")

    metadata = _metadata_from_info(info)
    return {
        "source": "yt-dlp",
        "description": metadata["description"],
        "uploader": metadata["uploader"],
        "media_files": media_files,
    }


def _sync_download_instagram_with_instaloader(post_shortcode, download_path):
    loader = instaloader.Instaloader(
        download_video_thumbnails=False,
        save_metadata=False,
        post_metadata_txt_pattern="",
        quiet=True,
    )

    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    cookies_file = os.path.join(project_root, "cookies.txt")
    if os.path.exists(cookies_file):
        try:
            import http.cookiejar

            cookie_jar = http.cookiejar.MozillaCookieJar(cookies_file)
            cookie_jar.load(ignore_discard=True, ignore_expires=True)

            # Convert cookie jar to a flat dict for load_session.
            # load_session creates an entirely new requests.Session (not the anonymous
            # one from the constructor), which avoids the duplicate empty-domain cookie
            # issue that caused Instagram to return null data.
            cookie_dict = {cookie.name: cookie.value for cookie in cookie_jar}
            username = cookie_dict.get("ds_user_id", "unknown")
            loader.context.load_session(username, cookie_dict)
        except Exception as error:
            print(f"Cookie load warning: {error}")

    # Set a realistic browser User-Agent to avoid Instagram blocking
    loader.context._session.headers.update({
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    })

    post = instaloader.Post.from_shortcode(loader.context, post_shortcode)
    loader.download_post(post, target=download_path)
    media_files = _find_files(download_path)
    if not media_files:
        raise RuntimeError("Instaloader did not download any Instagram carousel media.")

    return {
        "source": "instaloader",
        "description": post.caption or "",
        "uploader": post.owner_username or "Unknown",
        "media_files": media_files,
    }


def _sync_download_instagram_post(url, post_shortcode, download_path):
    ytdlp_error = None
    try:
        return _sync_download_instagram_with_ytdlp(url, download_path)
    except Exception as error:
        ytdlp_error = error
        if os.path.exists(download_path):
            shutil.rmtree(download_path)

    try:
        return _sync_download_instagram_with_instaloader(post_shortcode, download_path)
    except Exception as instaloader_error:
        raise RuntimeError(
            "Instagram metadata/media fetch failed. Refresh cookies.txt or retry later; "
            f"yt-dlp error: {ytdlp_error}; Instaloader error: {instaloader_error}"
        ) from instaloader_error


def _sync_analyze_images(images, description="", transcript_text=""):
    context = "\n\n".join(
        part
        for part in [
            f"{SYSTEM_PROMPT}\n\nExtract knowledge from these images.",
            f"Caption/description:\n{description}" if description else "",
            f"Video/audio transcript from this carousel:\n{transcript_text}" if transcript_text else "",
        ]
        if part
    )
    content_parts = [context]

    for img_path in images:
        with Image.open(img_path) as img:
            img.thumbnail((1024, 1024))
            if img.mode != "RGB":
                img = img.convert("RGB")
            buf = io.BytesIO()
            img.save(buf, format="JPEG")
            content_parts.append(types.Part.from_bytes(data=buf.getvalue(), mime_type="image/jpeg"))

    fallback_text = "\n\n".join(part for part in [description, transcript_text] if part)
    response, model_used = generate_content_with_fallback(
        contents=content_parts,
        config=types.GenerateContentConfig(response_mime_type="application/json"),
        purpose="image_analysis",
    )
    ai_data = _parse_json_response(response.text, _fallback_ai_data(fallback_text, "AI image JSON parsing failed"))
    ai_data["_model_used"] = model_used
    return ai_data


def _sync_analyze_text(raw_text, description=""):
    analysis_text = "\n\n".join(part for part in [raw_text, f"Caption/description:\n{description}" if description else ""] if part)
    prompt = f"{SYSTEM_PROMPT}\n\nTranscript:\n{analysis_text}"
    response, model_used = generate_content_with_fallback(
        contents=prompt,
        config=types.GenerateContentConfig(response_mime_type="application/json"),
        purpose="text_analysis",
    )
    ai_data = _parse_json_response(response.text, _fallback_ai_data(analysis_text, "AI text JSON parsing failed"))
    ai_data["_model_used"] = model_used
    return ai_data


def _cleanup_paths(paths):
    for path in paths:
        try:
            if os.path.isfile(path):
                os.remove(path)
            elif os.path.isdir(path):
                shutil.rmtree(path)
        except Exception as error:
            print(f"Cleanup warning for {path}: {error}")


# --- Async processors (non-blocking, event loop stays free) ---

async def process_image_post(url: str, task_id: str = None, status_callback=None) -> dict:
    if status_callback:
        await status_callback("Downloading Instagram carousel media")
    if task_id:
        ops_manager.update_task(task_id, "Downloading Instagram carousel media", progress=20)

    # Extract shortcode from Instagram URL - handles both with and without trailing slash
    # e.g. /p/DYcOwEZCGCX/ or /p/DYcOwEZCGCX
    shortcode_match = re.search(r'/p/([A-Za-z0-9_-]+)', url)
    post_shortcode = shortcode_match.group(1) if shortcode_match else url.split("/")[-1]
    download_path = f"temp_{post_shortcode}_{uuid.uuid4().hex[:8]}"

    try:
        download_result = await asyncio.to_thread(_sync_download_instagram_post, url, post_shortcode, download_path)
        media_files = download_result["media_files"]
        image_files = [path for path in media_files if path.lower().endswith(IMAGE_EXTENSIONS)]
        transcript_media = [path for path in media_files if path.lower().endswith(VIDEO_EXTENSIONS)]

        if status_callback:
            await status_callback("Hashing carousel media")
        if task_id:
            ops_manager.update_task(task_id, "Hashing carousel media", progress=35)
        content_hash = calculate_composite_md5(media_files)

        transcript_parts = []
        for index, media_path in enumerate(transcript_media, start=1):
            if status_callback:
                await status_callback(f"Transcribing carousel video {index}/{len(transcript_media)}")
            if task_id:
                ops_manager.update_task(task_id, f"Transcribing carousel video {index}/{len(transcript_media)}", progress=45)
            transcript = await asyncio.to_thread(_sync_transcribe, media_path)
            if transcript:
                transcript_parts.append(transcript)

        raw_transcript = "\n\n".join(transcript_parts).strip()
        transcript_status = "complete" if raw_transcript else ("not_applicable" if not transcript_media else "empty")

        if status_callback:
            await status_callback("AI analyzing carousel")
        if task_id:
            ops_manager.update_task(task_id, "AI analyzing carousel", progress=70)

        description = download_result["description"]
        if image_files:
            ai_data = await asyncio.to_thread(_sync_analyze_images, image_files, description, raw_transcript)
        else:
            source_text = raw_transcript or description
            ai_data = await asyncio.to_thread(_sync_analyze_text, source_text, description)

        _cleanup_paths([download_path])
        return {
            "uploader": download_result["uploader"],
            "description": description,
            "url": url,
            "type": "instagram-carousel",
            "platform": "instagram",
            "ai_data": ai_data,
            "content_hash": content_hash,
            "raw_transcript": raw_transcript,
            "transcript_status": transcript_status,
            "media_count": len(media_files),
            "processor": download_result["source"],
        }
    except Exception:
        _cleanup_paths([download_path])
        raise



async def _async_fetch_twitter_thread(url):
    import twscrape
    import re
    tweet_id_match = re.search(r'status/(\d+)', url)
    if not tweet_id_match:
        raise ValueError("Could not find tweet ID in URL")
    tweet_id = int(tweet_id_match.group(1))

    api = twscrape.API()
    try:
        tweet = await api.tweet_details(tweet_id)
        if not tweet:
             raise ValueError("Tweet not found")

        text = tweet.rawContent
        author = tweet.user.username if tweet.user else "Twitter User"

        return {
            "title": f"Tweet by {author}",
            "text": text,
            "author": author
        }
    except Exception as e:
        return await asyncio.to_thread(_sync_fetch_web_article, url)

def _sync_fetch_web_article(url):
    import requests
    from bs4 import BeautifulSoup
    response = requests.get(url, headers={'User-Agent': 'Mozilla/5.0'})
    response.raise_for_status()

    try:
        from readability import Document
        doc = Document(response.text)
        title = doc.title() or "Web Article"
        summary_html = doc.summary()
        soup = BeautifulSoup(summary_html, 'html.parser')
        text = soup.get_text(separator=' ')
    except Exception as e:
        print(f"Readability-lxml parsing failed: {e}. Falling back to default BeautifulSoup parser.")
        soup = BeautifulSoup(response.text, 'html.parser')
        for script in soup(["script", "style"]):
            script.extract()
        title = soup.title.string if soup.title else "Web Article"
        text = soup.get_text(separator=' ')

    lines = (line.strip() for line in text.splitlines())
    chunks = (phrase.strip() for line in lines for phrase in line.split("  "))
    text = '\n'.join(chunk for chunk in chunks if chunk)

    return {
        "title": title,
        "text": text,
        "author": "Web Source"
    }

async def process_web_article(url: str, task_id: str = None, status_callback=None) -> dict:
    if status_callback:
        await status_callback("Fetching text content")
    if task_id:
        ops_manager.update_task(task_id, "Fetching text content", progress=20)

    try:
        from core.utils import get_platform_from_url
        platform = get_platform_from_url(url)

        if platform == "twitter":
            article_data = await _async_fetch_twitter_thread(url)
        else:
            article_data = await asyncio.to_thread(_sync_fetch_web_article, url)

        if status_callback:
            await status_callback("AI analyzing article text")
        if task_id:
            ops_manager.update_task(task_id, "AI analyzing article text", progress=70)

        import hashlib
        content_hash = hashlib.md5(article_data["text"].encode('utf-8')).hexdigest()
        ai_data = await asyncio.to_thread(_sync_analyze_text, article_data["text"], article_data["title"])

        return {
            "uploader": article_data["author"],
            "description": article_data["title"],
            "url": url,
            "type": "web-article",
            "platform": "web",
            "ai_data": ai_data,
            "content_hash": content_hash,
            "raw_transcript": article_data["text"],
            "transcript_status": "complete",
            "processor": "beautifulsoup"
        }
    except Exception:
        raise

def _sync_extract_pdf_text(filepath):
    import fitz # PyMuPDF
    doc = fitz.open(filepath)
    text = ""
    for page in doc:
        text += page.get_text()

    title = os.path.basename(filepath)
    if doc.metadata and doc.metadata.get("title"):
        title = doc.metadata.get("title")

    author = "Unknown Author"
    if doc.metadata and doc.metadata.get("author"):
        author = doc.metadata.get("author")

    return {
        "text": text,
        "title": title,
        "author": author
    }

async def process_pdf(filepath: str, original_filename: str, task_id: str = None, status_callback=None) -> dict:
    if status_callback:
        await status_callback("Extracting text from PDF")
    if task_id:
        ops_manager.update_task(task_id, "Extracting text from PDF", progress=20)

    try:
        pdf_data = await asyncio.to_thread(_sync_extract_pdf_text, filepath)

        if status_callback:
            await status_callback("AI analyzing PDF content")
        if task_id:
            ops_manager.update_task(task_id, "AI analyzing PDF content", progress=70)

        import hashlib
        content_hash = hashlib.md5(pdf_data["text"].encode('utf-8')).hexdigest()
        ai_data = await asyncio.to_thread(_sync_analyze_text, pdf_data["text"], pdf_data["title"])

        return {
            "uploader": pdf_data["author"],
            "description": pdf_data["title"],
            "url": f"file://{original_filename}",
            "type": "pdf-document",
            "platform": "local",
            "ai_data": ai_data,
            "content_hash": content_hash,
            "raw_transcript": pdf_data["text"],
            "transcript_status": "complete",
            "processor": "pymupdf"
        }
    except Exception:
        raise

def _extract_youtube_video_id(url: str) -> str | None:
    patterns = [
        r'(?:v=|\/embed\/|\/shorts\/|\/e\/|youtu\.be\/)([a-zA-Z0-9_-]{11})'
    ]
    for pattern in patterns:
        match = re.search(pattern, url)
        if match:
            return match.group(1)
    return None


def _fetch_youtube_transcript_api(video_id: str) -> str | None:
    try:
        from youtube_transcript_api import YouTubeTranscriptApi
        data = YouTubeTranscriptApi().fetch(video_id)
        return " ".join([entry.text for entry in data]).strip()
    except Exception as e:
        print(f"Failed to fetch YouTube subtitles via API: {e}")
        return None


async def process_reel(url: str, task_id: str = None, status_callback=None) -> dict:
    platform = get_platform_from_url(url)
    
    if platform == "youtube":
        video_id = _extract_youtube_video_id(url)
        if video_id:
            if status_callback:
                await status_callback("Fetching video transcript")
            if task_id:
                ops_manager.update_task(task_id, "Fetching video transcript", progress=30)
            
            transcript = await asyncio.to_thread(_fetch_youtube_transcript_api, video_id)
            if transcript:
                if status_callback:
                    await status_callback("AI analyzing transcript")
                if task_id:
                    ops_manager.update_task(task_id, "AI analyzing transcript", progress=70)
                
                try:
                    ydl_opts = _build_ytdlp_opts("", quiet=True)
                    ydl_opts["skip_download"] = True
                    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                        info = await asyncio.to_thread(ydl.extract_info, url, download=False)
                    metadata = _metadata_from_info(info)
                    description = metadata["description"]
                    uploader = metadata["uploader"]
                except Exception as e:
                    print(f"Failed to fetch metadata for YouTube video: {e}")
                    description = f"YouTube video {video_id}"
                    uploader = "YouTube"

                ai_data = await asyncio.to_thread(_sync_analyze_text, transcript, description)
                import hashlib
                content_hash = hashlib.md5(transcript.encode('utf-8')).hexdigest()
                
                return {
                    "uploader": uploader,
                    "description": description,
                    "url": url,
                    "type": "youtube-video",
                    "platform": "youtube",
                    "ai_data": ai_data,
                    "content_hash": content_hash,
                    "raw_transcript": transcript,
                    "transcript_status": "complete",
                    "media_size": 0,
                }

    if status_callback:
        await status_callback("Downloading audio/video")
    if task_id:
        ops_manager.update_task(task_id, "Downloading audio/video", progress=20)

    temp_prefix = f"temp_audio_{uuid.uuid4().hex}"
    ydl_opts = _build_ytdlp_opts(f"{temp_prefix}.%(ext)s")
    ydl_opts["format"] = "bestaudio/best"

    try:
        dl_result = await asyncio.to_thread(_sync_download_reel, url, ydl_opts, temp_prefix)
        temp_audio = dl_result["audio_path"]
        description = dl_result["description"]
        uploader = dl_result["uploader"]
        content_hash = dl_result["content_hash"]

        if status_callback:
            await status_callback("Transcribing audio")
        if task_id:
            ops_manager.update_task(
                task_id,
                "Transcribing audio",
                progress=45,
                media_size=dl_result.get("media_size"),
            )
        raw_text = await asyncio.to_thread(_sync_transcribe, temp_audio)
        transcript_status = "complete" if raw_text else "empty"
        analysis_text = raw_text or description

        if status_callback:
            await status_callback("AI analyzing transcript")
        if task_id:
            ops_manager.update_task(
                task_id,
                "AI analyzing transcript",
                progress=70,
                transcript_chars=len(raw_text),
            )
        ai_data = await asyncio.to_thread(_sync_analyze_text, analysis_text, description)

        _cleanup_paths(_find_downloaded_media(temp_prefix))
        return {
            "uploader": uploader,
            "description": description,
            "url": url,
            "type": f"{platform}-video",
            "platform": platform,
            "ai_data": ai_data,
            "content_hash": content_hash,
            "raw_transcript": raw_text,
            "transcript_status": transcript_status,
            "media_size": dl_result.get("media_size"),
        }
    except Exception:
        _cleanup_paths(_find_downloaded_media(temp_prefix))
        raise

def _sync_extract_text_file_content(filepath):
    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
        text = f.read()
    title = os.path.basename(filepath)
    return {
        "text": text,
        "title": title,
        "author": "Local Text File"
    }

async def process_text_file(filepath: str, original_filename: str, task_id: str = None, status_callback=None) -> dict:
    if status_callback:
        await status_callback("Reading text file")
    if task_id:
        ops_manager.update_task(task_id, "Reading text file", progress=20)

    try:
        file_data = await asyncio.to_thread(_sync_extract_text_file_content, filepath)

        if status_callback:
            await status_callback("AI analyzing text content")
        if task_id:
            ops_manager.update_task(task_id, "AI analyzing text content", progress=70)

        import hashlib
        content_hash = hashlib.md5(file_data["text"].encode('utf-8')).hexdigest()
        ai_data = await asyncio.to_thread(_sync_analyze_text, file_data["text"], file_data["title"])

        return {
            "uploader": file_data["author"],
            "description": file_data["title"],
            "url": f"file://{original_filename}",
            "type": "text-document",
            "platform": "local",
            "ai_data": ai_data,
            "content_hash": content_hash,
            "raw_transcript": file_data["text"],
            "transcript_status": "complete",
            "processor": "text-reader"
        }
    except Exception:
        raise

async def process_raw_text(text: str, title: str, task_id: str = None, status_callback=None) -> dict:
    if status_callback:
        await status_callback("AI analyzing raw text")
    if task_id:
        ops_manager.update_task(task_id, "AI analyzing raw text", progress=50)

    try:
        import hashlib
        content_hash = hashlib.md5(text.encode('utf-8')).hexdigest()
        ai_data = await asyncio.to_thread(_sync_analyze_text, text, title)

        return {
            "uploader": "Shared Text",
            "description": title,
            "url": f"local://shared-text-{task_id or uuid.uuid4().hex[:8]}",
            "type": "shared-text",
            "platform": "local",
            "ai_data": ai_data,
            "content_hash": content_hash,
            "raw_transcript": text,
            "transcript_status": "complete",
            "processor": "raw-text-processor"
        }
    except Exception:
        raise

async def process_audio_file(filepath: str, original_filename: str, task_id: str = None, status_callback=None) -> dict:
    if status_callback:
        await status_callback("Transcribing audio file")
    if task_id:
        ops_manager.update_task(task_id, "Transcribing audio file", progress=30)

    try:
        raw_text = await asyncio.to_thread(_sync_transcribe, filepath)
        transcript_status = "complete" if raw_text else "empty"

        if status_callback:
            await status_callback("AI analyzing transcript")
        if task_id:
            ops_manager.update_task(task_id, "AI analyzing transcript", progress=70)

        import hashlib
        content_hash = hashlib.md5(raw_text.encode('utf-8')).hexdigest() if raw_text else hashlib.md5(original_filename.encode('utf-8')).hexdigest()
        ai_data = await asyncio.to_thread(_sync_analyze_text, raw_text or "No transcribed text.", original_filename)

        return {
            "uploader": "Local Audio File",
            "description": original_filename,
            "url": f"file://{original_filename}",
            "type": "audio-document",
            "platform": "local",
            "ai_data": ai_data,
            "content_hash": content_hash,
            "raw_transcript": raw_text,
            "transcript_status": transcript_status,
            "processor": "whisper-transcriber"
        }
    except Exception:
        raise

async def process_uploaded_image(filepath: str, original_filename: str, task_id: str = None, status_callback=None) -> dict:
    if status_callback:
        await status_callback("Analyzing image file")
    if task_id:
        ops_manager.update_task(task_id, "Analyzing image file", progress=30)

    try:
        if status_callback:
            await status_callback("AI analyzing image content")
        if task_id:
            ops_manager.update_task(task_id, "AI analyzing image content", progress=70)

        content_hash = calculate_md5(filepath)
        ai_data = await asyncio.to_thread(_sync_analyze_images, [filepath], original_filename)

        return {
            "uploader": "Local Image File",
            "description": original_filename,
            "url": f"file://{original_filename}",
            "type": "image-document",
            "platform": "local",
            "ai_data": ai_data,
            "content_hash": content_hash,
            "raw_transcript": "",
            "transcript_status": "not_applicable",
            "processor": "gemini-vision"
        }
    except Exception:
        raise

