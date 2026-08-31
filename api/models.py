"""
api/models.py — Pydantic request & data models for FastAPI endpoints.

Centralized models shared across routes and services.
"""
from typing import Optional
from pydantic import BaseModel


class IngestRequest(BaseModel):
    url: str


class AskRequest(BaseModel):
    message: str
    session_id: Optional[str] = None
    note_context: Optional[str] = None


class SaveAnswerRequest(BaseModel):
    title: str
    content: str


class ReviewRequest(BaseModel):
    fileName: str


class AppendTasksRequest(BaseModel):
    tasks: str


class JournalAppendRequest(BaseModel):
    content: Optional[str] = None
    text: Optional[str] = None


class ToggleInboxModeRequest(BaseModel):
    inbox_mode: bool


class IngestTextRequest(BaseModel):
    text: str
    title: Optional[str] = "Shared Text"


class RenameTagRequest(BaseModel):
    old_tag: str
    new_tag: str


class CreateNoteRequest(BaseModel):
    title: str
    category: str
    content: Optional[str] = ""


class DeviceTokenRequest(BaseModel):
    token: str
    device: str


class LocationOverrideRequest(BaseModel):
    latitude: float
    longitude: float


class HideLocationRequest(BaseModel):
    name: Optional[str] = None
    lat: Optional[float] = None
    lng: Optional[float] = None
