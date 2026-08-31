# 🖥️ Cortex: Frontend Architecture & Client Exploration

Cortex provides two intuitive, high-performance interfaces: a **React 19 Web Dashboard** for in-depth knowledge synthesis and a **Flutter Client** for cross-platform capture.

---

## 🕸️ React 19 Web Dashboard

The Web Dashboard has been re-architected from a 1,188-line monolith into a modular, hook-driven architecture where presentation components remain pure and state is decoupled into domain hooks.

```
src/
├── App.tsx                      # Declarative Root Orchestrator (~205 lines)
├── types/                       # Centralized TypeScript Contracts (index.ts)
├── services/                    # Typed API Client Layer (api.ts)
├── hooks/                       # Custom Domain State Hooks
│   ├── useNotes.ts              # Note selection, action execution, and search
│   ├── useChat.ts               # RAG conversational stream and active note context
│   ├── useIngest.ts             # URL SSE streaming, drag-and-drop, and voice recording
│   └── useSystemStatus.ts       # Real-time task queue polling, sync, and theme toggle
└── components/
    ├── layout/                  # Core Layout Presentation Components
    │   ├── VaultSidebar.tsx     # Stored knowledge explorer, search, and node sync status
    │   ├── IngestionHeader.tsx  # Omni-ingestion input bar, upload/voice buttons, toast alerts
    │   ├── NoteViewer.tsx       # Markdown reader, action toolbar, task appender, frontmatter tags
    │   ├── EmptyWorkspace.tsx   # 2D Knowledge Graph, 4-column widget grid, activity heatmap
    │   ├── ChatPanel.tsx        # Collapsible RAG terminal with active note context focus
    │   └── ActiveQueueOverlay.tsx # Floating real-time background task progress cards
    ├── SystemDashboard.tsx      # Mission Control operations monitor & log viewer
    ├── VaultGraph.tsx           # Interactive 2D Force-Directed Knowledge Graph
    ├── ActivityHeatmap.tsx      # Contribution & knowledge capture activity grid
    ├── SerendipityWidget.tsx    # Spaced-repetition knowledge resurfacing
    ├── EventsWidget.tsx         # Upcoming event deadlines widget
    ├── SuggestionsWidget.tsx    # Random contextual note recommendations
    ├── InboxCompileWidget.tsx   # Raw clippings batch compiler
    └── LibraryDirectory.tsx     # Categorical folder tree browser
```

---

## 🎣 Custom Domain Hooks

| Hook | Responsibilities | Key Functions & State |
| :--- | :--- | :--- |
| **`useNotes`** | Manages note browsing, note viewing, and AI-assisted note actions. | `notes`, `selectedNote`, `noteContent`, `searchQuery`, `fetchNotes()`, `handleSelectNote()`, `handleAction('summarize' \| 'deep_dive' \| 'extract_tasks')`, `handleSaveTasks()`. |
| **`useChat`** | Manages RAG conversation state, session history, and Wiki promotion. | `messages`, `chatInput`, `currentSessionId`, `isTyping`, `isChatMinimized`, `useActiveNoteContext`, `handleChat()`, `loadChatSession()`, `handlePromoteToWiki()`. |
| **`useIngest`** | Manages multi-modal ingestion (SSE streams, file uploads, voice notes, drag-and-drop, global paste). | `url`, `loadingNote`, `ingestStatus`, `error`, `success`, `isDragging`, `isRecording`, `handleIngest()`, `uploadFileObj()`, `toggleRecording()`. |
| **`useSystemStatus`** | Polls real-time Celery task queues, controls vault sync, and persists theme preferences. | `activeTasks`, `recentTasks`, `activeModel`, `isSyncing`, `showDashboard`, `theme`, `toggleTheme()`, `handleSync()`. |

---

## 📱 Cross-Platform Flutter Client (`flutter_client/`)

The mobile and desktop client, named **Cortex**, provides unified knowledge capture across **Android, iOS, Windows, macOS, Linux, and Web**.

### 📥 Native "Share to Ingest" Workflow
1. **Discover**: Ingest content from native social media apps (YouTube, Instagram, TikTok, Twitter/X) by tapping the OS **Share** button.
2. **Select Cortex**: Choose the "Cortex" app from the native share sheet.
3. **Auto-Process**: The app extracts the URL, submits it to the background Celery queue via `POST /api/ingest` with `X-Queue: true`, and surfaces real-time progress notifications.

### Key Mobile Capabilities:
- **Offline Ingestion Queue**: When disconnected from your home network, links and clippings are saved to an encrypted local queue and synced automatically upon reconnection.
- **Proactive Geofencing**: Automatically notifies you when you are physically near a venue or restaurant saved in your "Spot to Visit" notes.
- **Mobile RAG Terminal**: Full conversational chat interface to research your knowledge vault on mobile.
- **Analytics & Mission Control**: Mobile dashboard tracking ingestion velocity, category distributions, and backend service health.
