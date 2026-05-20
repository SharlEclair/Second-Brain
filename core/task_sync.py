import os
from todoist_api_python.api import TodoistAPI

def push_task_to_todoist(task_text: str, due_date: str | None, source_filename: str) -> str | None:
    """
    Push a task to Todoist. Returns the todoist task ID if successful, otherwise None.
    """
    todoist_api_key = os.getenv("TODOIST_API_KEY")
    if not todoist_api_key:
        print("[Todoist] TODOIST_API_KEY is not configured in environment variables.")
        return None

    try:
        api = TodoistAPI(todoist_api_key)
        description = f"From Cortex Vault: [[{source_filename}]]"
        
        # Add task payload
        payload = {
            "content": task_text,
            "description": description,
        }
        if due_date:
            payload["due_date"] = due_date

        task = api.add_task(**payload)
        print(f"[Todoist] Task pushed successfully. ID: {task.id}")
        return task.id
    except Exception as e:
        print(f"[Todoist] Failed to push task to Todoist: {e}")
        return None
