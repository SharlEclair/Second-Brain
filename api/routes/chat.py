"""
api/routes/chat.py — RAG chat and chat history session endpoints.
"""
import os
import json
import uuid
import datetime
from fastapi import APIRouter, HTTPException

from api.models import AskRequest
from core.config import OBSIDIAN_INBOX_PATH, PROJECT_VAULT_PATH
from core.processors import generate_content_with_fallback
from core.db import get_vault_collection

router = APIRouter(tags=["chat"])

CHAT_HISTORY_FILE = "chat_history.json"


def load_chat_history():
    if os.path.exists(CHAT_HISTORY_FILE):
        with open(CHAT_HISTORY_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_chat_history(history):
    with open(CHAT_HISTORY_FILE, "w", encoding="utf-8") as f:
        json.dump(history, f, indent=2)


@router.post("/api/chat")
async def chat(request: AskRequest):
    try:
        session_id = request.session_id or str(uuid.uuid4())

        # Determine chat history context
        chat_history_db = load_chat_history()
        session_history = chat_history_db.get(session_id, [])

        from api.services.chat import run_hybrid_chat
        result = run_hybrid_chat(
            message=request.message,
            session_id=session_id,
            note_context_file=request.note_context,
            history=session_history,
        )

        # Save to history
        chat_entry = {
            "timestamp": datetime.datetime.now().isoformat(),
            "query": request.message,
            "response": result["response"],
            "model_used": result["model"],
        }
        if session_id not in chat_history_db:
            chat_history_db[session_id] = []
        chat_history_db[session_id].append(chat_entry)
        save_chat_history(chat_history_db)

        return {
            "response": result["response"],
            "model": result["model"],
            "session_id": result["session_id"],
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/chats")
async def get_chats():
    try:
        chat_history_db = load_chat_history()
        sessions = []
        for session_id, messages in chat_history_db.items():
            if messages:
                # Use the first query as the session title
                title = messages[0]["query"][:50] + (
                    "..." if len(messages[0]["query"]) > 50 else ""
                )
                last_updated = messages[-1]["timestamp"]
                sessions.append(
                    {
                        "session_id": session_id,
                        "title": title,
                        "last_updated": last_updated,
                        "message_count": len(messages),
                    }
                )
        # Sort by most recent
        sessions.sort(key=lambda x: x["last_updated"], reverse=True)
        return {"sessions": sessions}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/chats/{session_id}")
async def get_chat_session(session_id: str):
    try:
        chat_history_db = load_chat_history()
        if session_id not in chat_history_db:
            raise HTTPException(status_code=404, detail="Chat session not found")
        return {"session_id": session_id, "messages": chat_history_db[session_id]}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
