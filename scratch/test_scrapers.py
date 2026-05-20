import re
import requests
from bs4 import BeautifulSoup
from readability import Document
from youtube_transcript_api import YouTubeTranscriptApi

def extract_youtube_video_id(url: str) -> str | None:
    patterns = [
        r'(?:v=|\/embed\/|\/shorts\/|\/e\/|youtu\.be\/)([a-zA-Z0-9_-]{11})'
    ]
    for pattern in patterns:
        match = re.search(pattern, url)
        if match:
            return match.group(1)
    return None

# Test YouTube ID Extraction
url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
video_id = extract_youtube_video_id(url)
print(f"Extracted Video ID: {video_id}")

# Test YouTube transcripts
try:
    # dQw4w9WgXcQ is Rickroll, which might have auto-subtitles
    # Let's try to get transcripts
    transcript = YouTubeTranscriptApi.get_transcript(video_id)
    text = " ".join([entry['text'] for entry in transcript])
    print(f"Transcript fetched successfully (length: {len(text)})")
except Exception as e:
    print(f"YouTube transcript fetching failed: {e}")

# Test Readability
url_article = "https://example.com"
try:
    response = requests.get(url_article, headers={'User-Agent': 'Mozilla/5.0'})
    doc = Document(response.text)
    title = doc.title()
    summary_html = doc.summary()
    soup = BeautifulSoup(summary_html, 'html.parser')
    text_content = soup.get_text(separator=' ')
    print(f"Readability parsed example.com: title='{title}', text length={len(text_content)}")
except Exception as e:
    print(f"Readability parsing failed: {e}")
