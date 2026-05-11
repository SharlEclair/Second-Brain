import json
import os
import datetime
from .config import URL_INDEX_FILE

class OperationManager:
    def __init__(self):
        self.active_tasks = {} # task_id -> {url, status, start_time}
        self.error_logs_file = "error_log.json"
        
    def start_task(self, task_id, url, initial_status="Starting"):
        self.active_tasks[task_id] = {
            "url": url,
            "status": initial_status,
            "start_time": datetime.datetime.now().isoformat()
        }
        
    def update_task(self, task_id, status):
        if task_id in self.active_tasks:
            self.active_tasks[task_id]["status"] = status
            
    def end_task(self, task_id):
        if task_id in self.active_tasks:
            del self.active_tasks[task_id]

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
