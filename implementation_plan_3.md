```markdown
# Phase 3: Advanced Task Automation & Active Serendipity Integration Plan

This plan details the design and implementation specifications for adding four advanced automation pipelines to the Cortex Second Brain system. These features eliminate manual overhead in scheduling, task management, spaced repetition, and historical graph densification, transitioning the system from a passive repository to an active, living assistant.

## User Review Required

> [!IMPORTANT]
> **Core Architectural Decisions:**
> 1. **Webhook Security & Exposure (Todoist):** To achieve two-way task synchronization, Todoist must send webhooks to the Cortex backend when a task is completed. This requires exposing a specific endpoint (`/api/webhooks/todoist`) to the public internet. *Decision:* We will enforce strict HMAC-SHA256 signature validation on the webhook endpoint to ensure only Todoist can trigger vault updates. For local development, an `ngrok` tunnel will be strictly required.
> 2. **Notification Delivery Mechanism:** For "Ambient Serendipity," we must choose between scheduling notifications entirely locally on the device (via `flutter_local_notifications`) vs. server-driven pushes (via Firebase Cloud Messaging). *Decision:* We will use **FCM (Server-Driven)**. This allows the FastAPI backend to leverage the heavy ChromaDB and Gemini LLM logic to intelligently select the *best* notes dynamically, rather than relying on the mobile client's limited local state.
> 3. **Graph Modification Safety:** Modifying *historical* markdown files programmatically (Retroactive Backlinking) carries a severe risk of data corruption or mid-sentence formatting breaks. *Decision:* The retroactive engine will strictly append generated links under a designated `## Related Vault Insights` header at the end of historical notes, explicitly avoiding fragile inline regex replacements.

## Proposed Changes

```mermaid
graph TD
    subgraph Mobile Client
        FCM[Firebase Messaging] -->|Receives Daily Push| UI[Lock Screen Notification]
        UI -->|Tap| NV[NoteViewerScreen]
        App[App Launch] -->|Sends Token| API_T[POST /api/device_token]
    end
    
    subgraph FastAPI Backend
        Ingest[Ingestion Pipeline] -->|Extracts event_date| Cal[Calendar Sync Engine]
        Cal -->|Google API| GCal[(Google Calendar)]
        
        Ingest -->|Extracts '- [ ] Task'| TS[Task Sync Engine]
        TS -->|Todoist API| Todoist[(Todoist)]
        Todoist -->|Webhook: Item Completed| WH[POST /api/webhooks/todoist]
        WH -->|Regex '- [x]'| Vault[(Markdown Vault)]
        
        Cron[Daily Scheduler] -->|Selects 3 Notes| Ser[Serendipity Engine]
        Ser -->|firebase-admin| FCM
        
        Cron2[Weekly Scheduler] -->|Query ChromaDB| RB[Retroactive Backlinker]
        RB -->|Appends to Old Notes| Vault
    end

```

---

## Component 1: Automated Calendar Sync Pipeline

During standard ingestion, the Gemini AI already extracts temporal data into the `event_date` field. This component automatically blocks time on Google Calendar for these detected events to eliminate manual data entry.

**`[NEW]` `core/calendar_sync.py**`

* **Dependencies:** `google-api-python-client`, `google-auth-httplib2`, `google-auth-oauthlib`.
* **OAuth Management:** Implement `get_credentials()` to read from a local `credentials.json` and generate a scoped `token.json` (`https://www.googleapis.com/auth/calendar.events`).
* **Function `Calendar(title, event_date_str, source_url, description)`:**
* Parse the ISO-8601 `event_date_str`.
* If no explicit end time is provided by the AI, dynamically calculate `end_time = start_time + timedelta(hours=1)`.
* Construct the Google Calendar API payload.
* Format the `description` to include a direct link back to the local note: `\n\n---\nSource Note: {source_url}\n\n{description}`.
* Execute `service.events().insert(calendarId='primary', body=event).execute()`.



**`[MODIFY]` `main.py**`

