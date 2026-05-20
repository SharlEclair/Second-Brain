import os
import sys
import json
import uuid
import datetime
import hmac
import hashlib
import base64

# Add project root to path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from fastapi.testclient import TestClient
from main import app, PROJECT_VAULT_PATH, OBSIDIAN_INBOX_PATH

client = TestClient(app)

def test_device_token():
    print("[Test] Registering device token...")
    response = client.post("/api/device_token", json={
        "token": "test_fcm_token_12345",
        "device": "android"
    })
    assert response.status_code == 200
    assert response.json()["status"] == "success"
    
    # Check that file exists
    assert os.path.exists("device_tokens.json")
    with open("device_tokens.json", "r") as f:
        tokens = json.load(f)
    assert any(t["token"] == "test_fcm_token_12345" for t in tokens)
    print("[Test] Registering device token passed.")

def test_todoist_webhook():
    print("[Test] Testing Todoist webhook...")
    
    # 1. Create a dummy note with a task to index
    test_filename = "test_note_todoist.md"
    test_filepath = os.path.join(PROJECT_VAULT_PATH, test_filename)
    
    # Write note with task checklist
    with open(test_filepath, "w", encoding="utf-8") as f:
        f.write("# Test Todoist Note\n\n- [ ] Sync this task to todoist\n")
        
    # Trigger update_note_tasks manually
    from main import update_note_tasks
    update_note_tasks(test_filename, "- [ ] Sync this task to todoist")
    
    # Load tasks to find the task and set a dummy todoist_task_id
    tasks_file = os.path.join(PROJECT_VAULT_PATH, "_tasks.json")
    assert os.path.exists(tasks_file)
    with open(tasks_file, "r", encoding="utf-8") as f:
        tasks = json.load(f)
        
    # Find our task
    target_task = None
    for t in tasks:
        if t["filename"] == test_filename:
            target_task = t
            t["todoist_task_id"] = "dummy_todoist_id_999"
            break
            
    assert target_task is not None, "Task was not indexed"
    
    # Save back task with dummy Todoist ID
    with open(tasks_file, "w", encoding="utf-8") as f:
        json.dump(tasks, f, indent=2)
        
    # 2. Call the Todoist webhook endpoint with completion payload
    # Mock signature or skip validation if CLIENT_SECRET not set
    client_secret = os.getenv("TODOIST_CLIENT_SECRET", "dummy_secret")
    os.environ["TODOIST_CLIENT_SECRET"] = client_secret
    
    payload = {
        "event_name": "item:completed",
        "event_data": {
            "id": "dummy_todoist_id_999"
        }
    }
    body_bytes = json.dumps(payload).encode('utf-8')
    computed_hash = hmac.new(client_secret.encode('utf-8'), body_bytes, hashlib.sha256).digest()
    signature = base64.b64encode(computed_hash).decode('utf-8')
    
    response = client.post("/api/webhooks/todoist", 
                           content=body_bytes,
                           headers={"X-Todoist-Hmac-SHA256": signature, "Content-Type": "application/json"})
                           
    assert response.status_code == 200
    assert response.json()["status"] == "success"
    
    # Check that note checkbox got checked
    with open(test_filepath, "r", encoding="utf-8") as f:
        note_content = f.read()
    assert "- [x] Sync this task to todoist" in note_content, f"Checkbox was not updated. Content: {note_content}"
    
    # Check tasks database status
    with open(tasks_file, "r", encoding="utf-8") as f:
        tasks = json.load(f)
    for t in tasks:
        if t["filename"] == test_filename:
            assert t["completed"] is True
            
    # Cleanup
    if os.path.exists(test_filepath):
        os.remove(test_filepath)
    print("[Test] Todoist webhook test passed.")

if __name__ == "__main__":
    test_device_token()
    test_todoist_webhook()
    print("[Success] All integration tests passed successfully.")
