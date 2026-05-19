# Second Brain: Mobile Expansion & Thematic Polish Plan

This implementation plan outlines the architectural approach for bringing the newly added interactive, dynamic features (Hierarchical Indexing, Vault Auditing, Synthesis Loops, and Inbox Compilation) to the Flutter mobile application. Additionally, it defines the strategy for introducing a robust, aesthetic Light/Dark mode toggle across both the React/Vite Web App and the Flutter Mobile App.

## 1. Mobile App Feature Parity (Flutter Expansion)

The mobile app currently acts primarily as an ingestion point. The goal is to elevate it to a full "Mission Control" interface matching the web app.

### A. Hierarchical Markdown Indexing (Library Directory)
- **UI Component:** Implement a new `LibraryDirectoryWidget` in Flutter.
- **Logic:** Fetch `_master-index.md` from the backend via a new or existing API endpoint (e.g., `GET /api/notes/_master-index.md`).
- **Aesthetics:** Use a sleek, collapsible folder-tree UI (`ExpansionTile` or custom animated widgets). Incorporate custom icons (`Icons.folder_special`, `Icons.article`) with subtle accent colors (orange/indigo) on a deep dark or clean light background.

### B. Vault Auditing & Hygiene Dashboard
- **UI Component:** Create an `AuditDashboardScreen` accessible from the main navigation.
- **Logic:** Add a Floating Action Button (FAB) or prominent action card to trigger `POST /api/audit`.
- **Aesthetics:** Display the parsed JSON results (Ghost Topics, Contradictions, Gaps) using stylized cards (`Card` widget with elevated shadows and rounded corners). Use distinct color-coding (Red for contradictions, Orange for ghost topics, Indigo for gaps) to make the data instantly readable.

### C. Inbox "Compile" Workflow
- **UI Component:** Add an "Inbox Status" badge/widget to the mobile home screen.
- **Logic:** Periodically poll `GET /api/raw_count`. If `raw_count > 0`, display a "Compile Inbox" button.
- **Aesthetics:** When tapped, trigger `POST /api/compile` and show a highly aesthetic loading animation (e.g., a custom `Lottie` animation or a complex `AnimatedBuilder` sequence showing "data" flowing into folders).

### D. The Synthesis Loop (Chat Upgrade)
- **UI Component:** Upgrade the existing Chat interface in Flutter.
- **Logic:** Add a "Promote to Wiki" button below AI responses, triggering `POST /api/save_answer`.
- **Aesthetics:** Ensure the chat bubbles follow the new theme guidelines. The "Promote" button should have a glassmorphism effect or a subtle glowing border to encourage interaction.

---

## 2. Universal Light/Dark Mode Implementation

To ensure both applications remain highly aesthetic in any environment, a system-wide theme toggle must be implemented.

### A. Web App (React / Vite / TailwindCSS)
- **State Management:** Implement a theme context or use Zustand/Zustand to manage `theme` state (`light` | `dark`).
- **Persistence:** Save the user's preference in `localStorage`.
- **Tailwind Configuration:** Ensure `darkMode: 'class'` is set in `tailwind.config.js`.
- **CSS Strategy:**
  - Define custom CSS variables in `index.css` for background, text, borders, and accents (e.g., `--bg-primary`, `--text-primary`).
  - Map Tailwind utility classes to these variables.
  - The "Mission Control" aesthetic must adapt: The dark mode remains the current sleek, circuit-board hacker theme (`#0a0a0a` backgrounds, glowing orange/indigo accents). The light mode should pivot to a "Clean Lab" aesthetic (crisp white `#ffffff` or off-white backgrounds, soft gray borders, and vibrant but slightly muted accent colors to maintain readability).
- **Toggle UI:** Add an elegant Sun/Moon toggle switch in the `SystemDashboard` or top header, utilizing `framer-motion` for a smooth transition animation.

### B. Mobile App (Flutter)
- **State Management:** Use `Provider`, `Riverpod`, or `Bloc` to manage `ThemeMode` (System, Light, Dark).
- **Persistence:** Save the preference using `shared_preferences`.
- **ThemeData Definitions:**
  - Create two distinct `ThemeData` objects (`AppTheme.lightTheme` and `AppTheme.darkTheme`).
  - Carefully define `colorScheme`, `scaffoldBackgroundColor`, `appBarTheme`, `cardTheme`, and `textTheme` for both modes.
  - Match the Web App's color palette perfectly to ensure brand consistency across platforms.
- **Toggle UI:** Add a switch in a new `SettingsScreen` or the main App Bar. Ensure smooth interpolation between themes using Flutter's built-in animated theme transitions.

---

## 3. Verification & Testing Plan

1. **Aesthetic Audit:** Visually compare the Web and Mobile light/dark themes side-by-side to ensure color harmony and contrast ratios meet accessibility standards.
2. **Mobile Functionality:** Build and run the Flutter app on an emulator/device. Verify that triggering an Audit or Compile action accurately updates the UI and communicates with the backend without hanging.
3. **Theme Persistence:** Verify that reloading the web page or restarting the mobile app retains the selected theme.
