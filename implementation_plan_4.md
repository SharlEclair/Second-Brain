# 🧠 Cortex: Mobile Expansion & Automation Plan

This document outlines the strategic implementation phases (Phases 4, 5, and 6) to transform the Cortex Flutter app from a simple dashboard into a highly proactive, offline-capable, and frictionless extension of your Second Brain.

---

## `implementation_plan_phase_4.md`
# Phase 4: Frictionless Capture & Edge Input

**Objective:** Eliminate the friction of opening the app to save information. This phase focuses on native OS integrations to funnel data into the FastAPI backend as seamlessly as possible.

### Component 1: Native Share Sheet Extension
Allow users to share URLs and text directly from other apps (Safari, Chrome, Twitter, YouTube) straight to Cortex without opening the app.

* **Dependencies:** `receive_sharing_intent` (Flutter package).
* **iOS Implementation:** * Create a Share Extension target in Xcode (`ios/Runner.xcodeproj`).
    * Modify `Info.plist` to accept URLs and plain text.
    * Use App Groups to pass the shared string to the main Flutter app.
* **Android Implementation:** * Modify `android/app/src/main/AndroidManifest.xml` to include `<intent-filter>` for `android.intent.action.SEND` with `mimeType="text/plain"`.
* **Flutter Logic (`lib/services/share_service.dart`):**
    * Listen to the incoming intent stream.
    * Upon receiving a URL or text payload, immediately invoke a background headless task.
    * Call `ApiService().ingestUrl(url)` or `ApiService().ingestRawText(text)`.
    * Trigger a local notification: *"Cortex: Ingested to Second Brain."*

### Component 2: "Brain Dump" Voice Memos
A single-tap audio recording feature that streams voice data to the backend's existing Whisper transcription pipeline.

* **Dependencies:** `record` (for audio recording), `path_provider`.
* **Flutter UI (`lib/widgets/brain_dump_button.dart`):**
    * Add a prominent, floating "Mic" button on the home screen.
    * Press-and-hold or Tap-to-toggle to record a high-quality `.m4a` or `.wav` file.
* **Integration (`lib/services/audio_ingest_service.dart`):**
    * On stop, save the file locally.
    * Construct a `MultipartRequest` and push the audio file to the existing backend endpoint `POST /api/upload`.
    * The backend's existing `process_audio_file` will transcribe it via Whisper, summarize it via Gemini, and drop it into the vault.

### Component 3: Smart Clipboard Polling
Detect copied links and prompt the user to save them instantly upon app launch.

* **Dependencies:** Flutter native `Clipboard` API.
* **Lifecycle Observer (`lib/main.dart`):**
    * Implement `WidgetsBindingObserver` to detect when the app transitions to `AppLifecycleState.resumed`.
    * Read the clipboard. Check if it matches a URL regex.
    * Cross-reference with a lightweight local cache or query the backend briefly to check if it's already in `url_index.json`.
    * If new, show a non-intrusive `SnackBar` or `BottomSheet`: *"Copied link detected. Save to Cortex?"* with an "Ingest" button.

### Phase 4 Verification Plan
1.  **Share Sheet:** Open YouTube, tap Share -> Cortex. Verify the backend logs show the ingestion process starting without opening the Cortex UI.
2.  **Brain Dump:** Record a 15-second audio clip saying "Remember to buy milk." Verify the backend receives the file, transcribes it, and saves a formatted note.
3.  **Clipboard:** Copy a random Wikipedia URL, open the app, and verify the bottom sheet prompts for ingestion.

---

## `implementation_plan_phase_5.md`
# Phase 5: Interactive Widgets & Contextual Awareness

**Objective:** Move information out of the app and onto the OS home screen and lock screen, creating ambient serendipity and spatial awareness.

### Component 1: Android/iOS Native Home Screen Widgets
Utilize the placeholder XML files (e.g., `thought_spark_widget_info.xml`) to build fully functional OS widgets.

* **Dependencies:** `home_widget` (Flutter package).
* **Backend Support:** Create a lightweight `GET /api/widgets/sync` endpoint that returns pre-formatted strings for the widgets (1 Serendipity note, 3 Focus tasks).
* **App Group Sync (`lib/services/widget_service.dart`):**
    * Use `Workmanager` to schedule a background fetch every 6 hours.
    * Save the fetched data to native `SharedPreferences` (Android) and `AppGroups/UserDefaults` (iOS) using `home_widget.saveWidgetData()`.
