"""
api/services/vault.py — Vault maintenance, system config, index generation, and task extraction.
"""
import os
import json
import re
import uuid
import datetime
from core.config import OBSIDIAN_INBOX_PATH, PROJECT_VAULT_PATH
from core.processors import generate_content_with_fallback

SYSTEM_CONFIG_FILE = "system_config.json"
CATEGORY_SUMMARIES_CACHE = {}


def get_system_config() -> dict:
    if os.path.exists(SYSTEM_CONFIG_FILE):
        try:
            with open(SYSTEM_CONFIG_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {"inbox_mode": False}


def save_system_config(config: dict):
    with open(SYSTEM_CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2)


def extract_summary_from_md(filepath: str) -> str:
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()
        match = re.search(r'> \*\*AI Summary:\*\* (.*)', content)
        if match:
            return match.group(1).strip()
        body = content
        if content.startswith("---\n"):
            end_idx = content.find("\n---\n", 4)
            if end_idx != -1:
                body = content[end_idx + 5:]

        lines = [
            l.strip()
            for l in body.split("\n")
            if l.strip() and not l.strip().startswith("#") and not l.strip().startswith(">")
        ]
        if lines:
            summary = lines[0]
            if len(summary) > 100:
                summary = summary[:97] + "..."
            return summary
    except Exception:
        pass
    return "No summary available."


def update_hierarchical_indexes():
    """Generates _master-index.md and _index.md for each category to maintain the AI Librarian structure."""
    global CATEGORY_SUMMARIES_CACHE
    for vault_path in [PROJECT_VAULT_PATH, OBSIDIAN_INBOX_PATH]:
        if not os.path.exists(vault_path):
            continue

        categories = {}
        for item in os.listdir(vault_path):
            cat_path = os.path.join(vault_path, item)
            if os.path.isdir(cat_path):
                md_files = [f for f in os.listdir(cat_path) if f.endswith('.md') and f != '_index.md']
                if not md_files:
                    continue
                categories[item] = len(md_files)

                # Extract summaries for each file in this category
                file_summaries = {}
                for md in md_files:
                    filepath = os.path.join(cat_path, md)
                    summary = extract_summary_from_md(filepath)
                    file_summaries[md.replace(".md", "")] = summary

                # Get or generate category summary
                cache_key = f"{item}:{','.join(sorted(md_files))}"
                if cache_key in CATEGORY_SUMMARIES_CACHE:
                    cat_summary = CATEGORY_SUMMARIES_CACHE[cache_key]
                else:
                    prompt = (
                        f"Describe the category/topic '{item}' in one brief, engaging sentence based on "
                        f"the following articles inside it:\n"
                        + "\n".join([f"- {title}: {sum_val}" for title, sum_val in file_summaries.items()])
                    )
                    try:
                        res, _ = generate_content_with_fallback(prompt, purpose="category_summary")
                        cat_summary = res.text.strip()
                    except Exception:
                        cat_summary = f"Articles related to {item}."
                    CATEGORY_SUMMARIES_CACHE[cache_key] = cat_summary

                index_content = f"# {item} Index\n\n{cat_summary}\n\nThis folder contains {len(md_files)} articles related to {item}.\n\n## Articles\n"
                for title, summary in file_summaries.items():
                    index_content += f"- [[{title}]]: {summary}\n"

                with open(os.path.join(cat_path, "_index.md"), "w", encoding="utf-8") as f:
                    f.write(index_content)

        master_content = "# Knowledge Base Master Index\n\nTopics appear here as they're created.\n\n"
        for cat, count in categories.items():
            cat_summary = ""
            for k, val in CATEGORY_SUMMARIES_CACHE.items():
                if k.startswith(f"{cat}:"):
                    cat_summary = val
                    break
            if not cat_summary:
                cat_summary = f"Articles related to {cat}."

            master_content += f"- **[[{cat}/_index|{cat}]]**: {count} articles\n  *{cat_summary}*\n"

        with open(os.path.join(vault_path, "_master-index.md"), "w", encoding="utf-8") as f:
            f.write(master_content)


def update_note_tasks(filename: str, markdown_content: str):
    """Parses markdown checkboxes and updates _tasks.json, optionally syncing to Todoist."""
    tasks_file = os.path.join(PROJECT_VAULT_PATH, "_tasks.json")
    existing_tasks = []
    if os.path.exists(tasks_file):
        try:
            with open(tasks_file, "r", encoding="utf-8") as f:
                existing_tasks = json.load(f)
        except Exception as e:
            print(f"Error loading tasks: {e}")

    existing_map = {t["text"]: t for t in existing_tasks if t.get("filename") == filename}
    cleaned_tasks = [t for t in existing_tasks if t.get("filename") != filename]

    new_tasks = []
    lines = markdown_content.splitlines()
    for line in lines:
        match = re.search(r'^\s*-\s*\[\s*\]\s*(.+)$', line)
        if match:
            task_text = match.group(1).strip()
            due_date = None
            date_match = re.search(r'(?:due:|@due|by:?)\s*(\d{4}-\d{2}-\d{2})', task_text, re.IGNORECASE)
            if date_match:
                due_date = date_match.group(1)

            if task_text in existing_map:
                new_tasks.append(existing_map[task_text])
            else:
                from core.task_sync import push_task_to_todoist
                todoist_id = push_task_to_todoist(task_text, due_date, filename)

                new_tasks.append({
                    "id": str(uuid.uuid4()),
                    "text": task_text,
                    "due_date": due_date,
                    "filename": filename,
                    "completed": False,
                    "todoist_task_id": todoist_id,
                    "created_at": datetime.datetime.now().isoformat(),
                })

    cleaned_tasks.extend(new_tasks)
    try:
        with open(tasks_file, "w", encoding="utf-8") as f:
            json.dump(cleaned_tasks, f, indent=2, ensure_ascii=False)
    except Exception as e:
        print(f"Error saving tasks: {e}")
