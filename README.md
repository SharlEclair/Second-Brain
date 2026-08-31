# 🧠 Second Brain (Cortex): AI-Powered Personal Knowledge Vault

Second Brain is a modern, production-ready personal knowledge management and intelligence system. It automatically captures, transcribes, categorizes, and indexes multi-modal content (social media URLs from Instagram, YouTube, TikTok, plus PDFs, audio recordings, images, and text clippings) into a structured, bidirectional-linked Obsidian Markdown vault. It features a RAG-enabled (Retrieval-Augmented Generation) chat engine, automated background synthesis, proactive knowledge graph exploration, and cross-platform capture clients.

---

## 🚀 Key Features

- **Omni-Ingestion Pipeline**: Ingest URLs (YouTube, Instagram Reels & Carousels, TikTok, Web articles), local documents (PDF, TXT, MD), audio recordings (WAV, MP3, M4A), and image files.
- **High-Performance Audio Transcription**: Local, fast transcription powered by `faster-whisper` (`large-v3-turbo` with `int8`/`float16` acceleration).
- **AI Synthesis & Auto-Classification**: Uses Google Gemini 2.5 (`gemini-2.5-flash-lite` primary with automatic fallback to `gemini-2.5-flash`) to categorize content into Recipes, Spots to Visit, Tech Guides, Career, and more with Obsidian frontmatter and wiki-links (`[[Note Title]]`).
- **RAG Terminal & Contextual Chat**: Chat with your entire knowledge vault using ChromaDB vector embeddings. Support for targeting active note context and one-click "Promote to Wiki Article" generation.
- **Background Intelligence Loops**: Celery + Redis worker queues power automated Weekly Synthesis briefs, daily Serendipity resurfacing, and retroactive link analysis.
- **Vault Auditing & Ghost Topics**: Detect conflicting information, coverage gaps, and uncreated notes referenced via wiki-links (`[[Ghost Notes]]`).
- **Cross-Platform Capture**:
  - **Web Dashboard**: Modern, responsive React 19 + Vite dashboard with interactive 2D Force Graph, Activity Heatmaps, and real-time task queue overlays.
  - **Flutter Client**: Cross-platform application supporting **Android, iOS, Windows, macOS, Linux, and Web** with native system Share Sheet integration for one-tap ingestion.
- **One-Click Orchestration**: A unified service runner (`python run_services.py`) that manages Docker Redis, Celery workers, Celery Beat, FastAPI, Vite dev server, and Ngrok tunnels simultaneously.

---

## 🛠️ Architecture Overview

```
                          ┌────────────────────────┐
                          │   Cross-Platform Apps  │
                          │ React Web / Flutter App│
                          └───────────┬────────────┘
                                      │
                                      ▼
                      ┌───────────────────────────────┐
                      │    FastAPI Gateway (8000)     │
                      │       (api/routes/*)          │
                      └───────┬───────────────┬───────┘
                              │               │
             Direct Sync / SSE│               │ Queue Tasks (X-Queue)
                              ▼               ▼
                   ┌─────────────────┐ ┌──────────────┐
                   │  api/services/  │ │ Redis Broker │
                   │  ingestion.py   │ └──────┬───────┘
                   │    vault.py     │        │
                   └────────┬────────┘        ▼
                            │        ┌─────────────────┐
                            │        │  Celery Worker  │
                            │        │  (api/tasks.py) │
                            │        └────────┬────────┘
                            ▼                 ▼
          ┌────────────────────────────────────────────────────────┐
          │                      core/ Engine                      │
          │  processors.py  •  db.py (ChromaDB)  •  config.py     │
          └───────────────────────────┬────────────────────────────┘
                                      │
                                      ▼
                      ┌───────────────────────────────┐
                      │         Storage Layer         │
                      │  Obsidian Vault / ChromaDB /  │
                      │         url_index.json        │
                      └───────────────────────────────┘
```

---

## 📥 Quick Start

### Prerequisites
- **Python 3.10+** (with virtual environment recommended)
- **Node.js 18+** & **npm**
- **FFmpeg** (installed and added to system `PATH` for media processing)
- **Docker Desktop** (optional, for Redis container orchestration)
- **Flutter SDK** (optional, for building the mobile/desktop client)

---

### Step 1: Clone & Configure Environment

1. Clone the repository:
   ```bash
   git clone https://github.com/SharlEclair/Second-Brain.git
   cd Second-Brain
   ```

2. Create your `.env` file from the provided template:
   ```bash
   cp .env.example .env
   ```

