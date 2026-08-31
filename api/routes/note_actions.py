"""
api/routes/note_actions.py — Note enhancement and modification actions (summarize, deep dive, extract tasks, review, create, save answer).
"""
import os
import re
import json
import uuid
import datetime
from fastapi import APIRouter, HTTPException

from api.models import (
    AppendTasksRequest,
    ReviewRequest,
    CreateNoteRequest,
    SaveAnswerRequest,
)
from core.config import OBSIDIAN_INBOX_PATH, PROJECT_VAULT_PATH, AI_MODEL
from core.state import get_url_index, save_url_index
from core.utils import chunk_text
from core.processors import generate_content_with_fallback
from core.db import get_vault_collection
from api.services.ingestion import get_unique_filename
from api.services.vault import update_hierarchical_indexes

router = APIRouter(tags=["note_actions"])


@router.post("/api/notes/{filename:path}/summarize")
async def summarize_note(filename: str):
    paths = [
        os.path.join(OBSIDIAN_INBOX_PATH, filename),
        os.path.join(PROJECT_VAULT_PATH, filename),
    ]
    content = None
    for p in paths:
        if os.path.exists(p):
            with open(p, "r", encoding="utf-8") as f:
                content = f.read()
            break
    if not content:
        raise HTTPException(status_code=404, detail="Note not found")

    prompt = f"Provide a concise 3-5 bullet point summary of this note. Focus on actionable takeaways:\n\n{content}"
    response, model_used = generate_content_with_fallback(
        prompt, purpose="note_summary"
    )
    return {"summary": response.text, "model": model_used}


@router.post("/api/notes/{filename:path}/deep_dive")
async def deep_dive_note(filename: str):
    paths = [
        os.path.join(OBSIDIAN_INBOX_PATH, filename),
        os.path.join(PROJECT_VAULT_PATH, filename),
    ]
    content = None
    for p in paths:
        if os.path.exists(p):
            with open(p, "r", encoding="utf-8") as f:
                content = f.read()
            break
    if not content:
        raise HTTPException(status_code=404, detail="Note not found")

    prompt = (
        "Provide a detailed analysis of this note. Include: (1) Key concepts explained, "
        "(2) Connections to broader topics, (3) Questions worth exploring further, "
        "(4) Practical applications. Format with markdown headers:\n\n"
        f"{content}"
    )
    response, model_used = generate_content_with_fallback(
        prompt, purpose="note_deep_dive"
    )
    return {"deep_dive": response.text, "model": model_used}


@router.post("/api/notes/{filename:path}/extract_tasks")
async def extract_tasks(filename: str):
    paths = [
        os.path.join(OBSIDIAN_INBOX_PATH, filename),
        os.path.join(PROJECT_VAULT_PATH, filename),
    ]
    content = None
    for p in paths:
        if os.path.exists(p):
            with open(p, "r", encoding="utf-8") as f:
                content = f.read()
            break
    if not content:
        raise HTTPException(status_code=404, detail="Note not found")

    prompt = (
        "Analyze the following note content and extract a clean list of actionable checklist items (tasks/next steps). "
        "Format them using Obsidian Markdown task syntax (- [ ] Task description). "
        "Keep them highly specific and concise. Respond ONLY with the list of tasks (no headers, intro, or wrap-up text):\n\n"
        f"{content}"
    )
    response, model_used = generate_content_with_fallback(
        prompt, purpose="task_extraction"
    )
    return {"tasks": response.text.strip(), "model": model_used}


@router.post("/api/notes/{filename:path}/append_tasks")
async def append_tasks(filename: str, request: AppendTasksRequest):
    paths = [
        os.path.join(OBSIDIAN_INBOX_PATH, filename),
        os.path.join(PROJECT_VAULT_PATH, filename),
    ]
    filepaths_found = [p for p in paths if os.path.exists(p)]
    if not filepaths_found:
        raise HTTPException(status_code=404, detail="Note not found")

    for path in filepaths_found:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()

        new_content = content + f"\n\n## Actionable Tasks\n{request.tasks}\n"
        with open(path, "w", encoding="utf-8") as f:
            f.write(new_content)

    return {"status": "success", "message": "Tasks successfully appended to note"}


