"""
core/taxonomy.py — Autonomous Librarian: Tag Merging & Dynamic Maps of Content (MOC).

Extracts tags from vault note frontmatters, clusters them with Gemini to unify taxonomy,
updates note frontmatters in-place, and generates/refreshes Map of Content index files
in vault/Maps/.
"""
import os
import re
import json
import datetime
import yaml
from core.config import PROJECT_VAULT_PATH
from core.processors import generate_content_with_fallback


def extract_note_metadata(filepath: str) -> dict:
    """
    Reads note file and extracts YAML frontmatter tags, summary/snippet, and title.
    """
    title = os.path.basename(filepath)
    if title.endswith(".md"):
        title = title[:-3]

    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
    except Exception as e:
        print(f"[Taxonomy] Failed to read {filepath}: {e}")
        return {"tags": [], "summary": "", "title": title, "raw_content": "", "body": ""}

    frontmatter_match = re.match(r'^---\s*\n(.*?)\n---\s*\n(.*)$', content, re.DOTALL)
    if not frontmatter_match:
        # Check if entire file is frontmatter or body only
        return {"tags": [], "summary": content[:200].replace("\n", " ").strip(), "title": title, "raw_content": content, "body": content}

    fm_raw, body = frontmatter_match.groups()
    try:
        data = yaml.safe_load(fm_raw) or {}
    except Exception:
        data = {}

    tags = []
    raw_tags = data.get("tags") or data.get("tag")
    if isinstance(raw_tags, list):
        tags = [str(t).strip() for t in raw_tags if str(t).strip()]
    elif isinstance(raw_tags, str):
        tags = [t.strip() for t in raw_tags.split(",") if t.strip()]

    # Normalize tags to always start with '#'
    normalized_tags = []
    for t in tags:
        norm = t if t.startswith("#") else f"#{t}"
        if norm not in normalized_tags:
            normalized_tags.append(norm)

    # Extract summary/description
    summary_match = re.search(r'> \*\*AI Summary:\*\* (.*)', body)
    if summary_match:
        summary = summary_match.group(1).strip()
    else:
        sec_match = re.search(r'## Summary\s*\n+(.*?)(?=\n## |\Z)', body, re.DOTALL)
        if sec_match:
            summary = sec_match.group(1).strip().split("\n")[0]
        else:
            # Clean first few non-empty lines
            clean_lines = [l.strip() for l in body.splitlines() if l.strip() and not l.startswith("#")]
            summary = clean_lines[0] if clean_lines else "Note content reference"

    return {
        "tags": normalized_tags,
        "summary": summary[:250],
        "title": title,
        "raw_content": content,
        "frontmatter": data,
        "body": body,
    }


def update_note_tags(filepath: str, unified_tag_map: dict[str, str]) -> bool:
    """
    Updates the note's YAML frontmatter tags with the unified tag mapping.
    Returns True if tags were changed and file was saved.
    """
    if not os.path.exists(filepath) or not filepath.endswith(".md"):
        return False

    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()

        fm_match = re.match(r'^---\s*\n(.*?)\n---\s*\n(.*)$', content, re.DOTALL)
        if not fm_match:
            return False

        fm_raw, body = fm_match.groups()
        data = yaml.safe_load(fm_raw)
        if not isinstance(data, dict):
            return False

        raw_tags = data.get("tags") or data.get("tag")
        if not raw_tags:
            return False

        if isinstance(raw_tags, list):
            current_tags = [str(t).strip() for t in raw_tags if str(t).strip()]
        else:
            current_tags = [t.strip() for t in str(raw_tags).split(",") if t.strip()]

        new_tags = []
        changed = False
        for t in current_tags:
            norm_t = t if t.startswith("#") else f"#{t}"
            mapped_t = (
                unified_tag_map.get(norm_t)
                or unified_tag_map.get(norm_t.lower())
                or unified_tag_map.get(norm_t.lstrip("#"))
                or norm_t
            )
            if not mapped_t.startswith("#"):
                mapped_t = f"#{mapped_t}"
            if mapped_t != norm_t:
                changed = True
            if mapped_t not in new_tags:
                new_tags.append(mapped_t)

        if not changed:
            return False

        data["tags"] = new_tags
        if "tag" in data:
            del data["tag"]

        new_fm_str = yaml.dump(data, sort_keys=False, default_flow_style=None)
        new_content = f"---\n{new_fm_str.strip()}\n---\n{body}"

        with open(filepath, "w", encoding="utf-8") as f:
            f.write(new_content)
        return True
    except Exception as e:
        print(f"[Taxonomy] Error updating tags for {filepath}: {e}")
        return False


