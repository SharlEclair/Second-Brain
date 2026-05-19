# Implementation Plan 2: Mobile Parity & Aesthetics

## Overview
This implementation plan covers the strategy for introducing feature parity to the mobile app (Flutter) by adding the new interactive and dynamic features that were recently introduced to the web application. Additionally, it details the steps required to implement a polished, aesthetic light/dark mode switch across both the mobile app and the web application.

## Tasks

### 1. Mobile App Dynamic Features
* **Objective:** Ensure the mobile application matches the web application in terms of interactive and dynamic capabilities.
* **Details:**
  * Implement the synthesis loop and inbox compile workflow on the Flutter app.
  * Add the "Compile Inbox" functionality, ensuring appropriate state management and API integration with the FastAPI backend.
  * Update the UI to ensure the layout remains highly aesthetic, utilizing Flutter's material/custom design language to mirror the sleek cyberpunk/dark theme currently available on the web.
  * Integrate dynamic charting/knowledge graph visualization if applicable, or equivalent lists that seamlessly display the indexed tags and vault status.

### 2. Aesthetic Light Mode / Dark Mode Switch
* **Objective:** Allow users to toggle between a meticulously designed Light Mode and the existing Dark Mode on both Web and Mobile platforms.
* **Details:**
  * **Web Application (React/Vite):**
    * Introduce a ThemeContext or use an existing state management solution to toggle themes.
    * Define a `light` theme in CSS/Tailwind with a specific color palette (e.g., off-white backgrounds, dark typography, subtle accents) that maintains the "Second Brain" aesthetic without being harsh on the eyes.
    * Add a minimalist toggle switch in the UI (e.g., top-right nav bar) with smooth CSS transitions.
  * **Mobile Application (Flutter):**
    * Update the `MaterialApp` theme configuration to include `ThemeData.light()` and `ThemeData.dark()`.
    * Implement a corresponding toggle switch in the settings or main app bar.
    * Ensure all custom widgets, text colors, and background containers appropriately use the `Theme.of(context)` properties to switch seamlessly.

### 3. Verification & Testing
* **Objective:** Ensure smooth functionality and aesthetic consistency.
* **Details:**
  * Run UI tests on both web and mobile to confirm that flipping the theme switch dynamically updates the UI without requiring a reload.
  * Verify that the new dynamic features on the mobile app interact perfectly with the Python backend.
