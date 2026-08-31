# Cortex Change Log

---

## 2026-08-31 - Major Architectural Refactor

### 🚀 Backend Architecture & Modularization
- **Monolith Deconstruction**: Reduced `main.py` from **2,371 lines** to an ultra-thin **87-line** bootstrap application.
- **Modular APIRouters**: Extracted all 47 endpoints into 11 domain-driven router modules in `api/routes/`:
  - `system.py`: Health, status, logs, config, and vault sync.
  - `ingest.py`: URL SSE streaming, document uploads, and raw text clippings.
  - `note_actions.py`: AI summaries, deep dives, task extraction, review timestamps, and note creation.
  - `chat.py`: RAG conversational chat and chat session persistence.
  - `journal.py`: Daily journal append and date/event parsing.
  - `discovery.py`: Weekly brief generator, upcoming events, serendipity, 2D knowledge graph, and inbox counts.
  - `vault.py`: Tags manager, comprehensive vault audit, compile raw clippings, weekly synthesis, and retroactive backlinks.
  - `integrations.py`: Client telemetry analytics, Todoist task sync, Todoist webhook, and FCM device tokens.
  - `auth.py`, `notes.py`, `geofence.py`: Centralized existing route endpoints.
- **Service Layer Extraction**: Created pure business logic layer in `api/services/`:
  - `ingestion.py`: Media acquisition, MD5 deduplication hashing, and unique filename generation.
  - `vault.py`: Hierarchical index generation (`_master-index.md`, `_index.md`), task extraction parser, and system config persistence.
- **Centralized Data Models**: Created `api/models.py` housing 13 centralized Pydantic request and response schemas, eliminating scattered inline models.
- **Zero Circular Dependencies**: Replaced module-level ChromaDB client initialization in `main.py` with a thread-safe lazy singleton in `core/db.py` (`get_vault_collection()`). Severed all circular imports between `main.py`, `api/tasks.py`, `core/synthesis_loop.py`, and `core/retroactive_backlink.py`.

### ⚛️ Frontend React Architecture
- **App.tsx Monolith Deconstruction**: Reduced `src/App.tsx` from **1,188 lines** to **205 lines**, transforming it into a declarative orchestrator.
- **Custom Domain State Hooks**:
  - `useNotes`: Encapsulates note browsing, selection, markdown actions, and weekly brief generation.
  - `useChat`: Encapsulates RAG conversation streams, active note context switching, and Wiki article promotion.
  - `useIngest`: Encapsulates SSE streaming ingestion, drag-and-drop file uploads, voice recording, and global paste listeners.
  - `useSystemStatus`: Encapsulates Celery task queue polling, theme switching, and vault synchronization.
- **Layout Component Decomposition**: Extracted 6 dedicated layout components in `src/components/layout/`:
  - `VaultSidebar.tsx`, `IngestionHeader.tsx`, `NoteViewer.tsx`, `EmptyWorkspace.tsx`, `ChatPanel.tsx`, `ActiveQueueOverlay.tsx`.
- **Typed API Client Layer**: Created `src/services/api.ts` providing typed `notesApi`, `ingestApi`, `chatApi`, and `systemApi` clients.
- **Dependency Pruning**: Cleaned up `package.json` and pruned **127 unused dependencies** (removing backend Express, CORS, Dotenv, and Python SDK artifacts).

### 🔒 Security Hardening & Cruft Cleanup
- **Secrets Protocol**: Replaced hardcoded credentials with dynamic environment variable interpolation (`${NGROK_AUTHTOKEN}`) in `ngrok.yml`.
- **Sanitized Config Templates**: Replaced sensitive `.env.example` keys with safe placeholders and documented all integration variables.
- **Git Ignore Hardening**: Added 8 missing runtime files (`cookies.txt`, `device_tokens.json`, `chat_history.json`, `error_log.json`, `system_config.json`, `firebase_credentials.json`, `scratch/`, `server_logs.db`) to `.gitignore`.
- **Legacy Cruft Removal**: Safely purged abandoned PyQt desktop GUI (`server_app/`, `launch_gui.py`), outdated scratch scripts, and legacy implementation plan backups.

---

## 2026-05-11 - Ingestion Reliability, Status Visibility, and Gemini Fallbacks

### Backend Ingestion
- Persisted raw video transcripts in generated Markdown notes under `## Raw Transcript`.
- Added `transcript_status` metadata to saved notes and `url_index.json` entries.
- Added transcript text and captions to ChromaDB indexing so RAG can retrieve the source transcript, not only Gemini's formatted summary.
- Added download diagnostics to operation state, including media size and transcript character count.
- Collision-safe filenames preventing overwrites across repeated ingests.

### Operation Status
- Expanded backend operation tracking from active-only tasks to active tasks plus recent task history.
- Added stage-level progress updates across download, hashing, transcription, AI analysis, and vector indexing.

### Instagram Carousel Handling
- Implemented dual-provider strategy: `yt-dlp` primary with Instaloader fallback.
- Added composite MD5 hashing over all carousel media assets.

### Gemini Model Fallback Chain
- Configured primary model `models/gemini-2.5-flash-lite` with automatic fallback to `models/gemini-2.5-flash` on server busy / rate limit errors.