def cluster_tags_with_gemini(unique_tags: list[str]) -> dict[str, str]:
    """
    Uses Gemini to cluster semantically similar or duplicate tags under standard umbrella terms.
    Returns a dictionary mapping { "#old_tag": "#UnifiedTag" }.
    """
    if len(unique_tags) < 2:
        return {t: t for t in unique_tags}

    prompt = f"""
You are an expert taxonomy and knowledge organization AI for an Obsidian Second Brain vault.
Analyze this list of unique tags found in the user's notes:
{json.dumps(unique_tags, indent=2)}

Your task:
1. Identify duplicate tags, singular/plural variations (e.g. #job vs #jobs), casing variations, synonyms, sub-topic splinters, and fragmentations.
2. Group them under standard, clean PascalCase or semantic umbrella tags (e.g., #AI, #LLM, #GenerativeAI -> #ArtificialIntelligence; #career, #job-search, #Job-Career, #career/resume -> #Career; #recipe, #recipes, #cooking -> #Recipe; #travel, #spots-to-visit -> #SpotToVisit).
3. If a tag is already clean and distinct, map it to itself.
4. Output a strict JSON object mapping every single input tag to its unified tag. Every value must start with '#'.

Output ONLY valid JSON with no markdown wrapping or extra comments:
{{
  "#old_tag": "#UnifiedTag"
}}
"""
    try:
        response, _ = generate_content_with_fallback(prompt, purpose="tag_taxonomy")
        text = response.text.strip()
        if text.startswith("```"):
            text = re.sub(r'^```(?:json)?\s*', '', text)
            text = re.sub(r'\s*```$', '', text)
        mapping = json.loads(text)
        clean_map = {}
        for k, v in mapping.items():
            key = k if k.startswith("#") else f"#{k}"
            val = v if v.startswith("#") else f"#{v}"
            clean_map[key] = val
            clean_map[key.lower()] = val
        return clean_map
    except Exception as e:
        print(f"[Taxonomy] Tag clustering LLM call failed or skipped: {e}")
        return {t: t for t in unique_tags}


def generate_maps_of_content(vault_path: str = PROJECT_VAULT_PATH) -> dict[str, str]:
    """
    Generates or refreshes Map of Content (MOC) index files in vault/Maps/
    for each tag cluster that contains 2 or more notes.
    """
    maps_dir = os.path.join(vault_path, "Maps")
    os.makedirs(maps_dir, exist_ok=True)

    tag_to_notes: dict[str, list[dict]] = {}

    for root, dirs, files in os.walk(vault_path):
        if ".git" in root or "Maps" in root or "raw" in root:
            continue
        for file in files:
            if file.endswith(".md") and not file.startswith((".", "_")):
                filepath = os.path.join(root, file)
                meta = extract_note_metadata(filepath)
                for tag in meta["tags"]:
                    norm_tag = tag if tag.startswith("#") else f"#{tag}"
                    tag_to_notes.setdefault(norm_tag, []).append(meta)

    created_mocs = {}
    timestamp = datetime.datetime.now().isoformat()

    for tag, notes in tag_to_notes.items():
        if len(notes) < 2:
            continue

        category_title = tag.lstrip("#")
        category_filename_clean = re.sub(r'[/\\:*?"<>|]', '_', category_title)
        moc_filename = f"{category_filename_clean}_Index.md"
        moc_path = os.path.join(maps_dir, moc_filename)

        seen_titles = set()
        indexed_items = []
        for n in notes:
            if n["title"] in seen_titles:
                continue
            seen_titles.add(n["title"])
            desc = n["summary"] or "Note reference"
            if len(desc) > 120:
                desc = desc[:117] + "..."
            indexed_items.append(f"* [[{n['title']}]] - {desc}")

        indexed_text = "\n".join(indexed_items)
        moc_content = f"""---
type: moc
tag: {category_title}
last_updated: {timestamp}
---
# {category_title} Map of Content

## Indexed Notes
{indexed_text}
"""
        with open(moc_path, "w", encoding="utf-8") as f:
            f.write(moc_content)
        created_mocs[category_title] = moc_path

    return created_mocs


def run_taxonomy_and_moc_pipeline(vault_path: str = PROJECT_VAULT_PATH) -> dict:
    """
    Executes the end-to-end Autonomous Librarian pipeline:
    1. Collects all unique tags across notes.
    2. Clusters and normalizes tags with Gemini.
    3. Updates note frontmatters in-place.
    4. Generates dynamic MOC files in vault/Maps/.
    """
    if not os.path.exists(vault_path):
        return {"status": "error", "message": "Vault path does not exist"}

    print(f"[Taxonomy] Scanning vault at {vault_path} for tags...")
    all_files = []
    all_tags = set()

    for root, dirs, files in os.walk(vault_path):
        if ".git" in root or "Maps" in root or "raw" in root:
            continue
        for file in files:
            if file.endswith(".md") and not file.startswith((".", "_")):
                fp = os.path.join(root, file)
                all_files.append(fp)
                meta = extract_note_metadata(fp)
                for t in meta["tags"]:
                    all_tags.add(t)

    unique_tags = sorted(list(all_tags))
    print(f"[Taxonomy] Found {len(unique_tags)} unique tags across {len(all_files)} notes.")

    # 1. Cluster tags with Gemini
    tag_map = cluster_tags_with_gemini(unique_tags)

    # 2. Update affected notes
    updated_count = 0
    for fp in all_files:
        if update_note_tags(fp, tag_map):
            updated_count += 1

    print(f"[Taxonomy] Updated tags in {updated_count} notes.")

    # 3. Generate Maps of Content
    created_mocs = generate_maps_of_content(vault_path)
    print(f"[Taxonomy] Generated/refreshed {len(created_mocs)} Maps of Content in {os.path.join(vault_path, 'Maps')}.")

    return {
        "status": "success",
        "unique_tags_count": len(unique_tags),
        "updated_notes_count": updated_count,
        "mocs_generated": list(created_mocs.keys()),
    }
