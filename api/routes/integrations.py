"""
api/routes/integrations.py — External integrations (analytics, Todoist task sync, webhook, FCM device tokens).
"""
import os
import re
import json
import datetime
import hmac
import hashlib
import base64
from fastapi import APIRouter, HTTPException, Request

from api.models import DeviceTokenRequest
from core.config import PROJECT_VAULT_PATH, OBSIDIAN_INBOX_PATH

router = APIRouter(tags=["integrations"])


@router.post("/api/analytics")
async def save_analytics(request: Request):
    try:
        data = await request.json()
        analytics_file = os.path.join(PROJECT_VAULT_PATH, "analytics.json")
        current_analytics = []
        if os.path.exists(analytics_file):
            try:
                with open(analytics_file, "r", encoding="utf-8") as f:
                    current_analytics = json.load(f)
            except Exception:
                current_analytics = []

        # Add timestamp if missing
        if "timestamp" not in data:
            data["timestamp"] = datetime.datetime.now().isoformat()

        current_analytics.append(data)

        # Ensure directory exists and write
        os.makedirs(PROJECT_VAULT_PATH, exist_ok=True)
        with open(analytics_file, "w", encoding="utf-8") as f:
            json.dump(current_analytics, f, indent=2)

        return {"status": "success", "message": "Analytics uploaded successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/tasks")
async def get_all_tasks():
    tasks_file = os.path.join(PROJECT_VAULT_PATH, "_tasks.json")
    if not os.path.exists(tasks_file):
        return []
    try:
        with open(tasks_file, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading tasks file: {e}")
        return []


@router.post("/api/webhooks/todoist")
async def todoist_webhook(request: Request):
    # 1. Enforce signature verification
    signature = request.headers.get("X-Todoist-Hmac-SHA256")
    body = await request.body()

    todoist_client_secret = os.getenv("TODOIST_CLIENT_SECRET")
    if todoist_client_secret:
        if not signature:
            raise HTTPException(
                status_code=401, detail="X-Todoist-Hmac-SHA256 header missing"
            )

        # Calculate HMAC
        computed_hash = hmac.new(
            todoist_client_secret.encode('utf-8'), body, hashlib.sha256
        ).digest()
        computed_sig = base64.b64encode(computed_hash).decode('utf-8')
        if not hmac.compare_digest(computed_sig, signature):
            raise HTTPException(status_code=401, detail="Invalid HMAC signature")
    else:
        print(
            "[Todoist Webhook] Warning: TODOIST_CLIENT_SECRET not configured. Skipping signature validation."
        )

    # 2. Parse payload
    try:
        payload = json.loads(body)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON payload")

    event_name = payload.get("event_name")
    if event_name != "item:completed":
        return {"status": "ignored", "event": event_name}

    event_data = payload.get("event_data", {})
    todoist_task_id = str(event_data.get("id") or event_data.get("item_id", ""))
    if not todoist_task_id:
        raise HTTPException(
            status_code=400, detail="Todoist task ID not found in payload"
        )

    # 3. Read and search tasks
    tasks_file = os.path.join(PROJECT_VAULT_PATH, "_tasks.json")
    if not os.path.exists(tasks_file):
        return {"status": "ignored", "reason": "No tasks database found"}

    try:
        with open(tasks_file, "r", encoding="utf-8") as f:
            tasks = json.load(f)
    except Exception as e:
        print(f"[Todoist Webhook] Error loading tasks list: {e}")
        raise HTTPException(status_code=500, detail="Failed to load tasks list")

    target_task = None
    for task in tasks:
        if task.get("todoist_task_id") and str(task["todoist_task_id"]) == todoist_task_id:
            target_task = task
            break

    if not target_task:
        print(
            f"[Todoist Webhook] No matching local task found for Todoist ID: {todoist_task_id}"
        )
        return {
            "status": "ignored",
            "reason": f"No task found for Todoist ID {todoist_task_id}",
        }

    filename = target_task.get("filename")
    task_text = target_task.get("text")
    if not filename or not task_text:
        return {"status": "ignored", "reason": "Invalid task data stored locally"}

    # 4. Modify physical files
    updated_files = 0
    paths = [
        os.path.join(PROJECT_VAULT_PATH, filename),
        os.path.join(OBSIDIAN_INBOX_PATH, filename),
    ]

    escaped_text = re.escape(task_text)
    pattern = re.compile(rf'^(\s*-\s*\[)\s*(\]\s*{escaped_text})', re.MULTILINE)

    for p in paths:
        if os.path.exists(p):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    content = f.read()

                new_content = pattern.sub(r'\1x\2', content)
                if new_content != content:
                    with open(p, "w", encoding="utf-8") as f:
                        f.write(new_content)
                    updated_files += 1
            except Exception as e:
                print(f"[Todoist Webhook] Failed to update markdown file at {p}: {e}")

    # 5. Update state in _tasks.json
    target_task["completed"] = True
    try:
        with open(tasks_file, "w", encoding="utf-8") as f:
            json.dump(tasks, f, indent=2, ensure_ascii=False)
    except Exception as e:
        print(f"[Todoist Webhook] Failed to write updated tasks list: {e}")

    return {
        "status": "success",
        "task_text": task_text,
        "updated_files": updated_files,
    }


@router.post("/api/device_token")
async def register_device_token(req: DeviceTokenRequest):
    tokens_file = "device_tokens.json"
    tokens = []
    if os.path.exists(tokens_file):
        try:
            with open(tokens_file, "r", encoding="utf-8") as f:
                tokens = json.load(f)
        except Exception:
            tokens = []

    # Prevent duplicates
    if not any(t.get("token") == req.token for t in tokens):
        tokens.append(
            {
                "token": req.token,
                "device": req.device,
                "registered_at": datetime.datetime.now().isoformat(),
            }
        )
        try:
            with open(tokens_file, "w", encoding="utf-8") as f:
                json.dump(tokens, f, indent=2)
        except Exception as e:
            print(f"Error saving device tokens: {e}")
            raise HTTPException(status_code=500, detail="Failed to save token")

    return {"status": "success", "message": "Device token registered"}
