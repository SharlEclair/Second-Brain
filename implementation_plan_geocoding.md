# Phase 7.5: Geocoding & Spatial Integrity Pipeline

**Objective:** Eliminate AI location hallucinations by shifting from AI-guessed coordinates to a deterministic Google Maps Geocoding pipeline. Implement a frontend fallback using the Google Places API for manual overrides.

---

## Step 1: Google Cloud Platform (GCP) Configuration

Before writing code, you need to enable the correct APIs in the GCP Console where your Calendar API is currently configured.

1. **Enable APIs:** In the GCP Console, go to **APIs & Services > Library** and enable:
* **Geocoding API:** (Used by the Python backend to convert text strings to coordinates).
* **Places API (New):** (Used by the Flutter frontend for the autocomplete search bar).


2. **Generate API Key:** Go to **Credentials**, create an API Key.
3. **Secure the Key:** Restrict this API key. For the backend, restrict it by IP address (if known) or leave it unrestricted *only* in your local `.env`. For the frontend, restrict it by Android/iOS app bundle ID.
4. **Environment Setup:** Add `Maps_API_KEY=your_key_here` to your backend `.env` file.

---

## Step 2: Backend Automation & "Context Stitching"

**Target:** `core/processors.py` and `core/config.py`

### 2.1: Update Dependencies & Config

* **Dependency:** Run `pip install googlemaps` to use the official Python client.
* **Config:** Load the `Maps_API_KEY` into your `core/config.py` settings.

### 2.2: Context-Stitching Prompt Engineering

* **Target:** `SYSTEM_PROMPT` in `core/processors.py`
* **Action:** Remove any instructions asking Gemini to extract `latitude` and `longitude`.
* **New Instruction:** Add the following to the prompt:
> *"If the content implies a 'Spot to Visit' or an 'Event', extract the specific venue name and the city/neighborhood into a new field called `location_query` (e.g., 'Fallow Restaurant, St. James, London')."*
> *"CRITICAL CONTEXT STITCHING: Social media posts often omit the city. You MUST infer the city based on the creator's username, hashtags, or surrounding context (e.g., if they mention 'CBD' or 'Chapel St', append ', Melbourne' to the `location_query`). Do NOT attempt to guess GPS coordinates."*



### 2.3: The Geocoding Interceptor

* **Target:** The processing function in `core/processors.py` (after Gemini returns the JSON, but before the Markdown file is saved).
* **Logic:**
1. Check if `location_query` exists in the extracted AI data.
2. Initialize the Google Maps client: `gmaps = googlemaps.Client(key=CONFIG.GOOGLE_MAPS_API_KEY)`.
3. Call the API: `geocode_result = gmaps.geocode(ai_data['location_query'])`.
4. If a result is returned, extract `geocode_result[0]['geometry']['location']['lat']` and `['lng']`.
5. Inject these exact `latitude` and `longitude` values into the metadata dictionary that will be written to the Markdown YAML frontmatter and `url_index.json`.



---

## Step 3: Backend Manual Override Endpoint

**Target:** `main.py`

Sometimes the Geocoder will fail (e.g., a place is too new). The mobile app needs a way to forcefully update a note's coordinates.

* **Endpoint:** Create a new route: `PATCH /api/notes/{filename}/location`
* **Payload:** Accept a JSON body containing `latitude` (float) and `longitude` (float).
* **Logic:**
1. Locate the Markdown file in the `PROJECT_VAULT_PATH`.
2. Read the file, parse the YAML frontmatter.
3. Update or add the `latitude` and `longitude` fields.
4. Write the file back to disk.
5. Update the corresponding entry in `url_index.json` so the `/api/nearby` endpoint can immediately see the new location.



---

## Step 4: Frontend Failsafe & Native Search UI

**Target:** `flutter_client/`

### 4.1: API Service Update

* **Target:** `lib/services/api_service.dart`
* **Action:** Add a method `updateNoteLocation(String fileName, double lat, double lng)` that sends a `PATCH` request to your new backend endpoint.

### 4.2: Note Viewer Missing Data UI

* **Target:** `lib/screens/note_viewer_screen.dart`
* **Logic:** When rendering the note's metadata at the top of the screen:
1. Check if `category == 'Spot to Visit'` or `Event`.
2. Check if `latitude == null` or `longitude == null`.
3. If missing, render a highly visible UI button (e.g., a greyed-out map pin icon with text: *"Location missing. Tap to set."*).



### 4.3: Google Places Autocomplete Integration

* **Dependency:** Add the `flutter_google_places_sdk` package to your `pubspec.yaml`.
* **Action:** When the user taps the "Location missing" button:
1. Launch the Google Places Autocomplete widget/overlay.
2. The user types the name of the restaurant (e.g., "Fallow London") and selects the correct Google Maps result.
3. The widget returns a `Place` object containing the exact `lat` and `lng`.
4. Call `apiService.updateNoteLocation(fileName, place.lat, place.lng)`.
5. Call `setState()` to update the local UI, replacing the "Missing" button with a green map pin that can deep-link out to the Google Maps app for directions.



---

## Verification Plan

1. **Test Context Stitching:** Ingest an Instagram reel caption that only says *"Best coffee on Lygon st!"* Verify the Python console logs show the AI appending ", Melbourne" to create the `location_query: "Lygon st, Melbourne"`.
2. **Test Geocoding:** Verify the saved Markdown file has perfectly precise `latitude` and `longitude` fields in its YAML frontmatter.
3. **Test Failsafe:** Manually edit a "Spot to Visit" Markdown file on your computer and delete the `latitude` field. Open the note in the Flutter app. Verify the "Location missing" button appears.
4. **Test Autocomplete Override:** Tap the missing location button, search for a valid place, and verify the backend `PATCH` route updates the physical Markdown file on your hard drive.