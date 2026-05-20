from youtube_transcript_api import YouTubeTranscriptApi
try:
    data = YouTubeTranscriptApi().fetch('dQw4w9WgXcQ')
    text = " ".join([entry.text for entry in data])
    print("Success! Combined character length:", len(text))
except Exception as e:
    print(f"Failed: {e}")