@router.post("/api/notes/reviewed")
async def mark_note_reviewed(request: ReviewRequest):
    try:
        index = get_url_index()
        target_url = None
        for url, data in index.items():
            if isinstance(data, dict) and data.get("fileName") == request.fileName:
                target_url = url
                break

        if not target_url:
            raise HTTPException(status_code=404, detail="Note not found in index")

        now_str = datetime.datetime.now().isoformat()
        index[target_url]["last_reviewed"] = now_str
        save_url_index(index)

        paths = [
            os.path.join(OBSIDIAN_INBOX_PATH, request.fileName),
            os.path.join(PROJECT_VAULT_PATH, request.fileName),
        ]
        for p in paths:
            if os.path.exists(p):
                with open(p, "r", encoding="utf-8") as f:
                    content = f.read()

                if content.startswith("---\n"):
                    end_idx = content.find("\n---\n", 4)
                    if end_idx != -1:
                        frontmatter = content[4:end_idx]
                        body = content[end_idx + 5:]

                        if "last_reviewed:" in frontmatter:
                            frontmatter = re.sub(
                                r'last_reviewed:.*',
                                f'last_reviewed: {now_str}',
                                frontmatter,
                            )
                        else:
                            frontmatter += f"\nlast_reviewed: {now_str}"

                        new_content = f"---\n{frontmatter}\n---\n{body}"
                        with open(p, "w", encoding="utf-8") as f:
                            f.write(new_content)

        return {"status": "success", "message": "Note marked as reviewed"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/notes/create")
async def create_note(request: CreateNoteRequest):
    try:
        date_str = datetime.datetime.now().strftime("%Y-%m-%d")
        safe_title = re.sub(r'[\\/*?:"<>|]', "", request.title)
        safe_category = re.sub(r'[\\/*?:"<>|]', "-", request.category)

        filename = f"{safe_title}.md"
        project_category_path = os.path.join(PROJECT_VAULT_PATH, safe_category)
        obsidian_category_path = os.path.join(OBSIDIAN_INBOX_PATH, safe_category)
        os.makedirs(project_category_path, exist_ok=True)
        os.makedirs(obsidian_category_path, exist_ok=True)

        project_filepath = os.path.join(project_category_path, filename)
        obsidian_filepath = os.path.join(obsidian_category_path, filename)

        if os.path.exists(project_filepath) or os.path.exists(obsidian_filepath):
            raise HTTPException(status_code=400, detail="Note already exists")

        content = f"""---
type: note
date: {date_str}
category: {request.category}
tags: ["#inbox"]
---
# {request.title}

{request.content or "Draft article created via Vault Audit."}
"""
        with open(project_filepath, "w", encoding="utf-8") as f:
            f.write(content)
        with open(obsidian_filepath, "w", encoding="utf-8") as f:
            f.write(content)

        relative_filename = os.path.join(safe_category, filename).replace("\\", "/")
        note_data = {
            "title": request.title,
            "fileName": relative_filename,
            "date": datetime.datetime.now().isoformat(),
            "url": f"local://{relative_filename}",
            "category": request.category,
            "tags": ["#inbox"],
        }

        index = get_url_index()
        index[f"local://{relative_filename}"] = note_data
        save_url_index(index)

        update_hierarchical_indexes()

        return {"status": "success", "note": note_data}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/save_answer")
async def save_answer(request: SaveAnswerRequest):
    try:
        existing_categories = []
        existing_titles = []
        if os.path.exists(PROJECT_VAULT_PATH):
            for item in os.listdir(PROJECT_VAULT_PATH):
                cat_path = os.path.join(PROJECT_VAULT_PATH, item)
                if os.path.isdir(cat_path) and not item.startswith("_") and item != "raw":
                    existing_categories.append(item)
                    for f in os.listdir(cat_path):
                        if f.endswith(".md") and not f.startswith("_"):
                            existing_titles.append(f.replace(".md", ""))

        existing_categories_str = ", ".join(existing_categories)
        existing_titles_str = "\n".join([f"- {t}" for t in existing_titles])

        prompt = f"""
You are an expert AI Librarian organizing a knowledge base.
We are saving a synthesized chat answer to our wiki. 

Title of the article: {request.title}
Content:
{request.content}

Here are the existing categories in our vault: {existing_categories_str}
Here are the existing note titles in our vault:
{existing_titles_str}

Please perform the following operations:
1. Select the most appropriate category for this note. Choose from the existing categories, or define a new category if none fits.
2. Refine the note: format it with clear, professional markdown (headers, lists, tables).
3. Identify and inject Obsidian-style wiki links like [[Note Title]] for any concepts, topics, or terms in the content that match any of our existing note titles. Ensure links are injected naturally and accurately.

Format your response as a valid JSON object matching the following structure:
{{
  "category": "Selected Category",
  "formatted_content": "The refined markdown content with appropriate [[wiki links]]"
}}

Ensure the output is ONLY valid JSON, with no markdown code fences, leading/trailing backticks, or extra text.
"""
        category = "Synthesis"
        formatted_content = request.content
        model_used = AI_MODEL

        try:
            response, model_used = generate_content_with_fallback(
                prompt, purpose="save_answer"
            )
            cleaned_text = response.text.strip()
            if cleaned_text.startswith("```json"):
                cleaned_text = cleaned_text[7:]
            if cleaned_text.endswith("```"):
                cleaned_text = cleaned_text[:-3]
            cleaned_text = cleaned_text.strip()
            ai_data = json.loads(cleaned_text)

            category = ai_data.get("category", "Synthesis")
            formatted_content = ai_data.get("formatted_content", request.content)
        except Exception as e:
            print(f"Error calling LLM for save_answer: {e}")

        date_str = datetime.datetime.now().strftime("%Y-%m-%d")
        safe_title = re.sub(r'[\\/*?:"<>|]', "", request.title)
        safe_category = re.sub(r'[\\/*?:"<>|]', "-", category)

        project_category_path = os.path.join(PROJECT_VAULT_PATH, safe_category)
        obsidian_category_path = os.path.join(OBSIDIAN_INBOX_PATH, safe_category)
        os.makedirs(project_category_path, exist_ok=True)
        os.makedirs(obsidian_category_path, exist_ok=True)

        filename = get_unique_filename(
            f"Synthesis - {safe_title}.md", category=safe_category
        )
        project_filepath = os.path.join(project_category_path, filename)
        obsidian_filepath = os.path.join(obsidian_category_path, filename)

        full_content = f"""---
type: synthesized_note
date: {date_str}
category: {category}
ai_model: {model_used}
---
# {request.title}

{formatted_content}
"""
        with open(project_filepath, "w", encoding="utf-8") as f:
            f.write(full_content)
        with open(obsidian_filepath, "w", encoding="utf-8") as f:
            f.write(full_content)

        relative_filename = os.path.join(safe_category, filename).replace("\\", "/")
        note_data = {
            "title": filename.replace(".md", ""),
            "fileName": relative_filename,
            "date": datetime.datetime.now().isoformat(),
            "url": f"local://{relative_filename}",
            "category": category,
        }

        # Add to index mapping
        index = get_url_index()
        index[f"local://{relative_filename}"] = note_data
        save_url_index(index)

        # Also index in ChromaDB
        chunks = [chunk for chunk in chunk_text(formatted_content) if chunk.strip()]
        if chunks:
            get_vault_collection().add(
                documents=chunks,
                metadatas=[
                    {
                        "filename": relative_filename,
                        "url": f"local://{relative_filename}",
                        "content_hash": "",
                    }
                    for _ in chunks
                ],
                ids=[f"synthesis_{uuid.uuid4().hex}_chunk_{i}" for i in range(len(chunks))],
            )

        update_hierarchical_indexes()

        return {"status": "success", "fileName": relative_filename, "note": note_data}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