* **Native UI Construction:**
    * **Android:** Update `ThoughtSparkWidgetProvider.kt` and `FocusMissionWidgetProvider.kt` to bind the saved `SharedPreferences` strings to the `RemoteViews` (the XML layouts).
    * **iOS:** Create a WidgetKit Extension in Swift. Build SwiftUI views that read from the `UserDefaults` AppGroup.
* **Interactivity:** Ensure clicking the widget writes a specific URI (e.g., `cortex://note/filename.md`), which the Flutter app intercepts to open the exact note.

### Component 2: "Quick Ask" RAG Overlay
A fast-access search widget that bypasses the main app UI.

* **Implementation:** * Create a 1x4 Search Bar widget for the home screen.
    * Tapping it fires an intent that opens a transparent Flutter Activity/ViewController containing only a Chat input field and response bubble.
    * This queries the existing `POST /api/chat` RAG endpoint directly, providing immediate answers without loading the full dashboard.

### Component 3: Geofenced "Spot to Visit" Reminders
Trigger local alerts when physically near a saved recommendation.

* **Dependencies:** `flutter_background_geolocation` or `geofence_service`.
* **Backend Update (`main.py`):**
    * Update the `SYSTEM_PROMPT` to extract latitude/longitude coordinates (via standard geocoding) when it categorizes a note as `Spot to Visit`.
* **Mobile Background Worker:**
    * Sync a list of `Spot to Visit` coordinates to the mobile device.
    * Register geofences (e.g., 500-meter radius) with the OS.
    * When the OS wakes the app due to a geofence breach, trigger a local notification: *"Cortex: You are near [Spot Name]. Check out your saved note!"*

### Phase 5 Verification Plan
1.  **Widgets:** Add the "Thought Spark" widget to the home screen. Force a background sync and verify the text updates. Tap it and ensure it deep-links to the Note Viewer.
2.  **Geofencing:** Manually inject the GPS coordinates of your current location into a "Spot to Visit" note. Walk 500 meters away and back. Verify the notification fires natively.

---

## `implementation_plan_phase_6.md`
# Phase 6: Offline Independence & Document Scanning

**Objective:** Decouple the mobile app from constant internet reliance. Ensure notes are accessible offline and add edge-AI scanning capabilities.

### Component 1: Local Database & Sync Engine
Replace direct API reads with a local cache for offline viewing and searching.

* **Dependencies:** `isar` (NoSQL database, extremely fast for full-text search) and `isar_flutter_libs`.
* **Schema Design:** Define an `IsarNote` collection mirroring the metadata from `url_index.json` and storing the raw markdown body.
* **Sync Logic (`lib/services/sync_service.dart`):**
    * On app launch, fetch a delta of modified notes from the backend since the last sync timestamp.
    * Download the `.md` content for these deltas and save them into the local Isar database.
* **UI Update:** Point `NotesBrowserScreen` and `NoteViewerScreen` to query Isar instead of the FastAPI backend.

### Component 2: Offline Action Queue
Allow users to create tasks, write notes, and edit tags while disconnected.

* **Queue Manager:** * Create an `IsarActionQueue` table.
    * If a user asks a chat question or uploads an audio dump while offline, serialize the request and save it to the queue.
* **Network Listener:** Use `connectivity_plus`. The moment the device regains a Wi-Fi or Cellular connection, automatically iterate through the `IsarActionQueue` and push payloads to the FastAPI backend.

### Component 3: Native Edge Document Scanner
Leverage OS-level document detection to scan physical pages cleanly.

* **Dependencies:** `cunning_document_scanner` (wraps Apple VisionKit and Android ML Kit).
* **Implementation (`lib/screens/scanner_screen.dart`):**
    * Trigger the native scanner, which automatically handles edge detection, perspective correction, and shadow removal.
    * Receive the cropped, flattened image array.
    * Upload the clean images to the existing `POST /api/upload` endpoint, where Gemini handles the OCR and markdown structuring.

### Phase 6 Verification Plan
1.  **Offline Cache:** Sync the app. Put the phone in Airplane Mode. Open Cortex, verify notes load, and test the local search bar.
2.  **Action Queue:** While in Airplane Mode, record an audio Brain Dump. Turn off Airplane Mode. Verify the app silently pushes the audio to the server in the background.
3.  **Doc Scanner:** Scan a physical receipt. Verify the edge-detection UI appears, and the final output note contains correctly extracted line items from Gemini Vision.