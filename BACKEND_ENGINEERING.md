# ⚙️ Cortex: Backend Engineering & API Reference

The Cortex backend is a modular, high-concurrency FastAPI engine engineered for media acquisition, local audio transcription, AI-driven synthesis, and vector search.

---

## 🏛️ Modular Backend Structure

The backend has been modularized from a legacy monolith into domain-specific routes, decoupled service layers, and core utilities:

```
├── main.py                     # Thin application bootstrap (~87 lines)
├── api/
│   ├── models.py               # 13 Centralized Pydantic models
│   ├── celery_app.py           # Celery broker configuration
│   ├── tasks.py                # Asynchronous Celery background workers
│   ├── routes/                 # 11 Modular APIRouters (47 endpoints)
│   │   ├── system.py           # Health, status, config, sync, logs
│   │   ├── ingest.py           # Multi-modal media ingestion (/ingest, /upload, /ingest_text)
│   │   ├── note_actions.py     # Summarize, deep dive, extract tasks, append tasks, review, create
│   │   ├── chat.py             # RAG conversational chat & session persistence
│   │   ├── journal.py          # Daily journal append & event extraction
│   │   ├── discovery.py        # Weekly brief, upcoming events, serendipity, graph, inbox counts
│   │   ├── vault.py            # Tags, vault audit, compile inbox, synthesis, backlinks
│   │   ├── integrations.py     # Analytics, Todoist sync, webhook, device tokens
│   │   ├── auth.py             # Google OAuth flow
│   │   ├── notes.py            # Vault note CRUD & location tagging
│   │   └── geofence.py         # Geofencing & proximity queries
│   └── services/               # Pure business logic services
│       ├── ingestion.py        # Media processing, duplicate hashing, filename generation
│       └── vault.py            # Index generation, master index, system config, task parser
└── core/                       # Core engine abstractions
    ├── db.py                   # Lazy singleton ChromaDB vector client
    ├── processors.py           # yt-dlp, faster-whisper, Gemini AI fallback chain
    ├── state.py                # OperationManager (Redis / in-memory task tracking)
    ├── config.py               # Centralized configuration & environment loader
    ├── utils.py                # Chunking, text cleaning, temp file lifecycle
    ├── serendipity.py          # Weighted random knowledge surfacing
    ├── synthesis_loop.py       # Automated weekly synthesis worker
    └── retroactive_backlink.py # Vault-wide bidirectional link scanner
```

---

## 📡 API Endpoint Reference

### 1. System & Operations (`api/routes/system.py`)
- `GET /`: API welcome and status summary.
- `GET /api/health`: Healthcheck endpoint for monitoring and container probes.
- `GET /api/status`: Real-time operation tracker returning `active_tasks`, `recent_tasks`, and progress metrics.
- `GET /api/logs`: Retrieves system error log history.
- `POST /api/logs/clear`: Clears the error log database.
- `GET /api/config`: Returns system configuration (active model, model chain, inbox mode).
- `POST /api/config/inbox_mode`: Toggles raw clipping inbox mode.
- `POST /api/sync`: Triggers automated Git push/pull synchronization on the local vault.

### 2. Ingestion (`api/routes/ingest.py`)
- `POST /api/ingest`: Ingests a URL (YouTube, Instagram, TikTok, Web). Supports `X-Stream: true` for SSE streaming or `X-Queue: true` for Celery background processing.
- `POST /api/upload`: Multi-part document, audio, or image file ingestion.
- `POST /api/ingest_text`: Ingests raw text clippings directly into the knowledge base.

### 3. Note Actions (`api/routes/note_actions.py`)
- `POST /api/notes/{filename}/summarize`: Generates a concise 3–5 bullet point executive summary.
- `POST /api/notes/{filename}/deep_dive`: Generates an in-depth analytical breakdown with conceptual connections.
- `POST /api/notes/{filename}/extract_tasks`: Extracts actionable checklist items in Obsidian Markdown syntax (`- [ ]`).
- `POST /api/notes/{filename}/append_tasks`: Appends task items to a note and syncs with `_tasks.json`.
- `POST /api/notes/reviewed`: Updates note metadata and frontmatter timestamp for spaced repetition review.
- `POST /api/notes/create`: Manually creates a new structured note.
- `POST /api/save_answer`: Synthesizes a chat answer into a permanent vault wiki article.

### 4. RAG Chat & History (`api/routes/chat.py`)
- `POST /api/chat`: Contextual conversational RAG endpoint. Queries ChromaDB for top-5 semantic matches and synthesizes answers using Gemini. Accepts optional `session_id` and `note_context`.
- `GET /api/chats`: Lists all saved chat sessions with titles and message counts.
- `GET /api/chats/{session_id}`: Retrieves full message history for a specific chat session.

### 5. Daily Journal & Events (`api/routes/journal.py`)
- `POST /api/journal/append`: Appends a scratchpad note or clipping to today's `YYYY-MM-DD - Daily Journal.md` file. Automatically parses prospective dates to create calendar reminders.

### 6. Discovery & Graph (`api/routes/discovery.py`)
- `GET /api/weekly_brief`: Aggregates notes from the previous 7 days into a structured intelligence brief.
- `GET /api/events/upcoming`: Retrieves upcoming events and deadlines extracted from vault frontmatter.
- `GET /api/suggestions`: Returns random note suggestions to spark creative connections.
- `GET /api/serendipity`: Algorithmically surfaces forgotten or high-value notes.
- `GET /api/graph`: Returns 2D Force Graph nodes and links representing vault wiki-link connections.
- `GET /api/inbox/pending`: Lists raw notes waiting in the inbox.
- `GET /api/raw_count`: Returns total count of uncompiled raw inbox clippings.

### 7. Vault Maintenance & Audits (`api/routes/vault.py`)
- `GET /api/tags`: Returns all active hierarchical tags from `tags.txt`.
- `PUT /api/tags/rename`: Vault-wide tag rename across all physical `.md` files.
- `POST /api/audit`: Comprehensive vault audit. Detects ghost topics (uncreated notes referenced via `[[links]]`), contradictory claims, and coverage gaps.
- `POST /api/synthesis/weekly`: Triggers automated weekly topic synthesis.
- `POST /api/maintenance/backlink`: Runs retroactive link scanner across all notes.
- `POST /api/compile`: Compiles, summarizes, and categorizes raw inbox notes into the main vault.

### 8. Integrations & Webhooks (`api/routes/integrations.py`)
- `POST /api/analytics`: Ingests client usage telemetry into `analytics.json`.
- `GET /api/tasks`: Returns all checklist tasks tracked in `_tasks.json`.
- `POST /api/webhooks/todoist`: Secure HMAC-SHA256 webhook endpoint that marks tasks completed when checked off in Todoist.
- `POST /api/device_token`: Registers mobile FCM device tokens for push notifications.

---

## 🔒 Security & Secrets Protocol

- **Zero Hardcoded Secrets**: All API keys, secrets, and auth tokens are loaded exclusively from `.env` or system environment variables.
- **HMAC Webhook Verification**: Todoist webhooks enforce cryptographic signature validation using `X-Todoist-Hmac-SHA256`.
- **Sanitized Git Baseline**: Runtime assets (`chroma_db/`, `device_tokens.json`, `chat_history.json`, `error_log.json`, `system_config.json`, `firebase_credentials.json`) are ignored in `.gitignore`.