* Locate `_run_ingestion_logic()` near the `Saving to vaults` phase.
* **Injection Logic:** Check if an `event_date` is present and if the note category is strictly `Event`.

```python
event_date = data.get("ai_data", {}).get("event_date")
if event_date and str(event_date).lower() != "null" and data['ai_data'].get('category') == "Event":
    ops_manager.update_task(task_id, "Syncing to Calendar", progress=90)
    try:
        from core.calendar_sync import create_calendar_event
        create_calendar_event(
            title=f"Event: {data['ai_data'].get('summary', 'New Event')[:50]}",
            event_date_str=event_date,
            source_url=data['url'],
            description=data['ai_data'].get('formatted_content', '')
        )
    except Exception as e:
        print(f"Calendar sync failed: {e}")

```

---

## Component 2: Task Manager (Todoist) Two-Way Sync

Automatically pushes extracted Markdown tasks (`- [ ]`) to Todoist and listens for completion webhooks to destructively update the local Markdown files, ensuring the vault reflects real-world progress.

**`[NEW]` `core/task_sync.py**`

* **Dependencies:** `todoist-api-python`.
* **Function `push_task_to_todoist(task_text, due_date, source_filename)`:**
* Initialize `TodoistAPI(TODOIST_API_KEY)` from `core.config`.
* Create a task. The content should be the `task_text`. The description should contain: `From Cortex Vault: [[{source_filename}]]`.
* If `due_date` is provided, map it to the Todoist `due_string` or `due_date` fields.
* Return the created `task.id`.



**`[MODIFY]` `main.py**`

* **Outbound Sync:** Update the `update_note_tasks(filename, markdown_content)` function.
* When iterating over the regex `r'^\s*-\s*\[\s*\]\s*(.+)$'`, if a new task is found (not present in `_tasks.json`), call `push_task_to_todoist`.
* Save the returned `todoist_task_id` into the `_tasks.json` dictionary alongside the system UUID.


* **Inbound Sync (Webhook Listener):**
* Create a new FastAPI endpoint: `POST /api/webhooks/todoist`.
* **Security:** Compute the HMAC-SHA256 digest of the request body using your Todoist Client Secret and compare it to the `X-Todoist-Hmac-SHA256` header. Reject unauthorized requests.
* Parse the payload for `event_name == "item:completed"`.
* Extract the `event_data.id`.
* Search `_tasks.json` for a matching `todoist_task_id`.
* If found, extract the `filename`. Open the physical `.md` file, perform a highly specific regex substitution targeting the exact `task_text` string, changing `- [ ]` to `- [x]`.
* Save the file and update `_tasks.json` to mark `completed: True`.



---

## Component 3: Ambient Serendipity via Push Notifications

A background synthesis loop that pushes 2-3 unreviewed/randomized notes directly to the user's mobile device daily to enforce spaced repetition and ambient learning.

**`[MODIFY]` `main.py**`

* **Dependencies:** `firebase-admin`.
* **Device Registration:** Add endpoint `POST /api/device_token` that accepts `{ "token": "fcm_string", "device": "android/ios" }` and persists it to `device_tokens.json`.
* **Scheduled Worker:** Create `daily_serendipity_scheduler()`.
* Register an `asyncio` task (or APScheduler job) to run daily at 08:30 AM local time.
* Invoke the internal logic of the existing `/api/serendipity` endpoint to fetch 3 notes optimized for review (prioritizing older, unreviewed items).
* For each note, construct an FCM payload:
```json
{
  "notification": {
    "title": "🧠 Daily Spark: [Note Title]",
    "body": "[1-sentence AI Summary]"
  },
  "data": {
    "route": "/note",
    "fileName": "[relative/path.md]"
  }
}

```


* Dispatch via `firebase_admin.messaging.send_multicast(message)`.



**`[MODIFY]` `flutter_client/lib/main.dart` & `[NEW]` `flutter_client/lib/services/notification_service.dart**`

