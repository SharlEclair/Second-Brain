"""
api/routes/journal.py — Daily journal append and scratchpad note extraction routes.
"""
import os
import re
import json
import datetime
import asyncio
from fastapi import APIRouter, HTTPException

from api.models import JournalAppendRequest
from core.config import PROJECT_VAULT_PATH
from core.state import get_url_index, save_url_index
from core.processors import generate_content_with_fallback
from api.services.vault import update_hierarchical_indexes

router = APIRouter(tags=["journal"])


@router.post("/api/journal/append")
async def append_to_journal(request: JournalAppendRequest):
    try:
        note_content = request.text or request.content
        if not note_content:
            raise HTTPException(
                status_code=400, detail="Either 'text' or 'content' field must be provided"
            )

        # 1. Determine today's date
        now = datetime.datetime.now()
        today_str = now.strftime("%Y-%m-%d")
        current_time = now.strftime("%H:%M")
        full_current_time_str = now.strftime("%Y-%m-%d %H:%M:%S")

        # 1.5. Check for events/reminders using Gemini
        try:
            prompt = f"""You are an intelligent assistant. The current date and time is {full_current_time_str}.
Analyze the following scratchpad note. Does it describe a future event, task with a deadline, or appointment?
If yes, return a JSON object with:
- "is_event": true
- "title": event title (string)
- "event_date": absolute date/time formatted as "YYYY-MM-DD HH:MM:SS" (resolve relative words like 'tomorrow', 'today', 'this friday' using the current date provided)
- "description": optional details (string)

If it's just a regular note or journal entry without an actionable event, return {{"is_event": false}}.

Respond ONLY with valid JSON. Do not include markdown formatting or backticks around the JSON.

Note: {note_content}"""

            response, model_used = generate_content_with_fallback(
                prompt, purpose="scratchpad_event_extraction"
            )

            cleaned_response = response.text.strip()
            if cleaned_response.startswith("```json"):
                cleaned_response = cleaned_response[7:]
            if cleaned_response.startswith("```"):
                cleaned_response = cleaned_response[3:]
            if cleaned_response.endswith("```"):
                cleaned_response = cleaned_response[:-3]

            parsed_data = json.loads(cleaned_response.strip())

            if parsed_data.get("is_event"):
                event_date = parsed_data.get("event_date")
                event_title = parsed_data.get("title", "Scratchpad Event")
                event_desc = parsed_data.get("description", note_content)

                if event_date:
                    from core.calendar_sync import create_calendar_event

                    await asyncio.to_thread(
                        create_calendar_event,
                        title=event_title,
                        event_date_str=event_date,
                        source_url="",
                        description=event_desc,
                    )
        except Exception as e:
            print(f"Failed to extract or create event from scratchpad: {e}")

        # 2. Path to the daily journal
        journal_dir = os.path.join(PROJECT_VAULT_PATH, "Journal")
        os.makedirs(journal_dir, exist_ok=True)
        filename = f"{today_str} - Daily Journal.md"
        filepath = os.path.join(journal_dir, filename)

        # 3. Create file if it doesn't exist
        if not os.path.exists(filepath):
            template = f"""---
tags:
  - Journal/Daily
date: {today_str}
---

# Daily Journal - {today_str}

## Focus of the Day
- 

## Tasks & Schedule
- [ ] 

## Notes & Thoughts
- 

### Scratchpad Notes
"""
            with open(filepath, "w", encoding="utf-8") as f:
                f.write(template)

        # 4. Append note to journal under Scratchpad Notes header
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()

        lines = content.splitlines()
        header_idx = -1
        for idx, line in enumerate(lines):
            # Check for ## Scratchpad Notes or ### Scratchpad Notes
            if "Scratchpad Notes" in line and (
                line.startswith("###") or line.startswith("##")
            ):
                header_idx = idx
                break

        new_bullet = f"- [{current_time}] {note_content}"

        if header_idx != -1:
            # Found the header. We append to the end of this section (i.e. before the next header)
            insert_idx = header_idx + 1
            while insert_idx < len(lines):
                if lines[insert_idx].startswith("#"):
                    break
                insert_idx += 1
            # Backtrack past empty lines to place cleanly
            while insert_idx > header_idx + 1 and lines[insert_idx - 1].strip() == "":
                insert_idx -= 1
            lines.insert(insert_idx, new_bullet)
            new_content = "\n".join(lines) + "\n"
        else:
            # Header not found, append to the end of the file
            if content.endswith("\n\n"):
                new_content = content + f"### Scratchpad Notes\n{new_bullet}\n"
            elif content.endswith("\n"):
                new_content = content + f"\n### Scratchpad Notes\n{new_bullet}\n"
            else:
                new_content = content + f"\n\n### Scratchpad Notes\n{new_bullet}\n"

        with open(filepath, "w", encoding="utf-8") as f:
            f.write(new_content)

        # 5. Add to url_index.json if not present so it's searchable
        index = get_url_index()
        url_key = f"journal-{today_str}"
        if url_key not in index:
            index[url_key] = {
                "title": f"{today_str} - Daily Journal",
                "fileName": f"Journal/{filename}",
                "category": "Journal",
                "date": today_str,
            }
            save_url_index(index)

        # 6. Run hierarchical index update
        try:
            update_hierarchical_indexes()
        except Exception as e:
            print(f"Error updating hierarchical indexes: {e}")

        return {
            "status": "success",
            "message": f"Successfully appended note to Daily Journal: {filename}",
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
