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

        # Build context from previous messages (up to 5 recent)
        history_context = ""
        if session_history:
            history_context = "Previous conversation:\n"
            for msg in session_history[-5:]:
                history_context += f"User: {msg['query']}\nAI: {msg['response']}\n"
            history_context += "\n"

        note_context_text = ""
        if request.note_context:
            paths = [
                os.path.join(OBSIDIAN_INBOX_PATH, request.note_context),
                os.path.join(PROJECT_VAULT_PATH, request.note_context),
            ]
            for p in paths:
                if os.path.exists(p):
                    try:
                        with open(p, "r", encoding="utf-8") as f:
                            note_content = f.read()
                            note_context_text = (
                                f"Context from active note ({request.note_context}):\n"
                                f"{note_content}\n\n"
                            )
                    except Exception:
                        pass
                    break

        results = get_vault_collection().query(query_texts=[request.message], n_results=5)
        ctx = (
            "\n".join(results['documents'][0])
            if results['documents'] and results['documents'][0]
            else ""
        )

        prompt = (
            f"Answer based on these notes:\n\n{note_context_text}{ctx}\n\n"
            f"{history_context}Question: {request.message}\n\n"
            "IMPORTANT INSTRUCTION: When referencing important concepts, people, or topics in your answer, "
            "wrap them in Obsidian-style wiki links like [[Concept Name]]."
        )
        response, model_used = generate_content_with_fallback(
            prompt, purpose="rag_chat"
        )

        # Save to history
        chat_entry = {
            "timestamp": datetime.datetime.now().isoformat(),
            "query": request.message,
            "response": response.text,
            "model_used": model_used,
        }
        if session_id not in chat_history_db:
            chat_history_db[session_id] = []
        chat_history_db[session_id].append(chat_entry)
        save_chat_history(chat_history_db)

        return {
            "response": response.text,
            "model": model_used,
            "session_id": session_id,
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
