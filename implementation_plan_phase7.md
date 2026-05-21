# Phase 7: Cortex Hardening, Spatial/Temporal Intelligence & ACE UX Overhaul

Comprehensive implementation plan for 5 major tasks spanning backend (FastAPI/Python), mobile client (Flutter/Dart), and infrastructure (Android).

## User Review Required

> [!IMPORTANT]
> **Task 5 (ACE Redesign)** fundamentally restructures the app navigation. The current `ChatScreen` has 2 tabs (Chat, Queue) with top actions. The new design introduces a `BottomNavigationBar` with 3 sections (Calendar, Efforts, Atlas) plus an Omni-Capture Speed Dial FAB. This is the highest-risk change. All existing functionality (URL ingestion, RAG chat, queue processing) is preserved and relocated into the **Efforts** tab.

> [!WARNING]
> **Isar Schema Changes (Task 2.1)** — Changing the `IsarNote` model's `id` field from `Isar.autoIncrement` to a deterministic hash **requires regenerating the `.g.dart` files** with `build_runner`. The existing Isar database on any test devices will need to be cleared (app data reset) since schema migration in Isar 3.x doesn't support changing the ID strategy on existing data.

> [!IMPORTANT]
> **Task 4.3 (Nearby Notes)** — The `geolocator` package is already in `pubspec.yaml` and location permissions are already in `AndroidManifest.xml`. No new permissions needed.

## Open Questions

> [!IMPORTANT]
> **flutter_animate version** — Task 5.3 requires adding `flutter_animate` to `pubspec.yaml`. Should I use the latest stable (`^4.5.2`) or do you have a preferred version? I'll default to the latest.

> [!NOTE]
> **Isar generated files** — After changing `isar_note.dart`, we must run `dart run build_runner build`. Should I run this command during implementation, or will you handle code generation separately? I'll run it as part of the implementation.

## Proposed Changes

### Task 1: Networking & Connectivity Hardening

---

#### [MODIFY] [AndroidManifest.xml](file:///c:/Users/91704/Desktop/Second-Brain/flutter_client/android/app/src/main/AndroidManifest.xml)
- **Already done** ✅ — Line 6 already has `android:usesCleartextTraffic="true"` on the `<application>` tag. No changes needed.

#### [MODIFY] [settings_screen.dart](file:///c:/Users/91704/Desktop/Second-Brain/flutter_client/lib/screens/settings_screen.dart)
- Modify `_saveUrl()` (L95-105) to sanitize the Base URL before saving:
  - Trim whitespace
  - Remove trailing slashes
  - Prepend `http://` if no scheme present (not starting with `http://` or `https://`)
- Add a visual indicator showing the sanitized URL after save

#### [MODIFY] [api_service.dart](file:///c:/Users/91704/Desktop/Second-Brain/flutter_client/lib/services/api_service.dart)
- **Already done** ✅ — `_getHeaders()` (L27-35) already includes `'ngrok-skip-browser-warning': 'true'` on every request
- **Already done** ✅ — All methods already have `.timeout()` calls ranging from 10s to 900s
- Minor: Ensure `fetchNotes()` (L202-215) and `fetchGeofences()` (L187-200) use the standard timeout pattern (they already do with 15s)

**Conclusion for Task 1:** `AndroidManifest.xml` and `api_service.dart` are already correctly configured from Phase 6. Only `settings_screen.dart` needs the URL sanitization logic.

---

### Task 2: State & Concurrency Fixes

---

#### [MODIFY] [isar_note.dart](file:///c:/Users/91704/Desktop/Second-Brain/flutter_client/lib/models/isar_note.dart)
- The `IsarNote` model already has `@Index(unique: true, replace: true)` on `fileName` (L9), which means Isar's `put()` will replace duplicates when using the `fileName` index.
- However, the `id` is still `Isar.autoIncrement` which means each `put()` creates a new row unless we explicitly query by `fileName` first.
- **Solution:** Add a deterministic `fastHash` function that converts `fileName` to a stable 64-bit `Id`. Set `id` using this hash in `SyncService.syncDown()` before calling `put()`. This ensures Isar overwrites by primary key.

```dart
// Add to isar_note.dart
static int fastHash(String string) {
  var hash = 0xcbf29ce484222325;
  var i = 0;
  while (i < string.length) {
    final codeUnit = string.codeUnitAt(i++);
    hash ^= codeUnit >> 8;
    hash *= 0x100000001b3;
    hash ^= codeUnit & 0xFF;
    hash *= 0x100000001b3;
  }
  return hash;
}
```

