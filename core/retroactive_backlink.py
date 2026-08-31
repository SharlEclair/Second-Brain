import os
import re
import datetime
import uuid
import json
from core.config import PROJECT_VAULT_PATH, OBSIDIAN_INBOX_PATH
from core.processors import generate_content_with_fallback
from core.state import get_url_index
from core.utils import chunk_text

def run_retroactive_scan():
    """
    Scans for connections between new notes (last 7 days) and historical notes (> 7 days),
    and appends backlink insights under '## Related Vault Insights' in historical notes.
    """
    print("[Backlink Engine] Starting retroactive backlink scan...")
    
    # 1. Load ChromaDB collection from core.db
    try:
        from core.db import get_vault_collection
        vault_collection = get_vault_collection()
    except Exception as e:
        print(f"[Backlink Engine] Error loading ChromaDB vault_collection: {e}")
        return {"status": "error", "message": "Failed to connect to ChromaDB"}

    # 2. Segment notes into new (<= 7 days) and old (> 7 days)
    index = get_url_index()
    now = datetime.datetime.now()
    seven_days_ago = now - datetime.timedelta(days=7)

    new_notes = []
    old_note_filenames = set()
    old_notes_meta = {}

    for url, data in index.items():
        if not isinstance(data, dict):
            continue
        
        filename = data.get("fileName")
        if not filename:
            continue

        date_str = data.get("date")
        is_new = False
        if date_str:
            try:
                dt = datetime.datetime.fromisoformat(date_str.replace("Z", "+00:00"))
                # Make naive for comparison
                dt = dt.replace(tzinfo=None)
                if dt >= seven_days_ago:
                    is_new = True
            except Exception:
                pass
        
        if is_new:
            # Try to read the note to get its title and summary
            # File search paths
            paths = [
                os.path.join(PROJECT_VAULT_PATH, filename),
                os.path.join(OBSIDIAN_INBOX_PATH, filename)
            ]
            summary = ""
            title = data.get("title") or filename.replace(".md", "").split("/")[-1].split("\\")[-1]
            
            for p in paths:
                if os.path.exists(p):
                    try:
                        with open(p, "r", encoding="utf-8") as f:
                            content = f.read()
                        summary_match = re.search(r'> \*\*AI Summary:\*\* (.*)', content)
                        if summary_match:
                            summary = summary_match.group(1).strip()
                    except Exception:
                        pass
                    break
            
            new_notes.append({
                "title": title,
                "summary": summary or title,
                "filename": filename,
                "url": url
            })
        else:
            old_note_filenames.add(filename)
            old_notes_meta[filename] = {
                "url": url,
                "content_hash": data.get("content_hash", "")
            }

    print(f"[Backlink Engine] Found {len(new_notes)} new notes and {len(old_note_filenames)} old notes.")

    if not new_notes or not old_note_filenames:
        return {"status": "success", "message": "No new or historical notes to analyze."}

    links_created = 0

    # 3. For each new note, find similar old notes
    for new_note in new_notes:
        query_text = f"{new_note['title']}: {new_note['summary']}"
        try:
            # Query ChromaDB for top candidate chunks
            query_results = vault_collection.query(
                query_texts=[query_text],
                n_results=15
            )
        except Exception as e:
            print(f"[Backlink Engine] ChromaDB query failed: {e}")
            continue

        if not query_results or not query_results.get("metadatas") or not query_results["metadatas"][0]:
            continue

        # Get unique older note filenames from results
        candidate_files = []
        seen_files = set()
        for meta in query_results["metadatas"][0]:
            fname = meta.get("filename")
            if fname in old_note_filenames and fname not in seen_files:
                seen_files.add(fname)
                candidate_files.append(fname)
                if len(candidate_files) >= 5:
                    break

        # 4. Prompt LLM to analyze the connection
        for old_fname in candidate_files:
            old_paths = [
                os.path.join(PROJECT_VAULT_PATH, old_fname),
                os.path.join(OBSIDIAN_INBOX_PATH, old_fname)
            ]
            old_content = ""
            old_path_used = None
            
            for p in old_paths:
                if os.path.exists(p):
                    try:
                        with open(p, "r", encoding="utf-8") as f:
                            old_content = f.read()
                        old_path_used = p
                    except Exception:
                        pass
                    break
            
            if not old_content or not old_path_used:
                continue

            prompt = f"""You are an AI Librarian maintaining a wiki. We have an existing historical article:
{old_content}

We recently added a new concept to our brain: 
Title: "{new_note['title']}", Summary: "{new_note['summary']}".

Analyze the historical article. Is there a highly relevant conceptual link to this new concept?
If yes, generate a single concise bullet point explaining the connection and including the markdown link [[{new_note['title']}]].
If no strong connection exists, output exactly "NONE".
Do not include any extra text, markdown wrap, or notes - just output the bullet point or "NONE".
"""
            try:
                response, _ = generate_content_with_fallback(prompt, purpose="retroactive_backlink")
                llm_output = response.text.strip()
            except Exception as e:
                print(f"[Backlink Engine] Gemini call failed for {old_fname}: {e}")
                continue

            if llm_output == "NONE" or "NONE" in llm_output[:10]:
                continue

            # 5. Inject backlink into the older note safely
            print(f"[Backlink Engine] Found link! Connecting {old_fname} -> [[{new_note['title']}]]")
            
            # Read current content to prevent race condition
            try:
                with open(old_path_used, "r", encoding="utf-8") as f:
                    current_content = f.read()
                
                # Check if backlink section already exists
                header = "## Related Vault Insights"
                if header in current_content:
                    # Append bullet point to the end of the section
                    # We can find the header and insert it
                    parts = current_content.split(header)
                    # Append inside the last part
                    updated_content = parts[0] + header + parts[1].rstrip() + f"\n- {llm_output}\n"
                else:
                    # Append header and bullet point at the bottom of the file
                    updated_content = current_content.rstrip() + f"\n\n{header}\n- {llm_output}\n"

                with open(old_path_used, "w", encoding="utf-8") as f:
                    f.write(updated_content)

                # Write to both paths for sync integrity
                other_path = old_paths[1] if old_path_used == old_paths[0] else old_paths[0]
                if os.path.exists(os.path.dirname(other_path)):
                    with open(other_path, "w", encoding="utf-8") as f:
                        f.write(updated_content)

                # 6. Re-index modified older note in ChromaDB
                try:
                    meta = old_notes_meta[old_fname]
                    url = meta["url"]
                    content_hash = meta["content_hash"]
                    
                    # Delete old vectors
                    vault_collection.delete(where={"filename": old_fname})
                    
                    # Chunk and re-insert
                    chunks = [c for c in chunk_text(updated_content) if c.strip()]
                    if chunks:
                        vault_collection.add(
                            documents=chunks,
                            metadatas=[{"filename": old_fname, "url": url, "content_hash": content_hash} for _ in chunks],
                            ids=[f"{content_hash or uuid.uuid4().hex}_chunk_{i}" for i in range(len(chunks))]
                        )
                except Exception as ex:
                    print(f"[Backlink Engine] ChromaDB update failed for {old_fname}: {ex}")

                links_created += 1
            except Exception as e:
                print(f"[Backlink Engine] Failed to write backlink to file: {e}")

    print(f"[Backlink Engine] Scan completed. Created {links_created} backlinks.")
    return {"status": "success", "message": f"Scan completed. Created {links_created} backlinks.", "links_created": links_created}
