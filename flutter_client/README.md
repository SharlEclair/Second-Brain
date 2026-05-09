# Second Brain Mobile (Flutter)

This is the mobile companion app for the Second Brain ecosystem. It allows you to chat with your knowledge vault on the go and ingest new content directly from social media apps via the Android Share Sheet.

## ✨ Features
- **Direct Sharing**: Share any Reel, Video, or Link to this app to instantly save it to your Second Brain.
- **AI Chat**: Full RAG-enabled chat interface.
- **Sync**: Trigger a GitHub push of your vault from your phone.

## ⚙️ Configuration
Before running, you must set your Backend API URL:
1. Open the app.
2. Go to **Settings**.
3. Enter your PC's IP address and port 8000 (e.g., `http://192.168.1.10:8000`).

## 🚀 Development

### Build
```bash
flutter pub get
flutter run
```

### Android Intent Setup
The app is configured to handle `ACTION_SEND` intents. This is defined in `android/app/src/main/AndroidManifest.xml`. If you rename the package, ensure the intent filter is updated accordingly.