#### [MODIFY] [sync_service.dart](file:///c:/Users/91704/Desktop/Second-Brain/flutter_client/lib/services/sync_service.dart)
- In `syncDown()`, before `isarDb.isarNotes.put(newNote)`, set `newNote.id = IsarNote.fastHash(fileName)` to make the ID deterministic
- Apply the same pattern for master index notes and category index notes (L67-95)

#### [MODIFY] [chat_screen.dart](file:///c:/Users/91704/Desktop/Second-Brain/flutter_client/lib/screens/chat_screen.dart)
- Audit all `setState()` / `Navigator` calls after `await`. Most already have `if (mounted)` checks.
- Add `if (!mounted) return;` guard in:
  - `_scanDocument()` — already has guards at L213, L223, L232 ✅
  - `_ingestUrl()` — already has guards at L252, L267, L285 ✅
  - `_sendMessage()` — already has guards at L353, L360 ✅
  - `_processQueue()` — already has guards at L306, L320 ✅
- **All critical paths already guarded** ✅

#### [MODIFY] [note_viewer_screen.dart](file:///c:/Users/91704/Desktop/Second-Brain/flutter_client/lib/screens/note_viewer_screen.dart)
- `_loadNote()` — already has `if (mounted)` guards at L34, L44, L54, L63, L74 ✅
- **All critical paths already guarded** ✅

#### [MODIFY] [library_directory_widget.dart](file:///c:/Users/91704/Desktop/Second-Brain/flutter_client/lib/widgets/library_directory_widget.dart)
- `_loadMasterIndex()` (L25-57): Add `if (!mounted) return;` before `setState` calls at L34 and L43 and L52
- `_CategoryExpansionTileState._loadCategoryNotes()` (L191-227): Add `if (!mounted) return;` before `setState` calls at L202 and L211 and L222

#### [MODIFY] [queue_service.dart](file:///c:/Users/91704/Desktop/Second-Brain/flutter_client/lib/services/queue_service.dart)
- The queue service uses `SharedPreferences` (not Isar) to store pending URLs as a JSON list
- **Poison-pill prevention:** Add a `Map<String, int>` retry tracker. If a URL fails 3 times during `processQueue()`, mark it as permanently failed and remove from the queue. Add a `failedPermanently` list in the result.
- Store failure counts in SharedPreferences key `'queue_retry_counts'` so they persist across sessions

---

### Task 3: Chronological Serendipity

---

#### [MODIFY] [main.py](file:///c:/Users/91704/Desktop/Second-Brain/main.py)

**3.1 — `/api/serendipity` endpoint (L1212-1289):**
- After collecting `all_notes`, add a new phase: scan for Event notes with upcoming `event_date`
- If `category == "Event"` and `event_date` is exactly 7 days, 3 days, or 0 days (today) from now, force that note into the result set
- These forced notes bypass the random pool entirely
- Fill remaining slots (up to 3 total) with the existing random sampling logic

**3.2 — `send_serendipity_notifications()` (L67-119):**
- Before building the FCM message, check if the note has `category == "Event"` and an upcoming `event_date`
- If yes, change `title` from `"🧠 Daily Spark: {title}"` to `"📅 Upcoming Event: {title}"`
- To do this, the serendipity endpoint must return `category` and `event_date` in its response (currently missing)

---

### Task 4: Spatial Serendipity (Nearby Features)

---

#### [MODIFY] [processors.py](file:///c:/Users/91704/Desktop/Second-Brain/core/processors.py)

**4.1 — SYSTEM_PROMPT update (L119-146):**
- Already includes coordinate extraction for "Spot to Visit" ✅ (L134: `If the category is "Spot to Visit", try to extract the approximate latitude and longitude`)
- **Extend to also include "Event" category**: Add instruction that if category is `"Event"`, the AI should also attempt to infer lat/lng from any location mentioned
- The JSON schema already includes `latitude` and `longitude` fields ✅ (L143-144)

#### [MODIFY] [main.py](file:///c:/Users/91704/Desktop/Second-Brain/main.py)

**4.2 — New `/api/nearby` endpoint:**
- Create `GET /api/nearby?lat={x}&lng={y}&radius_km=5`
- Iterate `url_index.json`, filter notes with non-null `latitude` and `longitude`
- Use Haversine formula to calculate distance from query point
- Return notes within radius, sorted by distance ascending
- Include `distance_km` in each result

#### [MODIFY] [api_service.dart](file:///c:/Users/91704/Desktop/Second-Brain/flutter_client/lib/services/api_service.dart)

