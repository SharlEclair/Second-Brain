# 🧠 Second Brain: AI-Powered Knowledge Vault

Second Brain is a sophisticated personal knowledge management system that automatically captures, transcribes, and organizes content from social media (Instagram, YouTube, TikTok) into a structured Obsidian vault. It features a RAG-enabled (Retrieval-Augmented Generation) chat interface for deep research into your saved notes.

## 🚀 Key Features

- **Omni-Ingestion**: Automatically processes URLs from Instagram (Reels & Carousels), YouTube, and TikTok.
- **AI Transcription**: High-performance audio-to-text using `faster-whisper`.
- **Intelligent Structuring**: Powered by Gemini 2.5 Flash to categorize content into Recipes, Spots, Events, and more.
- **RAG Chat**: Ask questions about your personal vault and get answers synthesized from your specific notes.
- **Obsidian Integration**: Saves notes directly to your vault with rich frontmatter, hierarchical tags, and wiki-links.
- **Real-time Status**: Live feedback during the ingestion process (Downloading → Transcribing → Analyzing).
- **Git Sync**: One-click synchronization of your entire vault to GitHub.

## 🛠️ Architecture

- **Backend**: Python FastAPI serving as the intelligence engine.
- **Frontend (Web)**: React + Vite + Tailwind CSS for a premium dashboard experience.
- **Mobile (Android)**: Flutter client with Share Sheet integration for one-tap ingestion.
- **Database**: ChromaDB (Vector Search) + Local JSON index.

## 📥 Installation

### Prerequisites
- Python 3.10+
- Node.js & npm
- FFmpeg (required for `yt-dlp` audio extraction)
- [Optional] Obsidian (to view your notes locally)

### Setup
1. **Clone the repository**:
   ```bash
   git clone https://github.com/SharlEclair/Second-Brain.git
   cd Second-Brain
   ```

2. **Install Backend Dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Install Frontend Dependencies**:
   ```bash
   npm install
   ```

4. **Configure Environment**:
   Create a `.env` file in the root:
   ```env
   GEMINI_API_KEY="your_api_key_here"
   OBSIDIAN_VAULT_PATH="C:\Path\To\Your\Vault"
   ```

## 🏃 Running the App

You need to run the backend and frontend simultaneously:

**Terminal 1 (Backend)**:
```bash
npm run backend
```

**Terminal 2 (Frontend)**:
```bash
npm run dev
```

**Mobile**:
Open the `flutter_client` folder in VS Code/Android Studio and run the app on your device. Set the API URL to `http://your-pc-ip:8000` in the app settings.

## 📂 Project Structure

- `main.py`: FastAPI Intelligence Engine.
- `src/`: React Frontend source code.
- `flutter_client/`: Flutter mobile application.
- `vault/`: Local storage for generated Markdown notes.
- `tags.txt`: Master list for hierarchical tagging.
