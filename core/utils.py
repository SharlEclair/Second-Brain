import re
import os
import shutil

def get_platform_from_url(url: str) -> str:
    url_lower = url.lower()
    if "tiktok.com" in url_lower:
        return "tiktok"
    if "youtube.com" in url_lower or "youtu.be" in url_lower:
        return "youtube"
    if "instagram.com" in url_lower or "instagr.am" in url_lower:
        return "instagram"
    if "twitter.com" in url_lower or "x.com" in url_lower:
        return "twitter"
    return "web"

def clean_url(url: str) -> str:
    if not url:
        return ""
    # Extract first HTTP/HTTPS URL if embedded within surrounding caption/text
    match = re.search(r'(https?://[^\s]+)', url)
    if match:
        url = match.group(1)
    # Strip trailing punctuation often appended by share intents (e.g. ., ), ], >, etc.)
    url = re.sub(r'[.,;!?)>\]]+$', '', url)
    # Strip query parameters (tracking params like ?igsh=..., ?utm_source=..., etc.)
    if "?" in url:
        url = url.split("?")[0]
    # Strip URL fragments
    if "#" in url:
        url = url.split("#")[0]
    return url.rstrip("/")

def chunk_text(text: str, chunk_size: int = 1500, overlap: int = 200) -> list[str]:
    try:
        from langchain_text_splitters import RecursiveCharacterTextSplitter
        text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=chunk_size,
            chunk_overlap=overlap,
            length_function=len,
            is_separator_regex=False,
        )
        return text_splitter.split_text(text)
    except ImportError:
        words = text.split()
        chunk_words = chunk_size // 5
        overlap_words = overlap // 5
        if len(words) <= chunk_words: return [text]
        chunks = []
        i = 0
        while i < len(words):
            chunk = " ".join(words[i:i + chunk_words])
            chunks.append(chunk)
            i += (chunk_words - overlap_words)
        return chunks

def cleanup_temp_files():
    print("[Clean] Cleaning up temporary files...")
    count = 0
    for item in os.listdir("."):
        if item.startswith(("temp_audio_", "temp_")):
            try:
                if os.path.isfile(item):
                    os.remove(item)
                elif os.path.isdir(item):
                    shutil.rmtree(item)
                count += 1
            except Exception as e:
                print(f"Failed to delete {item}: {e}")
    if count > 0:
        print(f"[Clean] Removed {count} temporary items.")
