# 🧠 Cortex: System Overview

Cortex is an enterprise-grade, privacy-first personal knowledge management and intelligence platform. It ingests multi-modal data (URLs, videos, audio, PDFs, images, notes), extracts and transcribes content locally, synthesizes rich insights using Gemini AI, and organizes the resulting notes in a bidirectionally-linked Obsidian vault with ChromaDB vector search.

---

## 🏛️ System Architecture

```
                               ┌────────────────────────────────────────┐
                               │           Capture Layer                │
                               │  • React Web Dashboard (Vite)          │
                               │  • Flutter Client (iOS/Android/Desktop)│
                               └───────────────────┬────────────────────┘
                                                   │
                                                   ▼
                               ┌────────────────────────────────────────┐
                               │           API Gateway (FastAPI)        │
                               │  11 Modular Routers in api/routes/     │
                               └───────────┬────────────────┬───────────┘
                                           │                │
                     SSE Stream Ingest     │                │ Asynchronous Background Job
                     (Direct HTTP Stream)  │                │ (X-Queue: true)
                                           ▼                ▼
                             ┌───────────────────┐    ┌───────────────────┐
                             │ api/services/     │    │ Redis Task Broker │
                             │ ingestion.py      │    └─────────┬─────────┘
                             └─────────┬─────────┘              │
                                       │                        ▼
                                       │              ┌───────────────────┐
                                       │              │ Celery Worker     │
                                       │              │ (api/tasks.py)    │
                                       │              └─────────┬─────────┘
                                       ▼                        ▼
                             ┌──────────────────────────────────────────┐
                             │               core/ Engine               │
                             │  • Faster-Whisper (Audio Transcription)  │
                             │  • yt-dlp & Instaloader (Acquisition)    │
                             │  • Gemini 2.5 Flash (AI Synthesis)       │
                             │  • core/db.py (ChromaDB Singleton)       │
                             └─────────────────────┬────────────────────┘
                                                   │
                                                   ▼
                               ┌────────────────────────────────────────┐
                               │             Storage Layer              │
                               │  • Markdown Vault (Obsidian Compatible)│
                               │  • ChromaDB (High-Dimensional Vectors) │
                               │  • url_index.json (State & Fingerprint)│
                               └────────────────────────────────────────┘
```

---

## ⚡ Asynchronous Task Architecture (Celery + Redis)

To support long-running batch ingests and scheduled intelligence jobs without blocking the main event loop, Cortex employs a dual-path execution strategy:

1. **Synchronous SSE Streaming (`X-Stream: true`)**:
   - Ideal for interactive web use where live stage feedback (Downloading $\rightarrow$ Transcribing $\rightarrow$ Synthesizing) is displayed in real-time.
   - Handled directly by `api/services/ingestion.py`.

2. **Asynchronous Celery Queue (`X-Queue: true`)**:
   - Ideal for mobile capture, high-latency video downloads, and batch operations.
   - The route immediately returns `{"task_id": "...", "status": "queued"}`.
   - The task is dispatched to the Redis broker (`REDIS_URL`) and processed in the background by `api.tasks.run_ingestion_task`.
   - Real-time progress is published to `core.state.OperationsManager` and queryable via `GET /api/status`.

---

## 🗄️ Database & Vector Store (`core/db.py` Singleton)

To prevent resource leaks, lock contention, and circular import dependencies, ChromaDB vector collection access is managed via a **lazy singleton** in [`core/db.py`](file:///c:/Users/91704/Desktop/Second-Brain/core/db.py):

```python
# core/db.py
_vault_collection = None

def get_vault_collection():
    """Lazily initializes and returns the persistent ChromaDB collection."""
    global _vault_collection
    if _vault_collection is None:
        client = chromadb.PersistentClient(path="./chroma_db")
        _vault_collection = client.get_or_create_collection(
            name="vault_notes",
            metadata={"hnsw:space": "cosine"}
        )
    return _vault_collection
```

- **Thread-safe & lazy**: Initialized on first query or insertion rather than module import time.
- **Zero Circular Dependencies**: Any service (`ingestion.py`, `synthesis_loop.py`, `retroactive_backlink.py`) can query vector embeddings without importing `main.py`.

---

## 🤖 Background Intelligence Workers

Cortex runs automated background workers managed via Celery Beat schedules or on-demand API endpoints:

1. **Weekly Synthesis (`POST /api/synthesis/weekly`)**:
   - Gathers all notes created over the previous 7 days.
   - Performs topic clustering and synthesizes an executive Weekly Intelligence Brief.
   - Automatically generates a dated Markdown note in `vault/Weekly Brief/` and embeds it in ChromaDB.

2. **Daily Serendipity (`GET /api/serendipity`)**:
   - Resurfaces forgotten knowledge using a weighted decay algorithm that balances historical notes, unexplored categories, and high-connection hubs.

3. **Retroactive Backlinking (`POST /api/maintenance/backlink`)**:
   - Scans existing vault notes against the current universe of note titles.
   - Injects contextual wiki-links (`[[Related Note]]`) into older notes when newly ingested concepts match existing keywords.

---

## 📱 Cross-Platform Architecture (Flutter Client)

The `flutter_client/` is a unified Flutter application targeting:
- **Mobile**: Android (with Share Sheet Intent receiver) and iOS.
- **Desktop**: Windows, macOS, and Linux native desktop builds.
- **Web**: Lightweight capture web app.

### Flutter Architecture Highlights:
- **Provider State Management**: Decoupled view models for `NotesProvider`, `IngestProvider`, and `ChatProvider`.
- **Offline Ingestion Queue**: If the network is unavailable, URLs and clippings are persisted to local SQLite/Hive storage and batch-flushed when connection is restored.
- **Proactive Geofencing**: Queries `/api/nearby` with device coordinates to notify the user of relevant "Spot to Visit" notes within proximity.

---

## 🔄 The Complete Knowledge Lifecycle

1. **Capture**: URL, document, or audio submitted via Web Ingestion Bar, Mobile Share Sheet, or REST API.
2. **Fingerprint**: MD5 composite hash generated over media bytes. If the hash already exists in `url_index.json`, ingestion skips immediately.
3. **Local Transcription**: Audio extracted via `yt-dlp` and transcribed locally via `faster-whisper`.
4. **AI Librarian Structuring**:
   - Transcript and metadata evaluated by Google Gemini 2.5.
   - Frontmatter tags, categories, summaries, and Obsidian wiki-links (`[[Topic]]`) injected.
5. **Dual Persistence**:
   - Physical Markdown file saved to `PROJECT_VAULT_PATH` and synced to `OBSIDIAN_INBOX_PATH`.
   - Semantic text chunks embedded and indexed in ChromaDB.
6. **Query & Chat**: RAG queries match semantic vectors in ChromaDB to ground AI answers with source citations.
