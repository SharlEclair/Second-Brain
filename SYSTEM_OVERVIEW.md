# 🧠 Cortex: System Overview

Cortex is a production-ready "Second Brain" system designed to capture, process, and query high-signal content from social media and the web. It transforms fleeting digital consumption into a permanent, searchable knowledge vault.

## 🏛️ Architecture at a Glance

The system is built on a "Secure Node" architecture:
- **Backend (Python/FastAPI)**: The engine. Handles media acquisition, transcription, AI analysis, and vector storage.
- **Web Dashboard (React/Vite)**: The "Mission Control." Used for managing the vault, viewing logs, and deep AI querying.
- **Mobile App (Flutter)**: The "Capture Device." Native Android integration for "Share to Ingest" workflows and mobile chat.
- **Storage Layer (Obsidian/Markdown)**: The "Vault." All notes are saved as local Markdown files for long-term data sovereignty.

## 🔄 The Knowledge Cycle

1. **Ingest**: A user shares a URL (YouTube, TikTok, Instagram) via the Mobile App or Web Dashboard.
2. **Download & Fingerprint**: The backend downloads the media and generates an **MD5 content hash**. If the hash already exists, the system skips ingestion to prevent duplicates.
3. **Transcription**: Audio is extracted and transcribed using the **Whisper** model (optimized via `float16` for speed).
4. **AI Synthesis**: The transcript and metadata are sent to **Gemini 2.5 Flash Lite**. It categorizes the content (Recipe, Event, Job, etc.) and generates a formatted Markdown note.
5. **Indexing**: 
    - **Physical**: A `.md` file is written to the Obsidian vault.
    - **Vector**: Content is chunked and stored in **ChromaDB** for Retrieval-Augmented Generation (RAG).
6. **Query**: The user asks questions in the Chat UI. The system retrieves relevant note chunks (RAG) and provides a synthesized answer.

## 🛠️ Core Technologies
- **AI**: Google Gemini 2.5 Flash Lite
- **Transcription**: Faster-Whisper (`large-v3-turbo`)
- **Database**: ChromaDB (Vector) + Local JSON (Index)
- **Frameworks**: FastAPI (Backend), React (Web), Flutter (Mobile)
- **Tools**: yt-dlp (Acquisition), Instaloader (Instagram), Obsidian (Organization)
