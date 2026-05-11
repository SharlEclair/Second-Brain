import re
import os
import shutil

def get_platform_from_url(url: str) -> str:
    if "tiktok.com" in url: return "tiktok"
    if "youtube.com" in url or "youtu.be" in url: return "youtube"
    if "instagram.com" in url: return "instagram"
    return "web"

def clean_url(url: str) -> str:
    if "?" in url: url = url.split("?")[0]
    return url.rstrip("/")

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

def cleanup_temp_files():
    print("🧹 Cleaning up temporary files...")
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
        print(f"✓ Removed {count} temporary items.")
