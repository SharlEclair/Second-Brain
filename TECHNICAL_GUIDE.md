# Technical Guide: Second Brain Internals

This document provides a deep-dive into the engineering decisions and technical workflows of the Second Brain system.

## 1. The Ingestion Pipeline

When a URL is submitted to `/api/ingest`, the system follows this workflow:

1. **Platform Detection**: Identifies if the URL is Instagram, YouTube, TikTok, or a generic Web page.
2. **Media Extraction**:
   - **Video**: Uses `yt-dlp` to extract the best available audio/video stream, then locates the actual downloaded media file by temporary prefix.
   - **Instagram Carousel**: Uses `yt-dlp` first and Instaloader as a fallback. Images are analyzed visually; carousel videos are transcribed.
3. **Transcription/Vision**:
   - **Audio**: Processed via `faster-whisper` using the `large-v3-turbo` model. It features an automatic fallback to the `base` model if system resources are low.
   - **Images**: Sent as a multi-modal payload to Gemini Vision.
4. **Structured Analysis**:
   - The transcript/description is sent to **Gemini 2.5 Flash Lite** with **Gemini 2.5 Flash** as the busy/server-error fallback.
   - Categorization is enforced via the hierarchical `tags.txt` file.
5. **Obsidian Storage**:
   - A Markdown file is generated with YAML frontmatter.
   - Raw transcripts are preserved in a `## Raw Transcript` section and included in vector indexing.
   - Wiki-links `[[entities]]` are automatically generated for cross-linking in Obsidian.

## 2. RAG (Retrieval-Augmented Generation)

The "Chat" feature uses a local RAG pipeline:
- **Embeddings**: Text chunks are embedded and stored through ChromaDB's configured embedding flow.
- **Vector Store**: **ChromaDB** stores the vectors locally in `./chroma_db`.
- **Retrieval**: When a question is asked, the top 5 most relevant chunks are retrieved and injected into the AI context as "Ground Truth".

## 3. Real-time Communication

The backend uses newline-delimited JSON via FastAPI's `StreamingResponse`. This allows the server to push status updates to the React frontend during long-running tasks:
- `{"status": "status", "message": "Downloading audio/video..."}`
- `{"status": "success", "task_id": "...", "note": {...}}`

The backend also exposes `/api/status`, which returns active tasks and recent task history for polling clients.

### Content Negotiation
The `/api/ingest` endpoint is polymorphic:
- **Web UI**: Sends `X-Stream: true` and receives newline-delimited JSON progress.
- **Mobile App**: Sends standard `application/json`, polls `/api/status` for the matching URL, and receives a single final result after processing completes.

## 4. Mobile Integration (Flutter)

The Flutter app leverages **Deep Intent Filters** in Android. When you share a URL from Instagram to the Second Brain app:
1. The `AndroidManifest.xml` catches the `SEND` intent.
2. `ReceiveSharingIntent` captures the URL.
3. The app hits `/api/ingest`, polls `/api/status` while the request is active, and shows the current backend stage.
4. If the backend is unreachable, the URL is saved to the offline queue for later batch processing.

## 5. Security & Synchronization

- **Environment**: All secrets are stored in `.env`.
- **Git Sync**: The app automates `git add`, `commit`, and `push`. This treats your Obsidian vault as a Git repository, providing version history and off-site backup to GitHub.
- **CORS**: Configured in `main.py` to allow cross-origin requests from the Flutter app and local dev servers.