3. Open `.env` and fill in your keys:
   ```ini
   # Required: Get from https://aistudio.google.com/app/apikey
   GEMINI_API_KEY="your_google_gemini_api_key"

   # Vault Storage Paths
   OBSIDIAN_INBOX_PATH="C:/Path/To/Your/Obsidian/Vault/Inbox"
   PROJECT_VAULT_PATH="./vault"

   # Celery Redis Broker URL
   REDIS_URL="redis://localhost:6379/0"

   # Ngrok Authtoken (for remote tunnel access)
   NGROK_AUTHTOKEN="your_ngrok_authtoken_here"
   ```

---

### Step 2: Install Dependencies

**Backend Python Packages:**
```bash
python -m venv venv
.\venv\Scripts\activate      # Windows
# source venv/bin/activate   # macOS / Linux
pip install -r requirements.txt
```

**Frontend Node Packages:**
```bash
npm install
```

---

### Step 3: Run the Complete Stack

Launch all services with the unified service orchestrator:
```bash
python run_services.py
```

This single command starts:
1. **Redis**: Starts or initializes the Docker container on port `6379`.
2. **Backend**: FastAPI REST API server on `http://127.0.0.1:8000`.
3. **Frontend**: Vite React web dashboard on `http://localhost:5173`.
4. **Celery Worker**: Background ingestion task processor.
5. **Celery Beat**: Periodic cron scheduler for weekly briefs and maintenance.
6. **Ngrok Tunnel**: Secure public HTTPS endpoint for remote capture.

---

## 📱 Cross-Platform Client (Flutter)

The `flutter_client/` directory contains the multi-platform client:

```bash
cd flutter_client
flutter pub get

# Run on your preferred connected target:
flutter run -d chrome     # Web
flutter run -d windows    # Windows Desktop
flutter run -d android    # Android Device
flutter run -d macos      # macOS Desktop
flutter run -d ios        # iOS Simulator / Device
```

In the app settings, set your **Backend URL** to your local network address (`http://192.168.x.x:8000`) or your public Ngrok tunnel URL.

---

## 📂 Repository Structure

```text
├── main.py                  # Lightweight FastAPI bootstrap (~87 lines)
├── run_services.py          # Unified multi-service orchestrator
├── api/
│   ├── models.py            # Centralized Pydantic request & response models
│   ├── celery_app.py        # Celery broker & task configuration
│   ├── tasks.py             # Asynchronous worker task definitions
│   ├── routes/              # Modular APIRouter controllers
│   │   ├── system.py        # Health, status, config, sync, logs
│   │   ├── ingest.py        # URL, File upload, and Text ingestion
│   │   ├── note_actions.py  # Summarize, Deep dive, Extract tasks, Review, Create
│   │   ├── chat.py          # RAG chat endpoint & session management
│   │   ├── journal.py       # Daily journal append & event extraction
│   │   ├── discovery.py     # Weekly brief, upcoming events, serendipity, graph
│   │   ├── vault.py         # Tags, audit, compile, synthesis, backlinks
│   │   ├── integrations.py  # Analytics, Todoist task sync, device tokens
│   │   ├── auth.py          # Google OAuth authentication flow
│   │   ├── notes.py         # Vault note CRUD & location tagging
│   │   └── geofence.py      # Geofencing & proximity queries
│   └── services/            # Business logic services
│       ├── ingestion.py     # Multi-modal media processing & duplicate hashing
│       └── vault.py         # Index generation, config persistence, task parser
├── core/
│   ├── config.py            # Centralized settings & model fallback chains
│   ├── db.py                # Lazy singleton ChromaDB vector database client
│   ├── processors.py        # yt-dlp, Faster-Whisper, Gemini AI engines
│   ├── state.py             # In-memory / Redis task operation state manager
│   ├── utils.py             # Chunking, text cleaning, temp file lifecycle
│   ├── serendipity.py       # Random note surfacing algorithms
│   ├── synthesis_loop.py    # Automated weekly topic clustering & synthesis
│   └── retroactive_backlink.py # Wiki backlink scanning & injection
├── src/                     # React 19 Web Dashboard
│   ├── hooks/               # Custom domain state hooks (useNotes, useChat, useIngest)
│   ├── services/            # Pure typed API clients (notesApi, ingestApi, chatApi)
│   ├── components/layout/   # Layout components (VaultSidebar, NoteViewer, ChatPanel)
│   └── types/               # TypeScript interface contracts
└── flutter_client/          # Cross-platform Flutter capture application
```
