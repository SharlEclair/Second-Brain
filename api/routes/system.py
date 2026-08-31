"""
api/routes/system.py — System health, status, config, logs, and vault sync routes.
"""
import os
import json
import datetime
import subprocess
from fastapi import APIRouter, HTTPException
from api.models import ToggleInboxModeRequest
from core.state import ops_manager, get_url_index
from core.config import (
    AI_MODEL,
    AI_MODEL_PRIMARY,
    AI_MODEL_FALLBACK,
    AI_MODEL_CHAIN,
    GOOGLE_MAPS_API_KEY,
    PROJECT_VAULT_PATH,
)
from api.services.vault import get_system_config, save_system_config

router = APIRouter(tags=["system"])


@router.get("/")
async def root():
    return {"message": "🧠 Second Brain API is Online", "docs": "/docs"}


@router.get("/api/health")
async def health_check():
    return {"status": "ok"}


@router.get("/api/status")
async def get_system_status():
    return ops_manager.get_status()


@router.get("/api/logs")
async def get_error_logs():
    if os.path.exists("error_log.json"):
        with open("error_log.json", "r", encoding="utf-8") as f:
            return json.load(f)
    return []


@router.post("/api/logs/clear")
async def clear_error_logs():
    if os.path.exists("error_log.json"):
        os.remove("error_log.json")
    return {"status": "cleared"}


def is_location_hidden(
    loc_name: str,
    loc_lat: float,
    loc_lng: float,
    hidden_locations: list,
) -> bool:
    if not hidden_locations:
        return False
    for hl in hidden_locations:
        if isinstance(hl, str):
            if loc_name and hl.strip().lower() == loc_name.strip().lower():
                return True
        elif isinstance(hl, dict):
            hl_lat = hl.get("lat") or hl.get("latitude")
            hl_lng = hl.get("lng") or hl.get("longitude")
            if hl_lat is not None and hl_lng is not None:
                if abs(float(hl_lat) - loc_lat) < 0.0001 and abs(float(hl_lng) - loc_lng) < 0.0001:
                    return True
            hl_name = hl.get("name")
            if hl_name and loc_name and hl_name.strip().lower() == loc_name.strip().lower():
                return True
    return False


@router.get("/api/config")
async def get_config():
    index = get_url_index()
    sys_config = get_system_config()
    return {
        "model": AI_MODEL,
        "primary_model": AI_MODEL_PRIMARY,
        "fallback_model": AI_MODEL_FALLBACK,
        "model_chain": AI_MODEL_CHAIN,
        "note_count": len(index),
        "inbox_mode": sys_config.get("inbox_mode", False),
        "maps_api_key": GOOGLE_MAPS_API_KEY,
    }


@router.post("/api/config/inbox_mode")
async def toggle_inbox_mode(request: ToggleInboxModeRequest):
    config = get_system_config()
    config["inbox_mode"] = request.inbox_mode
    save_system_config(config)
    return {"status": "success", "inbox_mode": config["inbox_mode"]}


@router.post("/api/sync")
async def sync_vault():
    git_dir = os.path.join(PROJECT_VAULT_PATH, ".git")
    if not os.path.exists(git_dir):
        raise HTTPException(
            status_code=400,
            detail="Vault is not initialized as a Git repository. Please initialize git in your vault directory (run 'git init' inside vault/ and configure a remote) before syncing.",
        )

    try:
        # Step 1: Stage all changes
        subprocess.run(
            ["git", "add", "."],
            cwd=PROJECT_VAULT_PATH,
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
        )

        # Step 2: Commit staged changes (does not fail if nothing changed)
        commit_result = subprocess.run(
            ["git", "commit", "-m", "Auto-sync from Second Brain (API)"],
            cwd=PROJECT_VAULT_PATH,
            capture_output=True,
            text=True,
            timeout=30,
        )

        # Step 3: Push commits to remote origin main
        push_result = subprocess.run(
            ["git", "push", "origin", "main"],
            cwd=PROJECT_VAULT_PATH,
            check=True,
            capture_output=True,
            text=True,
            timeout=60,
        )

        output_msg = push_result.stdout or push_result.stderr or commit_result.stdout or "Vault synced successfully."
        return {
            "status": "success",
            "message": "Vault synced to cloud repository",
            "output": output_msg.strip(),
        }
    except subprocess.CalledProcessError as e:
        error_detail = (e.stderr or e.stdout or str(e)).strip()
        raise HTTPException(
            status_code=500,
            detail=f"Git sync failed: {error_detail}",
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Git sync failed: {str(e)}",
        )
