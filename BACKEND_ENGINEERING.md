# ⚙️ Cortex: Backend Engineering

The Cortex backend is a high-performance FastAPI server designed for heavy media processing and AI-driven synthesis.

## 🚀 Key Features

### 1. Non-Blocking Concurrency
To prevent the server from freezing during long downloads or transcriptions, the backend uses a **Threaded Async Model**:
- **Async Handlers**: FastAPI handles incoming requests (like status polls) asynchronously.
- **Thread Offloading**: Heavy synchronous tasks (yt-dlp, Whisper, Gemini) are offloaded to a thread pool using `asyncio.to_thread()`.
- **Live Progress**: This allows the server to serve `/api/status` updates while a 10-minute video is still being processed in the background.

### 2. MD5 Content Fingerprinting
Cortex doesn't just check URLs for duplicates—it checks the *content*:
- Every file (audio or image) is hashed using the MD5 algorithm.
- This hash is stored in `url_index.json`.
- **Benefit**: If you share the same video from a different URL (e.g., a re-upload or a different platform), Cortex will identify the duplicate fingerprint and stop ingestion immediately.

### 3. RAG (Retrieval-Augmented Generation)
Cortex uses a state-of-the-art RAG pipeline for the "Ask Your Brain" feature:
- **Vector Storage**: Uses ChromaDB to store high-dimensional embeddings of your notes.
- **Semantic Search**: When you ask a question, the system finds the most relevant "chunks" of your knowledge.
- **Contextual Synthesis**: Relevant chunks are fed into the Gemini model as context, ensuring the AI only answers based on *your* data.

## 📡 API Endpoints

### Ingestion & Status
- `POST /api/ingest`: Accepts a URL. Supports `X-Stream: true` for live status streaming.
- `GET /api/status`: Returns current active tasks and their processing stage.
- `GET /api/config`: Returns system-wide configuration (Model ID, Note Count).

### Vault Management
- `GET /api/notes`: Lists all notes with metadata (title, date, URL, content hash).
- `GET /api/notes/{filename}`: Returns the raw Markdown content for viewing.
- `POST /api/notes/{filename}/summarize`: Triggers a targeted AI summary of a specific note.
- `POST /api/notes/{filename}/deep_dive`: Triggers a comprehensive AI analysis of a specific note.

### Knowledge Query
- `POST /api/chat`: The RAG endpoint. Searches ChromaDB and returns an AI-synthesized answer.
- `POST /api/save_answer`: Saves an AI chat response as a permanent note in the vault.

## 📂 Core Logic Modules
- `main.py`: The entry point and API route definitions.
- `core/processors.py`: The acquisition engine (yt-dlp, Instaloader, Whisper, Gemini).
- `core/state.py`: Manages the global `OperationsManager` for task tracking.
- `core/utils.py`: URL sanitization and platform detection.

## 2026-05-11 Backend Changes

### Transcript Generation and Persistence
- `process_reel()` now returns `raw_transcript`, `transcript_status`, media size, and the model used for AI synthesis.
- Saved Markdown notes include a `## Raw Transcript` section for video content.
- Empty or silent media is recorded as an explicit transcript status instead of disappearing from the note.
- ChromaDB indexing now combines formatted AI content, raw transcript text, and source captions.

### Operation State Model
`OperationManager` now keeps active tasks plus a bounded recent-task history. `/api/status` returns:
- `active_tasks`: tasks currently running.
- `recent_tasks`: recently completed, duplicate, or failed tasks.
- `task_count`: active task count.

Each task can include `task_id`, `url`, `platform`, `status`, `state`, `progress`, `start_time`, `updated_at`, `finished_at`, and `error`.

### Instagram Carousel Pipeline
- Instagram `/p/` posts are downloaded with a provider strategy: `yt-dlp` first, Instaloader fallback second.
- Carousel image files are sent to Gemini vision.
- Carousel video files are transcribed with Faster-Whisper and included in the analysis prompt.
- Duplicate detection uses a composite MD5 over all downloaded carousel media files.
- Metadata failures now include a clear remediation path: refresh `cookies.txt` or retry later if Instagram blocks GraphQL/media access.

### Gemini Fallbacks
All Gemini calls now go through `generate_content_with_fallback()`:
- Primary: `models/gemini-2.5-flash-lite`
- Fallback: `models/gemini-2.5-flash`
- Retry/fallback triggers: 429, 5xx, timeout, unavailable, overloaded, and resource exhaustion style errors.
- Non-retryable errors, such as invalid auth or bad requests, still fail fast.

### Related Endpoint Changes
- `GET /api/config` now returns `primary_model`, `fallback_model`, and `model_chain`.
- `POST /api/ingest` streamed responses are newline-delimited JSON (`application/x-ndjson`).
- Note summary, deep dive, RAG chat, text analysis, and image analysis all share the same Gemini fallback behavior.
