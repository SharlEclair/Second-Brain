import json
import os
import datetime
import threading
from .config import URL_INDEX_FILE

class OperationManager:
    def __init__(self):
        self.active_tasks = {}
        self.recent_tasks = []
        self.max_recent_tasks = 25
        self.error_logs_file = "error_log.json"
        self._lock = threading.Lock()
        
    def start_task(self, task_id, url, initial_status="Starting", platform=None, progress=0, state="active"):
        now = datetime.datetime.now().isoformat()
        task = {
            "task_id": task_id,
            "url": url,
            "platform": platform,
            "status": initial_status,
            "state": state,
            "progress": progress,
            "start_time": now,
            "updated_at": now,
            "finished_at": None,
            "error": None,
        }
        with self._lock:
            self.active_tasks[task_id] = task
        return task
        
    def update_task(self, task_id, status, progress=None, error=None, **extra):
        with self._lock:
            if task_id in self.active_tasks:
                task = self.active_tasks[task_id]
                task["status"] = status
                task["updated_at"] = datetime.datetime.now().isoformat()
                if progress is not None:
                    task["progress"] = progress
                if error is not None:
                    task["error"] = error
                for key, value in extra.items():
                    task[key] = value
                return task
        return None
            
    def end_task(self, task_id, final_status="Completed", state="completed", error=None):
        with self._lock:
            task = self.active_tasks.pop(task_id, None)
            if not task:
                return None

            now = datetime.datetime.now().isoformat()
            task["status"] = final_status
            task["state"] = state
            task["updated_at"] = now
            task["finished_at"] = now
            if error is not None:
                task["error"] = error
            if state in {"completed", "existing"}:
                task["progress"] = 100

            self.recent_tasks.insert(0, task)
            self.recent_tasks = self.recent_tasks[:self.max_recent_tasks]
            return task

    def get_status(self):
        with self._lock:
            return {
                "active_tasks": list(self.active_tasks.values()),
                "recent_tasks": list(self.recent_tasks),
                "task_count": len(self.active_tasks),
            }

    def log_error(self, url, error_msg, detail=None):
        log_entry = {
            "timestamp": datetime.datetime.now().isoformat(),
            "url": url,
            "error": error_msg,
            "detail": detail
        }
        try:
            logs = []
            if os.path.exists(self.error_logs_file):
                with open(self.error_logs_file, "r") as f:
                    logs = json.load(f)
            logs.insert(0, log_entry)
            with open(self.error_logs_file, "w") as f:
                json.dump(logs[:100], f, indent=4)
        except Exception as e:
            print(f"Failed to log error: {e}")

ops_manager = OperationManager()

def get_url_index():
    if not os.path.exists(URL_INDEX_FILE):
        return {}
    try:
        with open(URL_INDEX_FILE, "r") as f:
            return json.load(f)
    except:
        return {}

def save_url_index(index):
    with open(URL_INDEX_FILE, "w") as f:
        json.dump(index, f, indent=4)