**4.2b — Add `fetchNearby()` method:**
- `Future<List<Map<String, dynamic>>> fetchNearby(double lat, double lng, {double radiusKm = 5})`
- GET request to `/api/nearby?lat=$lat&lng=$lng&radius_km=$radiusKm`

#### [MODIFY] [notes_browser_screen.dart](file:///c:/Users/91704/Desktop/Second-Brain/flutter_client/lib/screens/notes_browser_screen.dart)

**4.3 — "📍 Find Nearby" FAB:**
- Replace the existing `ScannerScreen` FAB (L211-215) with a "📍 Find Nearby" FAB
- When tapped: use `Geolocator.getCurrentPosition()` to get location
- Call `ApiService.fetchNearby(lat, lng)`
- Show results in a `showModalBottomSheet()` with notes sorted by distance
- Each item shows title, category, and distance in km

---

### Task 5: The "ACE" UX Redesign

---

#### [MODIFY] [chat_screen.dart](file:///c:/Users/91704/Desktop/Second-Brain/flutter_client/lib/screens/chat_screen.dart)

This is the largest change. The current structure:
- `TabBar` with 2 tabs (Chat, Queue) + AppBar actions for Audit/Browser/Settings
- `BrainDumpButton` as FAB on Chat tab

**New structure — BottomNavigationBar with 3 tabs:**

1. **📅 Calendar (Time)** — New tab containing:
   - Today's date header
   - `EventsCarousel` (reused from existing widget)
   - Serendipity notes section (fetched from `/api/serendipity`)
   - Upcoming tasks section

2. **⚡ Efforts (Action)** — Contains existing functionality:
   - Chat interface (messages + input)
   - URL ingestion bar (preserved)
   - Queue view (accessible via badge/button)
   - Inbox compile badge

3. **🧭 Atlas (Knowledge)** — Contains:
   - `LibraryDirectoryWidget` (reused)
   - Entry point to `AuditDashboardScreen`
   - Entry point to `NotesBrowserScreen`

**Omni-Capture Speed Dial FAB:**
- Bottom-center anchored `FloatingActionButton`
- On tap, expands to show 3 options:
  - 🎤 Voice Dump → opens voice dialog
  - 📸 Scan Document → opens scanner
  - ✍️ Quick Text → opens brain dump dialog
- Uses custom animation (expand/collapse)

**Key implementation details:**
- Change `_tabController` from `TabController(length: 2)` to manage 3 body widgets via `_selectedIndex` + `IndexedStack`
- Remove `TabBar` from AppBar, add `BottomNavigationBar`
- Move Settings to AppBar action icon (gear)
- Preserve all existing functionality — URL bar stays at top of Efforts tab, chat stays in Efforts tab

#### [MODIFY] [pubspec.yaml](file:///c:/Users/91704/Desktop/Second-Brain/flutter_client/pubspec.yaml)

**5.3 — Add `flutter_animate` dependency:**
```yaml
flutter_animate: ^4.5.2
```

#### [MODIFY] [library_directory_widget.dart](file:///c:/Users/91704/Desktop/Second-Brain/flutter_client/lib/widgets/library_directory_widget.dart)

**5.3 — Visual Polish:**
- Add `flutter_animate` import
- Apply fade-in + slide-up animations (300ms) to category tiles as they render
- Apply `BorderRadius.circular(16)` to note cards instead of 8

#### [MODIFY] [note_viewer_screen.dart](file:///c:/Users/91704/Desktop/Second-Brain/flutter_client/lib/screens/note_viewer_screen.dart)

**5.3 — Visual Polish:**
- Add `flutter_animate` import  
- Apply 300ms fade-in animation when content loads
- Use `Color(0xFF1E1E1E)` for dark surface instead of `Color(0xFF111111)` for richer dark tones

---

## Verification Plan

### Automated Tests
```bash
# 1. Verify Flutter project compiles
cd flutter_client && flutter analyze

# 2. Verify Isar code generation
cd flutter_client && dart run build_runner build --delete-conflicting-outputs

# 3. Verify Python backend syntax
python -c "import main; print('Backend imports OK')"

# 4. Verify new endpoint exists
python -c "from main import app; routes = [r.path for r in app.routes]; assert '/api/nearby' in routes"
```

### Manual Verification
- Test URL sanitization in Settings screen with inputs like `192.168.1.5:8000/`, `https://example.com///`
- Verify serendipity notifications correctly show "📅 Upcoming Event:" for event notes
- Verify the "Find Nearby" button correctly fetches location and shows bottom sheet
- Verify the ACE BottomNavigationBar shows all 3 tabs with correct content
- Verify the Speed Dial FAB expands and all 3 actions work
- Verify `flutter_animate` animations render on library and note viewer
