# 🧠 Cortex Second Brain: Autonomous Knowledge Graph & Hybrid GraphRAG

[![FastAPI](https://img.shields.io/badge/FastAPI-0.100%2B-009688.svg?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![React 19](https://img.shields.io/badge/React-19.0-61DAFB.svg?logo=react&logoColor=black)](https://react.dev)
[![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-02569B.svg?logo=flutter&logoColor=white)](https://flutter.dev)
[![Neo4j](https://img.shields.io/badge/Neo4j-5.0-008CC1.svg?logo=neo4j&logoColor=white)](https://neo4j.com)
[![ChromaDB](https://img.shields.io/badge/ChromaDB-VectorStore-orange.svg)](https://www.trychroma.com)
[![Celery](https://img.shields.io/badge/Celery-Task%20Queue-37814A.svg?logo=celery&logoColor=white)](https://docs.celeryq.dev)
[![Gemini 2.5](https://img.shields.io/badge/Google%20Gemini-2.5%20Flash-4285F4.svg?logo=google&logoColor=white)](https://aistudio.google.com)

**Cortex Second Brain** is an autonomous, self-organizing personal intelligence operating system. It ingests unstructured multi-modal content (social media URLs, YouTube videos, PDFs, images, voice notes, and text clippings) and synthesizes them into an interconnected, bidirectional Markdown vault powered by **Hybrid GraphRAG (Neo4j Graph Database + ChromaDB Vector Store + Google Gemini 2.5)**.

---

## 🌟 Core Architectural Features

### 1. 🕸️ Hybrid GraphRAG Engine
- **Dual Retrieval Pipeline**: Combines dense vector similarity search (ChromaDB `vault_embeddings`) with graph relationship traversal (Neo4j 1–2 hop subgraph traversal).
- **Automated Knowledge Graph Extraction**: During ingestion, Gemini extracts domain entities (Frameworks, Concepts, Languages, Tools, People) and semantic relations (`WRITTEN_IN`, `USES`, `INTEGRATES_WITH`) into Neo4j.
- **Relational Context Synthesis**: `/api/chat` grounds its answers in both contextual text chunks and graph relationship statements with Obsidian-style wiki links (`[[Concept Name]]`).

### 2. 🤖 Autonomous Nightly Librarian
- **Nightly Synthesizer (02:00 AM UTC)**: Scans the vault, finds semantically similar notes via ChromaDB, and appends a safe **Semantic Footer** (`## Related Notes` & `## Suggested Links`).
- **Tag Merging & Dynamic Maps of Content (02:30 AM UTC)**: Uses Gemini to cluster synonyms, sub-topics, and duplicate tags into standardized umbrella categories, updating note frontmatters and generating dynamic **Maps of Content (MOCs)** in `vault/Maps/<Category>_Index.md`.
- **Weekly Synthesis & Serendipity Loops**: Proactive automated weekly briefing digests and spaced-repetition knowledge resurfacing.

### 3. 📥 Omni-Channel Ingestion
- **Desktop Dropzone Daemon (`scripts/desktop_dropzone.py`)**: Watches `~/Desktop/CortexDrop` using `watchdog`. Files dragged into the folder (PDFs, Markdown, Images, Audio) are automatically uploaded to `POST /api/ingest/file` and archived into `Processed/`.
- **PDF & Document Processing**: Fast, resilient text extraction via `pypdf` (with `pymupdf` fallback).
- **Audio & Video Processing**: Local Whisper transcription (`faster-whisper` `large-v3-turbo` with `int8`/`float16` acceleration).
- **Vision Ingestion**: Gemini 2.5 Flash visual reasoning for image carousels and infographic extractions.
- **Social Media Support**: URL ingestion for Instagram Reels & Carousels, YouTube Videos & Shorts, TikTok, and Web articles.

### 4. 📱 Cross-Platform Clients
- **React 19 Web Dashboard**: Modern responsive UI with 2D Force-Directed Graph visualization, real-time ingestion status overlays, and RAG chat.
- **Flutter Mobile & Desktop App**: Native application for Android, iOS, Windows, macOS, Linux, and Web with system Share Sheet integration for one-tap URL ingestion outside local networks via Ngrok.

### 5. 🔒 Private Vault Architecture & Git Isolation
- **Repository Isolation**: The `vault/` directory is an isolated Git repository separate from the parent codebase, guaranteeing private notes never leak into the main codebase repo.
- **Automated Cloud Backup**: `POST /api/sync` runs automated `git commit` and `git push` on the private vault repository.

---

## 🏗️ System Architecture

```
                               ┌──────────────────────────────────────────────┐
                               │             Capture Frontends                │
                               │  React 19 Web  •  Flutter Mobile  • Dropzone │
                               └──────────────────────┬───────────────────────┘
                                                      │
                                                      ▼
                                       ┌──────────────────────────────┐
                                       │    FastAPI Gateway (:8000)   │
                                       │        (api/routes/*)        │
                                       └──────────────┬───────────────┘
                                                      │
                                  ┌───────────────────┴───────────────────┐
                                  │ (Sync SSE / POST)                     │ (Async X-Queue)
                                  ▼                                       ▼
                       ┌────────────────────┐                   ┌───────────────────┐
                       │   api/services/    │                   │   Redis Broker    │
                       │   ingestion.py     │                   │    (port 6379)    │
                       │     chat.py        │                   └─────────┬─────────┘
                       └──────────┬─────────┘                             │
                                  │                                       ▼
                                  │                             ┌───────────────────┐
                                  │                             │   Celery Worker   │
                                  │                             │  (api/tasks.py)   │
                                  │                             └─────────┬─────────┘
                                  ▼                                       ▼
             ┌─────────────────────────────────────────────────────────────────────────────┐
             │                                core/ Engine                                 │
             │     processors.py  •  graph_rag.py  •  synthesis.py  •  taxonomy.py         │
             └──────┬───────────────────────┬──────────────────────────────┬───────────────┘
                    │                       │                              │
                    ▼                       ▼                              ▼
         ┌─────────────────────┐ ┌──────────────────────┐ ┌────────────────────────────────┐
         │  ChromaDB (Vector)  │ │   Neo4j (Graph DB)   │ │      Private Git Vault         │
         │  vault_embeddings   │ │  Entity & Note Graph │ │  Markdown Notes + MOC Indexes  │
         └─────────────────────┘ └──────────────────────┘ └────────────────────────────────┘
```

---

## ⚡ Tech Stack

| Component | Technologies |
| :--- | :--- |
| **Backend API** | FastAPI, Uvicorn, Python 3.10+, Pydantic v2 |
| **Task Orchestration** | Celery 5.x, Redis 7.x, Celery Beat |
| **Graph Database** | Neo4j 5.x Community (Bolt `:7687`, Browser `:7474`) |
| **Vector Database** | ChromaDB (Local Persistent Vector Index) |
| **AI Models** | Google Gemini 2.5 Flash Lite (Primary), Gemini 2.5 Flash (Fallback), Faster-Whisper |
| **Web Frontend** | React 19, Vite, Lucide Icons, HTML5 Canvas 2D Graph |
| **Mobile App** | Flutter (Dart), WorkManager, HomeWidget, Cupertino |
| **Desktop Daemon** | Python `watchdog`, `pypdf`, `requests` |
| **Infrastructure** | Docker Compose (`cortex-redis`, `cortex-neo4j`), Ngrok Tunnel |

---

## 🚀 Quick Start Guide

### Prerequisites
- **Python 3.10+**
- **Node.js 18+** & **npm**
- **Docker Desktop** (for Redis & Neo4j orchestration)
- **FFmpeg** (installed and added to system `PATH` for media transcription)

---

### Step 1: Clone Repository & Setup Environment

```bash
# Clone repository
git clone https://github.com/SharlEclair/Second-Brain.git
cd Second-Brain

# Create virtual environment
python -m venv venv
.\venv\Scripts\activate      # Windows
source venv/bin/activate       # macOS / Linux

# Install dependencies
pip install -r requirements.txt
npm install
```

---

### Step 2: Configure Environment Variables

Copy `.env.example` to `.env`:
```bash
cp .env.example .env
```

Edit `.env` with your API keys:
```ini
# Required: Google AI Studio Gemini API Key
GEMINI_API_KEY="your_gemini_api_key_here"

# Vault Paths
PROJECT_VAULT_PATH="./vault"
OBSIDIAN_INBOX_PATH="C:/Path/To/Your/Obsidian/Vault/Inbox"

# Infrastructure URLs
REDIS_URL="redis://localhost:6379/0"
NEO4J_URI="bolt://localhost:7687"
NEO4J_USER="neo4j"
NEO4J_PASSWORD="cortexpassword123"

# Optional: Ngrok Authtoken for mobile access
NGROK_AUTHTOKEN="your_ngrok_token_here"
```

---

### Step 3: Run Full Stack Orchestrator

Start all services simultaneously with the unified runner:
```bash
python run_services.py
```

`run_services.py` automatically:
1. Boots **Redis** and **Neo4j** containers via `docker compose up -d`.
2. Starts the **FastAPI Backend** on `http://localhost:8000`.
3. Starts the **Vite React Frontend** on `http://localhost:5173`.
4. Starts the **Celery Worker** and **Celery Beat** scheduler.
5. Launches the **Ngrok Secure Tunnel** for remote access.

---

### Step 4: Run Desktop Dropzone Daemon (Optional)

In a separate terminal, launch the folder watcher:
```bash
python scripts/desktop_dropzone.py
```
- Drag and drop any **PDF**, **Markdown**, **Text**, **Image**, or **Audio** file into `~/Desktop/CortexDrop`.
- The daemon automatically uploads the file to `POST /api/ingest/file` and moves it to `~/Desktop/CortexDrop/Processed/`.

---

## 🧪 Testing

Execute the comprehensive automated test suite:
```bash
python -m pytest api/tests/ -v
```

**Test Suite Coverage (25 Unit Tests):**
- Ingestion API & Queuing (`test_routes.py`, `test_dropzone_and_file_ingest.py`)
- Nightly Synthesizer & Footers (`test_synthesis.py`)
- Tag Clustering & Maps of Content (`test_taxonomy.py`)
- Knowledge Graph Extraction, Neo4j Upsertion & Hybrid Chat (`test_graph_rag.py`)

---

## 📁 Repository Structure

```
Second-Brain/
├── api/
│   ├── routes/             # FastAPI modular endpoints (chat, ingest, notes, system)
│   ├── services/           # Business logic (chat, ingestion, vault)
│   ├── tests/              # Pytest unit & integration test suites
│   ├── celery_app.py       # Celery configuration & beat schedule
│   └── tasks.py            # Celery background tasks
├── core/
│   ├── config.py           # Centralized configuration & environment loader
│   ├── db.py               # ChromaDB singleton
│   ├── graph_db.py         # Neo4j driver singleton & schema constraints
│   ├── graph_rag.py        # Knowledge Graph extraction, upsert & traversal
│   ├── processors.py       # Multi-modal media & file processors
│   ├── synthesis.py        # Semantic footers & unlinked mentions engine
│   ├── taxonomy.py         # Tag clustering & Maps of Content generator
│   └── state.py            # Operations manager & task status tracker
├── flutter_client/         # Cross-platform Flutter mobile/desktop app
├── scripts/
│   └── desktop_dropzone.py # Local folder watcher daemon
├── src/                    # React 19 + Vite Web application
├── docker-compose.yml      # Redis & Neo4j orchestration
├── run_services.py         # Unified multi-service runner
└── requirements.txt        # Python backend dependencies
```

---

## 📜 License
MIT License. Built with ❤️ for intelligent personal knowledge management.
