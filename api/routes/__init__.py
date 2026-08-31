"""
api/routes package — Modular FastAPI route endpoints.
"""
from api.routes import (
    auth,
    geofence,
    notes,
    system,
    ingest,
    note_actions,
    chat,
    journal,
    discovery,
    vault,
    integrations,
)

__all__ = [
    "auth",
    "geofence",
    "notes",
    "system",
    "ingest",
    "note_actions",
    "chat",
    "journal",
    "discovery",
    "vault",
    "integrations",
]
