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
        
        # Redis setup
        self.redis_client = None
        try:
            import redis
            from dotenv import load_dotenv
            load_dotenv()
            redis_url = os.getenv("REDIS_URL", "redis://localhost:6379/0")
            self.redis_client = redis.Redis.from_url(redis_url, decode_responses=True)
            self.redis_client.ping()
            print("[State] OperationManager: Connected to Redis successfully.")
        except Exception as e:
            self.redis_client = None
            print(f"[State] OperationManager: Redis not available. Using local in-memory state tracking. Error: {e}")
            
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
        
        if self.redis_client:
            try:
                self.redis_client.hset("cortex:active_tasks", task_id, json.dumps(task))
                return task
            except Exception as e:
                print(f"[State] Redis start_task error: {e}")
                
        with self._lock:
            self.active_tasks[task_id] = task
        return task
        
    def update_task(self, task_id, status, progress=None, error=None, **extra):
        if self.redis_client:
            try:
                task_json = self.redis_client.hget("cortex:active_tasks", task_id)
                if task_json:
                    task = json.loads(task_json)
                    task["status"] = status
                    task["updated_at"] = datetime.datetime.now().isoformat()
                    if progress is not None:
                        task["progress"] = progress
                    if error is not None:
                        task["error"] = error
                    for key, value in extra.items():
                        task[key] = value
                    self.redis_client.hset("cortex:active_tasks", task_id, json.dumps(task))
                    return task
            except Exception as e:
                print(f"[State] Redis update_task error: {e}")
                
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
        if self.redis_client:
            try:
                task_json = self.redis_client.hget("cortex:active_tasks", task_id)
                if task_json:
                    task = json.loads(task_json)
                    self.redis_client.hdel("cortex:active_tasks", task_id)
                    
                    now = datetime.datetime.now().isoformat()
                    task["status"] = final_status
                    task["state"] = state
                    task["updated_at"] = now
                    task["finished_at"] = now
                    if error is not None:
                        task["error"] = error
                    if state in {"completed", "existing"}:
                        task["progress"] = 100
                        
                    self.redis_client.lpush("cortex:recent_tasks", json.dumps(task))
                    self.redis_client.ltrim("cortex:recent_tasks", 0, self.max_recent_tasks - 1)
                    return task
            except Exception as e:
                print(f"[State] Redis end_task error: {e}")
                
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
        if self.redis_client:
            try:
                active_tasks_map = self.redis_client.hgetall("cortex:active_tasks")
                active_tasks = [json.loads(v) for v in active_tasks_map.values()]
                
                recent_tasks_json = self.redis_client.lrange("cortex:recent_tasks", 0, -1)
                recent_tasks = [json.loads(v) for v in recent_tasks_json]
                
                return {
                    "active_tasks": active_tasks,
                    "recent_tasks": recent_tasks,
                    "task_count": len(active_tasks),
                }
            except Exception as e:
                print(f"[State] Redis get_status error: {e}")
                
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