* **Dependencies:** `firebase_core`, `firebase_messaging`.
* **Initialization:** Request notification permissions (`FirebaseMessaging.instance.requestPermission()`).
* **Token Handling:** Fetch the FCM token and execute a `POST` to `/api/device_token` on application startup.
* **Interaction Routing:** Implement `FirebaseMessaging.onMessageOpenedApp.listen()`. Parse the `data['route']` and `data['fileName']`. Use the Flutter Navigator to push the user directly into `NoteViewerScreen(fileName: ...)`, bypassing the home dashboard.

---

## Component 4: Retroactive Auto-Backlinking Engine

Densifies the knowledge graph by injecting links to *new* concepts into *historical* notes where relevant, ensuring the Second Brain grows interconnectedly over time.

**`[NEW]` `core/retroactive_backlink.py**`

* **Function `run_retroactive_scan()`:**
* Fetch all notes indexed within the last 7 days from `url_index.json`.
* For each *new* note, extract its Title and Summary.
* Query ChromaDB (`vault_collection.query`) for the top 5 most semantically similar chunks from notes **older** than 7 days.
* Pass the *old* note content and the *new* note context to Gemini 2.5 Flash Lite.
* **LLM Prompt Specification:**
```text
You are an AI Librarian maintaining a wiki. We have an existing historical article:
[Insert Historical Content]

We recently added a new concept to our brain: 
Title: "{new_note_title}", Summary: "{new_note_summary}".

Analyze the historical article. Is there a highly relevant conceptual link to this new concept?
If yes, generate a single concise bullet point explaining the connection and including the markdown link [[{new_note_title}]].
If no strong connection exists, output exactly "NONE".

```


* **Safe Injection Markdown Writing:** If a valid bullet point is generated, open the *old* `.md` file. Check if `## Related Vault Insights` exists. If not, append the header to the bottom of the document. Append the generated bullet point beneath it.
* Trigger a ChromaDB deletion and re-insertion for the modified historical note to keep the vector embeddings perfectly synced with the file system.



**`[MODIFY]` `main.py**`

* Add a new endpoint `POST /api/maintenance/backlink` to trigger this scan manually from the frontend System Dashboard.
* Add `retroactive_backlink_scheduler()` to run once weekly (e.g., Sunday at 02:00 AM) alongside the existing weekly synthesis loop.

---

## Verification Plan

### Calendar Sync Verification

1. Run a test script attempting to ingest a raw text note: *"Dinner with Sarah at 8pm on May 25th 2026 at the new Italian place."*
2. Verify the FastAPI logs show the AI assigning `category: Event` and `event_date: 2026-05-25T20:00:00Z`.
3. Check the target Google Calendar to confirm the 1-hour time block was successfully created and the description contains a clickable `Source Note: local://...` link.

### Todoist Sync & Webhook Verification

1. Ingest a generic note containing the markdown: `- [ ] Finalize Q3 roadmap by Friday`.
2. Verify the task instantly appears in the Todoist Inbox via the Todoist UI.
3. Expose the local backend using `ngrok` and register the webhook URL in the Todoist App Console. Check off the task in Todoist.
4. Verify the FastAPI logs receive the `item:completed` webhook, validate the HMAC signature, and verify the local markdown file updates exactly to `- [x] Finalize Q3 roadmap by Friday` without altering surrounding text.

### Serendipity Push Notification Verification

1. Build and deploy the Flutter app to a physical Android/iOS device. Confirm `device_tokens.json` is successfully populated on the backend.
2. Hit the internal `daily_serendipity_scheduler()` function manually via a temporary debug endpoint.
3. Verify the native OS notification appears on the device lock screen. Tap the notification and ensure the navigation stack pushes directly to the `NoteViewerScreen` for the intended note.

### Retroactive Backlinking Verification

1. Create a dummy historical note named `Machine Learning Basics.md`.
2. Ingest a new note named `Large Language Models.md`.
3. Trigger `POST /api/maintenance/backlink`.
4. Open `Machine Learning Basics.md` in the vault and verify that `## Related Vault Insights` has been appended securely at the bottom, containing a rationale and a backlink to `[[Large Language Models]]`. Verify ChromaDB reflects this new text.

```

```