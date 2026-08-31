"""
main.py — FastAPI Application Bootstrap & Router Registration.
"""
import os
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from core.utils import cleanup_temp_files
from api.routes import (
    auth,
    geofence,
    notes,
    note_actions,
    system,
    ingest,
    chat,
    journal,
    discovery,
    vault,
    integrations,
)

# Safe Import of Firebase Admin SDK
try:
    import firebase_admin
    from firebase_admin import credentials

    HAS_FIREBASE = True
except ImportError:
    HAS_FIREBASE = False
    print("firebase-admin library not installed. FCM notifications are disabled.")

# Initialize Firebase Admin SDK
firebase_app = None
if HAS_FIREBASE:
    try:
        firebase_cred_path = "firebase_credentials.json"
        if os.path.exists(firebase_cred_path):
            cred = credentials.Certificate(firebase_cred_path)
            firebase_app = firebase_admin.initialize_app(cred)
            print("Firebase Admin SDK initialized successfully.")
        else:
            print(
                "firebase_credentials.json not found in root. FCM notifications are disabled."
            )
    except Exception as e:
        print(f"Error initializing Firebase Admin SDK: {e}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    cleanup_temp_files()
    yield


# --- INITIALIZATION ---
app = FastAPI(title="Second Brain API", lifespan=lifespan)

# Include modular API routers
app.include_router(system.router)
app.include_router(auth.router)
app.include_router(geofence.router)
app.include_router(notes.router)
app.include_router(note_actions.router)
app.include_router(ingest.router)
app.include_router(chat.router)
app.include_router(journal.router)
app.include_router(discovery.router)
app.include_router(vault.router)
app.include_router(integrations.router)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Startup Cleanup
cleanup_temp_files()

if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
