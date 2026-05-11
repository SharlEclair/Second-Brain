# Cortex Change Log

## 2026-05-11 - Ingestion Reliability, Status Visibility, and Gemini Fallbacks

### Backend ingestion
- Persisted raw video transcripts in generated Markdown notes under `## Raw Transcript`.
- Added `transcript_status` metadata to saved notes and `url_index.json` entries.
- Added transcript text and captions to ChromaDB indexing so RAG can retrieve the source transcript, not only Gemini's formatted summary.
- Added download diagnostics to operation state, including media size and transcript character count where available.
- Made audio/video download discovery more robust by using a temporary filename prefix and locating the actual downloaded media file instead of assuming a fixed `.m4a` path.
- Added empty-transcript handling. If no speech is detected, the note records that state instead of silently omitting transcript information.
- Added collision-safe filenames so repeated ingests from the same creator/category no longer overwrite earlier notes.

### Operation status
- Expanded backend operation tracking from active-only tasks to active tasks plus recent task history.
- Added task fields: `task_id`, `platform`, `state`, `progress`, `updated_at`, `finished_at`, and `error`.
- Updated `/api/status` to return `active_tasks`, `recent_tasks`, and `task_count`.
- Added stage-level progress updates across index checking, download, hashing, transcription, AI analysis, vault saving, and vector indexing.
- Failed ingests now remain visible in recent task history after the active task is removed.

### Instagram carousel handling
- Reworked Instagram post ingestion to try `yt-dlp` first and fall back to Instaloader.
- Added clearer Instagram failure messages that mention stale/missing `cookies.txt` when metadata or media fetches fail.
- Added carousel media collection for images and videos.
- Added transcription for video items inside Instagram carousels.
- Changed carousel duplicate detection from first-image MD5 to a composite MD5 over all downloaded media files.

### Gemini model handling
- Set the primary model to `models/gemini-2.5-flash-lite`.
- Added `models/gemini-2.5-flash` as the fallback model.
- Centralized Gemini calls behind a retry/fallback helper used by ingestion, RAG chat, note summary, and deep dive actions.
- Added retry handling for busy/server-side failures such as 429, 5xx, timeout, unavailable, overloaded, and resource exhaustion responses.
- Added JSON parsing recovery for Gemini responses with invalid control characters, with a preserved-source fallback note when formatting fails.
- `/api/config` now exposes the primary model, fallback model, and full model chain.

### Web UI
- Added global operation polling in the React app so the header can show active ingestion started from either web or mobile.
- Added a compact active/failed operation indicator with stage and progress.
- Updated Mission Control to show recent completed or failed operations, not only currently active tasks.
- Fixed the "Sync Vault" button to call the sync endpoint instead of only toggling spinner state.

### Flutter mobile app
- Increased ingestion timeout from 3 minutes to 15 minutes for long-running media processing.
- Added URL-specific status polling so the mobile app follows the task for the URL being ingested instead of guessing the last task.
- Added progress percentages to the mobile ingest button where the backend provides them.
- Added status polling for Android share-intent ingestions, surfacing backend stages through snackbars while processing.
- Added a timeout to `/api/status` polling to prevent status checks from hanging on poor networks.

### Configuration and maintenance
- `PROJECT_VAULT_PATH` now respects the environment variable and falls back to `vault`.
- Documentation updated to describe transcript persistence, task history, Instagram cookie/fallback behavior, and Gemini model fallback.
