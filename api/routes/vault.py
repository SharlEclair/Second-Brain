"""
api/routes/vault.py — Vault maintenance, tags management, audits, auto-synthesis, and inbox compilation routes.
"""
import os
import re
import json
import uuid
import datetime
import asyncio
from fastapi import APIRouter, HTTPException

from api.models import RenameTagRequest
from core.config import OBSIDIAN_INBOX_PATH, PROJECT_VAULT_PATH, TAGS_FILE, AI_MODEL
from core.state import get_url_index, save_url_index
from core.utils import chunk_text
from core.processors import generate_content_with_fallback
from core.db import get_vault_collection
from api.services.ingestion import get_unique_filename
from api.services.vault import (
    extract_summary_from_md,
    update_hierarchical_indexes,
    update_note_tasks,
)

router = APIRouter(tags=["vault"])


def find_ghost_topics():
    existing_titles = set()

    for root, _, files in os.walk(PROJECT_VAULT_PATH):
        for file in files:
            if file.endswith(".md") and not file.startswith("_"):
                title = file.replace(".md", "")
                existing_titles.add(title.lower())
                existing_titles.add(title)

    ghost_topics = {}

    for root, _, files in os.walk(PROJECT_VAULT_PATH):
        for file in files:
            if file.endswith(".md") and not file.startswith("_"):
                filepath = os.path.join(root, file)
                rel_path = os.path.relpath(filepath, PROJECT_VAULT_PATH).replace("\\", "/")
                try:
                    with open(filepath, "r", encoding="utf-8") as f:
                        content = f.read()

                    links = re.findall(r'\[\[(.*?)\]\]', content)
                    for link in links:
                        target = link.split("|")[0].strip()
                        if not target or target.endswith("_index") or target == "_master-index":
                            continue

                        target_clean = target.split("/")[-1]
                        if (
                            target_clean.lower() not in existing_titles
                            and target.lower() not in existing_titles
                        ):
                            if target_clean not in ghost_topics:
                                ghost_topics[target_clean] = []
                            if rel_path not in ghost_topics[target_clean]:
                                ghost_topics[target_clean].append(rel_path)
                except Exception as e:
                    print(f"Error scanning links in {file}: {e}")

    ghost_list = []
    for title, sources in ghost_topics.items():
        ghost_list.append({"title": title, "sources": sources})
    return ghost_list


@router.get("/api/tags")
async def get_tags():
    try:
        tags = []
        if os.path.exists(TAGS_FILE):
            with open(TAGS_FILE, "r", encoding="utf-8") as f:
                tags = [line.strip() for line in f if line.strip()]
        return {"tags": tags}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/api/tags/rename")
