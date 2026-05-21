Phase 7: Final Implementation & Hardening Plan
This plan outlines the final steps to move your Cortex application from a functional prototype to a reliable production-ready state.

1. Networking & Connectivity Hardening
Objective: Resolve "Connection Failed" errors by aligning Android security and HTTP request configurations.

Task 1.1: Android Cleartext Traffic

Action: You have already updated the AndroidManifest.xml with android:usesCleartextTraffic="true".

Verification: Ensure this is applied to both main/AndroidManifest.xml and debug/AndroidManifest.xml (the latter is often used during local development builds).

Task 1.2: Global Request Hardening

Target: flutter_client/lib/services/api_service.dart

Action: Update the _getHeaders() method to include a dynamic timeout for all requests.

Implementation: Define a static const Duration _timeout = Duration(seconds: 45); and update all http.get and http.post calls to chain .timeout(_timeout). This prevents the app from hanging if the Gemini/Whisper backend is busy.

2. State & Concurrency Fixes
Objective: Prevent app crashes and data corruption during background synchronization.

Task 2.1: Deterministic Isar ID Generation

Target: lib/models/isar_note.dart

Action: Add a helper method int get fastHash that calculates a 64-bit hash from the note's fileName string.

Implementation: Update your SyncService to use this hash as the @Id for Isar objects. This ensures that when you sync the same note twice, Isar overwrites the old data instead of creating duplicates.

Task 2.2: Context Lifecycle Protection

Target: ChatScreen.dart and NoteViewerScreen.dart

Action: Audit every await operation followed by setState or Navigator.

Implementation: Wrap these in a block:

Dart
final result = await apiService.performAction();
if (!mounted) return; // Immediate exit if user left the screen
setState(() { ... });
Task 2.3: Offline Queue Resilience

Target: lib/services/offline_queue_service.dart

Action: Implement a retry limit.

Logic: Add a retry_count integer to your ApiRequest model. Every time processQueue fails to send a request, increment the count. If retry_count >= 3, mark the record as is_failed: true and remove it from the active processQueue loop.

3. Chronological & Spatial Serendipity
Objective: Enable "Event" awareness and location-based discovery.

Task 3.1: Chronological Event Logic (main.py)

Action: Update the /api/serendipity endpoint logic.

Logic: Before selecting random notes, check url_index.json for any note where category == "Event". If event_date is within a 0–7 day window of the current date, force-include these notes in the returned list.

Task 3.2: Spatial Proximity Query (main.py)

Action: Add a new route GET /api/nearby?lat=...&lng=...&radius=....

Logic: Use Python's math.radians and the Haversine formula to filter your url_index.json. Return a JSON list of all notes that contain latitude and longitude fields within your defined radius.

4. Mobile UX: The "ACE" Framework Overhaul
Objective: Migrate the UI to a tab-based system (Atlas, Calendar, Efforts).

Task 4.1: ACE Navigation Structure (ChatScreen.dart)

Action: Remove the TabBar from the AppBar and move to a Scaffold(bottomNavigationBar: BottomNavigationBar(...)).

Tabs:

Calendar: Displays EventsWidget + UpcomingTasks.

Efforts: Displays ChatSidebar + QueueTab.

Atlas: Displays LibraryDirectoryWidget.

Task 4.2: Omni-Capture Speed Dial

Action: In ChatScreen, replace the current FAB with a SpeedDial (or a custom ExpandableFab widget).

Options: The button should expand into three smaller icons:

Voice (triggers BrainDumpButton logic).

Scanner (triggers ScannerScreen).

Text (triggers QuickAskScreen).

5. Implementation Sequence for the LLM
When you hand this to the next LLM, give it these instructions:

"Start with Task 2 (Isar ID generation)." This is the most critical for data integrity.

"Then implement Task 4 (Spatial Endpoints) in main.py."

"Finally, perform the UI migration in ChatScreen.dart."

By following this order, you ensure your data is stable and your backend endpoints exist before the Flutter client tries to call them!