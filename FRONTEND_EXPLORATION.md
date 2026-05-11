# 🖥️ Cortex: Frontend Exploration

Cortex provides two distinct interfaces for interacting with your knowledge: a high-power Web Dashboard for management and a streamlined Mobile App for capture.

## 🕸️ Web Dashboard (React/Vite)

The Web Dashboard is the "Mission Control" for your Second Brain.

### Key Features:
- **Vault Explorer**: A searchable sidebar that lists every note in your vault. Search is performed locally on titles for O(1) responsiveness.
- **Note Viewer**: A high-fidelity Markdown renderer (via `react-markdown`) with support for custom styling (Georgia font for readability).
- **Mission Control**: A specialized view for system health:
    - **Active Operations**: See exactly what the backend is doing (Downloading, Transcribing, Analyzing).
    - **Error Logs**: View and clear critical system errors with one-click retry functionality.
- **Ingestion Bar**: A prominent, mono-spaced input field for pasting URLs. It features a "Glow" effect when active and shows live status breadcrumbs.
- **Secure Node Sync**: A status indicator showing your vault is synced and the AI model is online.

---

## 📱 Mobile App (Flutter)

The mobile app, named **Cortex**, is optimized for "On-the-Go" knowledge capture.

### 📥 "Share to Ingest" Workflow
The most powerful feature of the mobile app is its native Android integration:
1. **Discover**: You see a Reel or post you like in another app (Instagram, YouTube).
2. **Share**: Tap the system "Share" button.
3. **Select Cortex**: Choose the "Cortex" app from the share sheet.
4. **Auto-Process**: The app automatically extracts the URL, sends it to the backend, and shows a "✓ Successfully Ingested" notification—all without you needing to copy/paste.

### Key Features:
- **Dynamic Status Polling**: The "INGEST" button and "PROCESS ALL" queue buttons change text in real-time (e.g., "TRANSCRIBING...") based on the backend status.
- **Queue Management**: If the server is unreachable (e.g., you're offline), links are saved to a local **Offline Queue**. You can batch-process them later with one tap.
- **Debug Logs**: A hidden "Developer" view allows you to see raw Network and Error logs directly on the phone for troubleshooting.
- **RAG Chat**: A full chat interface for talking to your brain while away from your desk.

## 🎨 Design Language
Both platforms share a consistent "Dark/Tech" aesthetic:
- **Primary Color**: Orange 500 (`#F97316`)
- **Background**: Pure Black (`#050505`) / Panel Gray (`#111111`)
- **Typography**: Inter (UI), JetBrains Mono (Tech), Georgia (Reading)
- **Animations**: Subtle motion via `framer-motion` (Web) and native Flutter transitions (Mobile).

## 2026-05-11 Frontend Changes

### Web Dashboard
- The React app now polls `/api/status` globally, so active ingestion is visible even when started from the Flutter app or Android share sheet.
- The header shows a compact active-operation indicator with stage and progress when ingestion is running.
- Failed recent ingests remain visible as a header warning until a newer status replaces them.
- Mission Control now renders recent completed or failed operations in addition to active tasks.
- The "Sync Vault" button now calls the backend sync endpoint instead of only toggling local spinner state.

### Mobile App
- Manual URL ingestion now tracks the matching backend task by URL and shows the current stage in the INGEST button.
- Progress percentages from the backend are displayed where available.
- Android "Share to Cortex" ingestions now poll `/api/status` while the long-running POST is active and surface stage updates through snackbars.
- The mobile HTTP ingestion timeout was increased to 15 minutes so longer media has time to download, transcribe, analyze, save, and index.
- `/api/status` polling now has its own timeout to avoid hanging the UI on weak networks.