async def rename_tag(request: RenameTagRequest):
    try:
        old_t = request.old_tag
        new_t = request.new_tag

        if not old_t or not new_t:
            raise HTTPException(
                status_code=400, detail="Both old and new tags are required"
            )

        if os.path.exists(TAGS_FILE):
            with open(TAGS_FILE, "r", encoding="utf-8") as f:
                tags = [line.strip() for line in f if line.strip()]

            tags = [new_t if t == old_t else t for t in tags]
            tags = sorted(list(set(tags)))

            with open(TAGS_FILE, "w", encoding="utf-8") as f:
                for t in tags:
                    f.write(f"{t}\n")

        updated_count = 0
        for vault_dir in [PROJECT_VAULT_PATH, OBSIDIAN_INBOX_PATH]:
            for root, _, files in os.walk(vault_dir):
                for file in files:
                    if file.endswith(".md"):
                        filepath = os.path.join(root, file)
                        with open(filepath, "r", encoding="utf-8") as f:
                            content = f.read()
                        if old_t in content:
                            content = re.sub(
                                rf'(?<!\S)#{re.escape(old_t)}\b', f'#{new_t}', content
                            )
                            with open(filepath, "w", encoding="utf-8") as f:
                                f.write(content)
                            if vault_dir == PROJECT_VAULT_PATH:
                                updated_count += 1

        return {
            "status": "success",
            "message": f"Updated tag in {updated_count} files",
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/audit")
async def audit_vault():
    try:
        ghost_list = find_ghost_topics()

        notes_summary_list = []
        for root, _, files in os.walk(PROJECT_VAULT_PATH):
            for file in files:
                if file.endswith(".md") and not file.startswith("_"):
                    title = file.replace(".md", "")
                    filepath = os.path.join(root, file)
                    summary = extract_summary_from_md(filepath)
                    notes_summary_list.append(
                        f"Title: {title}\nSummary: {summary}\n---"
                    )

        notes_summary_str = "\n".join(notes_summary_list)

        prompt = f"""
You are an expert AI Librarian. Analyze the following list of articles and summaries from our Knowledge Base Vault.

Check for:
1. Conflicting claims or outdated information across articles (e.g. contradictions in facts, dates, advice).
2. Gaps in coverage (suggest 3-5 specific articles to add to round out the topics).

Articles list:
{notes_summary_str}

Format your response as a valid JSON object matching the following structure:
{{
  "inconsistencies": [
    {{
      "articles": ["Article Title A", "Article Title B"],
      "conflict": "Description of the contradiction or outdated info"
    }}
  ],
  "gaps": [
    {{
      "suggested_title": "Suggested Article Title",
      "reason": "Why this is a gap and what it should cover"
    }}
  ]
}}

Ensure the output is ONLY valid JSON, with no markdown code fences, leading/trailing backticks, or extra text.
"""
        response, model_used = generate_content_with_fallback(
            prompt, purpose="vault_audit"
        )

        ai_analysis = {"inconsistencies": [], "gaps": []}
        try:
            cleaned_text = response.text.strip()
            if cleaned_text.startswith("```json"):
                cleaned_text = cleaned_text[7:]
            if cleaned_text.endswith("```"):
                cleaned_text = cleaned_text[:-3]
            cleaned_text = cleaned_text.strip()
            ai_data = json.loads(cleaned_text)
            if isinstance(ai_data, dict):
                ai_analysis = ai_data
        except Exception as e:
            print(f"Error parsing AI audit JSON: {e}")

        inconsistencies = ai_analysis.get("inconsistencies", [])
        gaps = ai_analysis.get("gaps", [])

        date_str = datetime.datetime.now().strftime("%Y-%m-%d")
        os.makedirs("output", exist_ok=True)
        filepath = os.path.join("output", f"Vault-Audit-{date_str}.md")

        ghosts_md = ""
        if not ghost_list:
            ghosts_md = "*No missing articles referenced via [[links]] found.*\n"
        else:
            for g in ghost_list:
                sources_str = ", ".join(
                    [f"[[{s.replace('.md', '')}]]" for s in g['sources']]
                )
                ghosts_md += f"- [ ] **[[{g['title']}]]** - referenced in: {sources_str}\n"

        inconsistencies_md = ""
        if not inconsistencies:
            inconsistencies_md = (
                "*No conflicting claims or outdated information detected.*\n"
            )
        else:
            for inc in inconsistencies:
                articles_str = " and ".join([f"[[{art}]]" for art in inc['articles']])
                inconsistencies_md += (
                    f"- **Conflict between {articles_str}**: {inc['conflict']}\n"
                )

        gaps_md = ""
        if not gaps:
            gaps_md = "*No significant coverage gaps detected.*\n"
        else:
            for gap in gaps:
                gaps_md += f"- **[[{gap['suggested_title']}]]**: {gap['reason']}\n"

        markdown_content = f"""---
type: audit-report
date: {date_str}
category: Audit
---
# Vault Audit Report - {date_str}

## Programmatic Analysis

### Ghost Topics (Missing Articles referenced via [[links]])
{ghosts_md}

## AI Analysis

### Conflicting Claims & Outdated Information
{inconsistencies_md}

### Gaps in Coverage (Suggested Articles to Add)
{gaps_md}
"""
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(markdown_content)

        update_hierarchical_indexes()

        return {
            "status": "success",
            "fileName": f"output/Vault-Audit-{date_str}.md",
            "ghost_topics": ghost_list,
            "inconsistencies": inconsistencies,
            "gaps": gaps,
        }
    except Exception as e:
        import traceback

        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/synthesis/weekly")
async def trigger_weekly_synthesis():
    from core.synthesis_loop import run_weekly_synthesis

    result = await run_weekly_synthesis(manual=True)
    if result["status"] == "error":
        raise HTTPException(status_code=500, detail=result["message"])
    return result


@router.post("/api/maintenance/backlink")
async def trigger_retroactive_backlink():
    try:
        from core.retroactive_backlink import run_retroactive_scan

        result = await asyncio.to_thread(run_retroactive_scan)
        if result.get("status") == "error":
            raise HTTPException(status_code=500, detail=result.get("message"))
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/api/compile")
async def compile_inbox():
    try:
        raw_dir = os.path.join(PROJECT_VAULT_PATH, "raw")
        if not os.path.exists(raw_dir):
            return {"status": "success", "compiled_count": 0, "notes": []}

        compiled_notes = []
        files = [
            f for f in os.listdir(raw_dir) if f.endswith(".md") and not f.startswith("_")
        ]

        if not files:
            return {"status": "success", "compiled_count": 0, "notes": []}

        # Get existing categories and note titles to pass to the LLM
        existing_categories = []
        existing_titles = []
        if os.path.exists(PROJECT_VAULT_PATH):
            for item in os.listdir(PROJECT_VAULT_PATH):
                cat_path = os.path.join(PROJECT_VAULT_PATH, item)
                if (
                    os.path.isdir(cat_path)
                    and not item.startswith("_")
                    and item != "raw"
                ):
                    existing_categories.append(item)
                    for f in os.listdir(cat_path):
                        if f.endswith(".md") and not f.startswith("_"):
                            existing_titles.append(f.replace(".md", ""))

        existing_categories_str = ", ".join(existing_categories)
        existing_titles_str = "\n".join([f"- {t}" for t in existing_titles])

        for file in files:
            filepath = os.path.join(raw_dir, file)
            obsidian_filepath = os.path.join(OBSIDIAN_INBOX_PATH, "raw", file)

            with open(filepath, "r", encoding="utf-8") as f:
                raw_content = f.read()

            prompt = f"""
You are an expert AI Librarian. Clean up, refine, and compile this raw note/clipping into a structured, categorized wiki article.

Note content:
{raw_content}

Here are the existing categories in our vault: {existing_categories_str}
Here are the existing note titles in our vault:
{existing_titles_str}

Please perform the following operations:
1. Select the most appropriate category for this note. Choose from the existing categories, or define a new category if none fits.
2. Refine the note: format it with clear, professional markdown. Start the content with a short summary section using format: > **AI Summary:** [Brief summary]
3. Extract relevant tags (e.g. ["#tag1", "#tag2"]).
4. Identify and inject Obsidian-style wiki links like [[Note Title]] for any concepts, topics, or terms in the content that match any of our existing note titles.

Format your response as a valid JSON object matching the following structure:
{{
  "category": "Selected Category",
  "title": "Optimized Note Title",
  "tags": ["#tag1", "#tag2"],
  "summary": "Brief 1-sentence summary",
  "formatted_content": "The refined markdown content with appropriate [[wiki links]]"
}}

Ensure the output is ONLY valid JSON, with no markdown code fences, leading/trailing backticks, or extra text.
"""
            category = "General"
            title = file.replace(".md", "")
            tags = ["#inbox"]
            summary = "Compiled note."
            formatted_content = raw_content
            model_used = AI_MODEL

            try:
                response, model_used = generate_content_with_fallback(
                    prompt, purpose="compile_note"
                )
                cleaned_text = response.text.strip()
                if cleaned_text.startswith("```json"):
                    cleaned_text = cleaned_text[7:]
                if cleaned_text.endswith("```"):
                    cleaned_text = cleaned_text[:-3]
                cleaned_text = cleaned_text.strip()
                ai_data = json.loads(cleaned_text)

                category = ai_data.get("category", "General")
                title = ai_data.get("title", title)
                tags = ai_data.get("tags", tags)
                summary = ai_data.get("summary", summary)
                formatted_content = ai_data.get("formatted_content", formatted_content)
            except Exception as e:
                print(f"Error parsing compile response for {file}: {e}")

            # Query vector database for similar notes to generate auto-backlinks
            related_insights_str = ""
            try:
                query_text = (
                    summary if (summary and len(summary) > 10) else raw_content[:500]
                )
                results = get_vault_collection().query(
                    query_texts=[query_text], n_results=5
                )

                similar_notes = []
                seen_files = set()

                if results and 'documents' in results and results['documents']:
                    docs = results['documents'][0]
                    metas = results['metadatas'][0] if 'metadatas' in results else []

                    for idx, doc in enumerate(docs):
                        meta = metas[idx] if idx < len(metas) else {}
                        fn = meta.get('filename') if isinstance(meta, dict) else None
                        if fn and fn != f"raw/{file}" and not fn.startswith("raw/"):
                            note_title = os.path.basename(fn).replace(".md", "")
                            if note_title not in seen_files:
                                seen_files.add(note_title)
                                similar_notes.append(
                                    {
                                        "title": note_title,
                                        "excerpt": doc[:300],
                                    }
                                )

                if similar_notes:
                    backlink_prompt = f"""
You are an expert AI Librarian. Analyze the relationship between the new note and these potentially related notes in the vault:

New Note:
Title: {title}
Summary: {summary}
Content:
{formatted_content}

Potentially Related Notes:
"""
                    for i, sn in enumerate(similar_notes):
                        backlink_prompt += f"\n{i+1}. Title: {sn['title']}\nExcerpt: {sn['excerpt']}\n"

                    backlink_prompt += """
Decide which of these notes are genuinely relevant and connected. For each relevant connection, generate a single Markdown list item with:
- The Obsidian backlink to the note (e.g. [[Note Title]])
- A concise, one-sentence rationale explaining the connection.

Format the output ONLY as a list of bullet points:
* [[Note Title]]: [Your rationale here]

If none are relevant, output nothing. Do not include markdown code fences, backticks, or other text.
"""
                    response_links, _ = generate_content_with_fallback(
                        backlink_prompt, purpose="backlinks"
                    )
                    links_text = response_links.text.strip()
                    if (
                        links_text
                        and not links_text.lower().startswith("none")
                        and "[[url" not in links_text.lower()
                    ):
                        clean_links = []
                        for line in links_text.splitlines():
                            line_stripped = line.strip()
                            if line_stripped.startswith("*") or line_stripped.startswith("-"):
                                clean_links.append(line_stripped)
                        if clean_links:
                            related_insights_str = (
                                "\n## Related Vault Insights\n"
                                + "\n".join(clean_links)
                                + "\n"
                            )
            except Exception as e:
                print(f"Error generating auto-backlinks for {file}: {e}")

            date_str = datetime.datetime.now().strftime("%Y-%m-%d")
            safe_category = re.sub(r'[\\/*?:"<>|]', "-", category)
            project_category_path = os.path.join(PROJECT_VAULT_PATH, safe_category)
            obsidian_category_path = os.path.join(OBSIDIAN_INBOX_PATH, safe_category)
            os.makedirs(project_category_path, exist_ok=True)
            os.makedirs(obsidian_category_path, exist_ok=True)

            new_filename = get_unique_filename(
                f"{date_str} - {safe_category} ({title}).md",
                category=safe_category,
            )
            new_project_filepath = os.path.join(project_category_path, new_filename)
            new_obsidian_filepath = os.path.join(obsidian_category_path, new_filename)

            full_content = f"""---
type: note
date: {date_str}
category: {category}
tags: {tags}
ai_model: {model_used}
---
# {title}

> **AI Summary:** {summary}

## Extracted Content
{formatted_content}
{related_insights_str}"""
            with open(new_project_filepath, "w", encoding="utf-8") as f:
                f.write(full_content)
            with open(new_obsidian_filepath, "w", encoding="utf-8") as f:
                f.write(full_content)

            relative_filename = os.path.join(safe_category, new_filename).replace(
                "\\", "/"
            )

            try:
                update_note_tasks(relative_filename, full_content)
            except Exception as e:
                print(f"Error updating tasks for {new_filename}: {e}")

            # Find the original URL from index mapping if it exists
            index = get_url_index()
            original_url = None
            for url, val in index.items():
                if isinstance(val, dict) and val.get("fileName") == f"raw/{file}":
                    original_url = url
                    break

            # Remove old index entry
            if original_url:
                index.pop(original_url, None)

            # Add new index entry
            new_url = original_url or f"local://{relative_filename}"
            note_data = {
                "title": new_filename.replace(".md", ""),
                "fileName": relative_filename,
                "date": datetime.datetime.now().isoformat(),
                "url": new_url,
                "category": category,
                "tags": tags,
            }
            index[new_url] = note_data
            save_url_index(index)

            # Update Vector DB (Delete raw note chunks and add compiled note chunks)
            try:
                get_vault_collection().delete(where={"filename": f"raw/{file}"})
            except Exception as e:
                print(f"Error deleting old chunks from vector db: {e}")

            chunks = [
                chunk for chunk in chunk_text(formatted_content) if chunk.strip()
            ]
            if chunks:
                get_vault_collection().add(
                    documents=chunks,
                    metadatas=[
                        {
                            "filename": relative_filename,
                            "url": new_url,
                            "content_hash": "",
                        }
                        for _ in chunks
                    ],
                    ids=[
                        f"compile_{uuid.uuid4().hex}_chunk_{i}"
                        for i in range(len(chunks))
                    ],
                )

            # Clean up the raw files
            try:
                if os.path.exists(filepath):
                    os.remove(filepath)
                if os.path.exists(obsidian_filepath):
                    os.remove(obsidian_filepath)
            except Exception as e:
                print(f"Error removing raw files: {e}")

            compiled_notes.append(note_data)

        update_hierarchical_indexes()

        return {
            "status": "success",
            "compiled_count": len(compiled_notes),
            "notes": compiled_notes,
        }
    except Exception as e:
        import traceback

        print(traceback.format_exc())
        raise HTTPException(status_code=500, detail=str(e))
