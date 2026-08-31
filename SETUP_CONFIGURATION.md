# 🛠️ Cortex: Setup & Configuration Guide

This guide details how to configure, run, and maintain the Cortex Second Brain system on your local machine.

---

## 🔑 Environment Variables (`.env`)

Cortex ships with a safe template in [`.env.example`](file:///c:/Users/91704/Desktop/Second-Brain/.env.example). Create your local configuration file by copying it:

```powershell
cp .env.example .env
```

Open `.env` and configure the following variables:

```ini
# ── Required ──────────────────────────────────────────────────────────────────
# Get your Gemini API key from: https://aistudio.google.com/app/apikey
GEMINI_API_KEY="your_gemini_api_key_here"

# ── Vault Paths ────────────────────────────────────────────────────────────────
# Path to your Obsidian Vault's inbox directory
OBSIDIAN_INBOX_PATH="C:/Users/YourUsername/Documents/Obsidian Vault/Inbox"

# Path to the Second-Brain project vault directory (defaults to ./vault)
PROJECT_VAULT_PATH="./vault"

# ── Celery Task Queue ──────────────────────────────────────────────────────────
# Redis connection URL for Celery background workers
REDIS_URL="redis://localhost:6379/0"

# ── Ngrok Tunnel (Remote Mobile & Web Access) ──────────────────────────────────
# Your personal Ngrok authtoken (from https://dashboard.ngrok.com/get-started/your-authtoken)
NGROK_AUTHTOKEN="your_ngrok_authtoken_here"

# ── Optional Integrations ──────────────────────────────────────────────────────
# Google Maps geocoding API key (for spot coordinates extraction)
GOOGLE_MAPS_API_KEY="your_maps_api_key"

# Todoist client secret for webhook signature verification
TODOIST_CLIENT_SECRET="your_todoist_secret"
```

---

## 🌐 Ngrok Tunnel Integration

Cortex includes native support for exposing your local FastAPI server over a secure, public HTTPS tunnel using **Ngrok**.

### How It Works:
1. When `python run_services.py` runs, it loads `NGROK_AUTHTOKEN` from your `.env` file.
2. The orchestrator injects this token into the subprocess environment and executes `npx ngrok` using [`ngrok.yml`](file:///c:/Users/91704/Desktop/Second-Brain/ngrok.yml).
3. `ngrok.yml` automatically interpolates `${NGROK_AUTHTOKEN}` without requiring hardcoded secrets:
   ```yaml
   version: 3
   agent:
     authtoken: ${NGROK_AUTHTOKEN}
   ```
4. Ngrok creates a secure tunnel forwarding to `http://127.0.0.1:8000`. You can paste the resulting public URL into your Flutter mobile client to capture notes from anywhere.

---

## 🚀 Running the System

### Automated Orchestration (`python run_services.py`)

The simplest and recommended way to start Cortex is using the unified service orchestrator:

```powershell
python run_services.py
```

This orchestrator automatically:
1. **Validates Redis**: Checks if the `redis` Docker container is running; if not, starts or creates a new `redis:7-alpine` container on port `6379`.
2. **Kills Zombie Processes**: Cleans up orphan ports (`8000`, `5173`, `5174`) and background processes.
3. **Launches Frontend**: Starts the Vite React dashboard on `http://localhost:5173`.
4. **Launches Backend**: Starts the FastAPI engine on `http://127.0.0.1:8000`.
5. **Launches Ngrok**: Establishes the secure public tunnel.
6. **Launches Celery**: Starts the background worker and periodic beat scheduler.

Press `Ctrl+C` in the terminal to cleanly terminate all services simultaneously.

---

### Manual Service Execution (Optional)

If you prefer to run services in separate terminals:

**Terminal 1 (Backend API):**
```powershell
.\venv\Scripts\activate
python main.py
```

**Terminal 2 (Frontend Web):**
```powershell
npm run dev
```

**Terminal 3 (Celery Worker):**
```powershell
.\venv\Scripts\activate
celery -A api.celery_app.celery_app worker --loglevel=info -P solo
```

**Terminal 4 (Celery Beat):**
```powershell
.\venv\Scripts\activate
celery -A api.celery_app.celery_app beat --loglevel=info
```

**Terminal 5 (Ngrok Tunnel):**
```powershell
npx ngrok http 8000 --config=ngrok.yml
```

---

## 📱 Mobile Client Setup (Flutter)

To run the capture app on your Android or iOS device:

```powershell
cd flutter_client
flutter pub get
flutter run
```

In the app's settings screen:
1. Set the **Backend URL** to your local network address (e.g. `http://192.168.1.50:8000`) or your public **Ngrok HTTPS URL**.
2. Tap "Test Connection" to confirm communication.
