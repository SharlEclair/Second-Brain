# Phase 8: The Ambient Brain & Spatial Mastery

## 1. Headless Background Ingestion (Zero-Friction Sharing)

**Objective:** Share a Reel or URL to Cortex from Instagram/Chrome without opening the Cortex app, confirming success via a Toast.

* **Task 1.1: Native Share Target Modifications**
* **Android:** Update `AndroidManifest.xml`. Create an `IntentFilter` attached to a transparent or headless `Activity` rather than the `MainActivity`.
* **iOS:** Implement a "Share Extension" in Xcode.


* **Task 1.2: Flutter Background Isolate**
* **Action:** When the OS receives the shared text/URL, boot up a Flutter background isolate using the `receive_sharing_intent` package's background execution method.
* **Logic:** 1. Check backend connectivity.
2. If online: Send to `ApiService.ingestUrl()`.
3. If offline: Write to the Isar `OfflineQueue`.


* **Task 1.3: Native Toast Feedback**
* **Dependency:** Add the `fluttertoast` package.
* **Logic:** On successful background ingestion or queue addition, trigger `Fluttertoast.showToast(msg: "Cortex: Saved to Vault 🧠", gravity: ToastGravity.BOTTOM)`.



## 2. Interactive Widgets & Live Activities

**Objective:** Scrollable daily agendas and real-time ingestion tracking right on the OS Home/Lock screens.

* **Task 2.1: iOS Live Activities (Ingestion Tracker)**
* **Action:** Use the `home_widget` package to trigger an iOS Live Activity.
* **Logic:** When the background isolate (from Step 1) starts processing a URL, start a Live Activity: *"Cortex: Ingesting 1 Link..."*. Update the state to *"Categorizing..."* and finally *"Complete"* before dismissing the activity.


* **Task 2.2: Scrollable Agenda Widget (Native Android/iOS)**
* **Constraint Note:** Flutter cannot draw scrollable widgets directly via Dart. You must write native UI code.
* **Android (Kotlin):** Implement a `RemoteViewsService` and a `RemoteViewsFactory` in Kotlin to create a scrollable `ListView`. Bind this to the JSON string of tasks/events fetched by Cortex.
* **iOS (SwiftUI):** Write a SwiftUI Widget Extension using a `List` view to display the daily agenda array.
* **Flutter Sync:** Use `Workmanager` to run a background fetch every 2 hours, dumping the latest agenda JSON into `HomeWidget.saveWidgetData()`.



## 3. The Scratchpad & Daily Journal Pipeline

**Objective:** A beautiful, fast fullscreen typing interface that automatically appends to today's journal.

* **Task 3.1: Backend Journal Endpoint (`main.py`)**
* **Action:** Create `POST /api/journal/append`.
* **Logic:** 1. Determine today's date (e.g., `2026-05-22`).
2. Look for `vault/Journal/2026-05-22 - Daily Journal.md`. If it doesn't exist, create it with a standard template.
3. Append the incoming scratchpad text under a `### Scratchpad Notes` header with a timestamp (e.g., `- [14:30] User's note here`).


* **Task 3.2: Fullscreen Scratchpad UI**
* **Action:** Create `ScratchpadScreen.dart`.
* **Design:** Completely minimal. Pure black/white background (based on theme), a single large `TextField` with `autofocus: true` (keyboard pops up instantly), and no app bar.
* **Action:** When the user swipes down to close the screen, grab the text. If it's not empty, call `apiService.appendToJournal()`, show a tiny haptic confirmation, and clear the local state.



## 4. Spatial Engine V2 (Multi-Location & Deletion)

**Objective:** Handle aggregate posts ("Top 5 cafes") and allow hiding places without deleting the actual note.

* **Task 4.1: Multi-Location Data Model (`core/processors.py`)**
* **Action:** Update the Gemini Prompt and JSON schema.
* **Logic:** Replace single `latitude`/`longitude` fields with a `locations` array:
`"locations": [{"name": "Cafe A", "lat": -37.8, "lng": 144.9}, {"name": "Cafe B", ...}]`.


* **Task 4.2: The "Hide from Nearby" Flag**
* **Action:** Add a `hidden_locations: []` metadata field to notes.
* **Backend Endpoint:** `PATCH /api/notes/{filename}/hide_location`. This accepts a specific coordinate/name and adds it to the `hidden_locations` array in the Markdown YAML.
* **Query Update:** Modify `GET /api/nearby` so it filters out any coordinates present in the `hidden_locations` array before returning the list to the mobile app.


* **Task 4.3: Formatting the Nearby API Response**
* **Logic:** The `/api/nearby` endpoint should now return items grouped by the *Place Name* first, rather than the Note Title.
* **Example:** `{ place_name: "Fallow", type: "Restaurant", distance_km: 1.2, source_note: "Top 10 London Spots.md" }`.



## 5. UI/UX: Map-First Discovery & The Command Palette

**Objective:** Make Cortex feel tactile, explorable, and instantly accessible.

* **Task 5.1: The Map-First View (`NearbyMapScreen.dart`)**
* **Dependency:** Add `Maps_flutter` (since you just generated the API key).
* **Logic:** 1. Fetch user coordinates via `geolocator`.
2. Fetch `/api/nearby`.
3. Render a stunning dark-mode map (using a custom JSON map style).
4. Render custom markers for each location.
5. Add a `DraggableScrollableSheet` at the bottom of the screen. Swiping it up reveals the categorized list view of the nearby spots. Swiping left on a list item calls the `hide_location` endpoint.


* **Task 5.2: Global Command Palette**
* **Action:** Build `CommandPaletteOverlay.dart`.
* **Trigger:** Wrap your main `ChatScreen` Scaffold in a `GestureDetector`. A downward swipe anywhere on the main screen triggers the palette.
* **UI:** A blurred frosted-glass overlay with a centered search bar.
* **Features:** Searching here filters through tags, note titles, or fires quick commands (e.g., typing `/scan` instantly opens the document scanner).


* **Task 5.3: System-Wide Haptics**
* **Action:** Audit all interactive elements.
* **Implementation:** * `HapticFeedback.lightImpact()`: Pressing standard buttons (send chat, open tag).
* `HapticFeedback.mediumImpact()`: Tapping the Omni-Capture speed dial.
* `HapticFeedback.heavyImpact()`: Successfully completing a background queue ingestion or swiping away/hiding a nearby location.