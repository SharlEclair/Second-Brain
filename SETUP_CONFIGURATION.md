# 🛠️ Cortex: Setup & Configuration

This guide details how to configure, run, and maintain the Cortex system.

## 🔑 Environment Variables (`.env`)
Create a `.env` file in the root directory with the following keys:

```env
# AI Configuration
GEMINI_API_KEY=your_google_ai_key

# Vault Paths
OBSIDIAN_INBOX_PATH=C:/path/to/Obsidian/Vault/Inbox
PROJECT_VAULT_PATH=C:/path/to/Second-Brain/vault
```

## 📂 Directory Structure

```text
/
├── main.py              # FastAPI Entry Point
├── core/                # Backend Modules
│   ├── config.py        # Centralized Settings
│   ├── processors.py    # Media/AI Engines
│   └── state.py         # Task Management
├── src/                 # React Web App Source
├── flutter_client/      # Mobile App Source
├── vault/               # Local Markdown Storage
├── chroma_db/           # Vector Database Files
├── url_index.json       # Metadata & MD5 Hashing Index
└── error_log.json       # System Error History
```

## 🏃 Running the System

The project is managed via a root `package.json` for convenience:

### Start the Backend
```bash
npm run backend
```
*Note: This automatically uses the virtual environment (`./venv/Scripts/python`).*

### Start the Web UI
```bash
npm run dev
```

### Build the Mobile App
```bash
cd flutter_client
flutter build apk --release
```

## 🔧 Maintenance & Ops

### Cloudflare Tunnel
For the mobile app to work outside your local network, use the provided Cloudflare tunnel command:
```bash
npx cloudflared tunnel --url http://127.0.0.1:8000
```
Update the "Backend URL" in the Mobile App settings with your custom `.trycloudflare.com` address.

### Vault Sync
The system includes a built-in Git sync mechanism. Ensure `PROJECT_VAULT_PATH` is a Git repository. Clicking "Sync Vault" on the dashboard will run:
1. `git add .`
2. `git commit -m "Auto-sync"`
3. `git push`

### Temporary Files
Cortex creates temporary audio/image files during ingestion. The system automatically runs `cleanup_temp_files()` on startup, but you can manually delete any files starting with `temp_` if needed.

## 2026-05-11 Configuration Notes

### Gemini Model Chain
The backend now uses a two-model Gemini chain:

```text
Primary:  models/gemini-2.5-flash-lite
Fallback: models/gemini-2.5-flash
```

The fallback is only used after repeated busy or server-side failures from Google, such as rate limiting, temporary unavailability, overload, timeout, or 5xx responses.

### Vault Paths
`PROJECT_VAULT_PATH` is now read from `.env` and falls back to `./vault` when unset. `OBSIDIAN_INBOX_PATH` continues to support both `OBSIDIAN_VAULT_PATH` and `OBSIDIAN_INBOX_PATH` for backwards compatibility.

### Instagram Cookies
Instagram carousel ingestion now tries `yt-dlp` first and Instaloader second. Both can use `cookies.txt` from the project root. If Instagram returns `403 Forbidden`, `Fetching Post metadata failed`, or login-required errors, refresh `cookies.txt` from an authenticated browser session and retry.

### Status Monitoring
Use `GET /api/status` to inspect live and recent operations. The response includes:

```json
{
  "active_tasks": [],
  "recent_tasks": [],
  "task_count": 0
}
```

Tasks include stage, progress, state, timestamps, URL, platform, and error fields. This endpoint powers Mission Control, the web header operation indicator, and mobile ingestion status.
