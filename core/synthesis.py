"""
core/synthesis.py — Nightly vault synthesis and semantic footer generation.

Scans Markdown notes in the vault, runs semantic similarity searches against ChromaDB,
identifies unlinked mentions of existing note titles, and safely appends a
semantic footer (## Related Notes and ## Suggested Links).
"""
import os
import re
from core.config import PROJECT_VAULT_PATH
from core.db import get_vault_collection


def get_all_vault_note_titles(vault_path: str = PROJECT_VAULT_PATH) -> dict[str, str]:
    """
    Scans the vault directory for all markdown files and returns a dictionary
    mapping normalized title (lowercase) to the actual note title (without .md).
    Excludes files starting with '.' or '_' and special directories.
    """
    titles = {}
    if not os.path.exists(vault_path):
        return titles

    for root, dirs, files in os.walk(vault_path):
        # Skip special internal or hidden directories
        if ".git" in root or "raw" in root:
            continue
        for file in files:
            if file.endswith(".md") and not file.startswith((".", "_")):
                title = file[:-3].strip()  # Strip .md
                if title:
                    titles[title.lower()] = title
    return titles


def find_related_notes(content: str, current_title: str, top_k: int = 3) -> list[str]:
    """
    Performs semantic search via ChromaDB for the given note content
    and returns up to top_k distinct related note titles (excluding the current note).
    """
    try:
        vault_col = get_vault_collection()
        # Extract summary or first 1000 characters for query
        summary_match = re.search(r'> \*\*AI Summary:\*\* (.*)', content)
        query_text = summary_match.group(1).strip() if summary_match else content[:1000].strip()
        if not query_text:
            return []

        results = vault_col.query(query_texts=[query_text], n_results=top_k + 5)
        if not results or not results.get("documents"):
            return []

        metadatas = results.get("metadatas", [[]])[0]
        related = []
        seen = {current_title.lower()}

        for meta in metadatas:
            if not isinstance(meta, dict):
                continue
            filename = meta.get("filename")
            if not filename:
                continue
            note_title = os.path.basename(filename).replace(".md", "").strip()
            # Normalize and check exclusion
            if note_title and note_title.lower() not in seen:
                seen.add(note_title.lower())
                related.append(note_title)
                if len(related) >= top_k:
                    break

        return related
    except Exception as e:
        print(f"[Synthesis] Error finding related notes: {e}")
        return []


def find_unlinked_mentions(content: str, current_title: str, all_titles: dict[str, str]) -> list[str]:
    """
    Scans content for mentions of existing note titles that are not already
    enclosed in wiki links [[Title]] or markdown links.
    """
    if not content or not all_titles:
        return []

    # Find all existing linked titles in the content (e.g. [[Note Title]] or [[Note Title|Alias]])
    linked_matches = re.findall(r'\[\[([^\]\|]+)(?:\|[^\]]+)?\]\]', content)
    linked_titles_lower = {l.strip().lower() for l in linked_matches}
    current_title_lower = current_title.strip().lower()

    # Remove existing wiki links from text before searching for plain text mentions
    stripped_text = re.sub(r'\[\[[^\]]+\]\]', ' ', content)
    # Also strip markdown links [text](url)
    stripped_text = re.sub(r'\[([^\]]+)\]\([^\)]+\)', r'\1', stripped_text)

    unlinked = []
    seen = set()

    for title_lower, original_title in all_titles.items():
        # Skip current note and already-linked notes
        if title_lower == current_title_lower or title_lower in linked_titles_lower:
            continue
        # Skip trivial or very short strings (<= 2 chars) to avoid false positives
        if len(original_title) <= 2:
            continue

        # Check for word-boundary mention in stripped text (case-insensitive)
        pattern = rf'(?<!\w){re.escape(original_title)}(?!\w)'
        if re.search(pattern, stripped_text, re.IGNORECASE):
            if original_title not in seen:
                seen.add(original_title)
                unlinked.append(original_title)

    return unlinked


def generate_semantic_footer(related_notes: list[str], unlinked_mentions: list[str]) -> str:
    """
    Builds the Markdown semantic footer.
    """
    sections = []
    if related_notes:
        notes_list = "\n".join(f"* [[{n}]]" for n in related_notes)
        sections.append(f"## Related Notes\n{notes_list}")

    if unlinked_mentions:
        mentions_list = "\n".join(f"* [[{m}]]" for m in unlinked_mentions)
        sections.append(f"## Suggested Links (Unlinked Mentions)\n{mentions_list}")

    if not sections:
        return ""

    footer_content = "\n\n".join(sections)
    return f"\n\n---\n{footer_content}\n"


def process_note_synthesis(filepath: str, all_titles: dict[str, str] = None) -> bool:
    """
    Processes a single note file: generates semantic related notes and unlinked mentions,
    then safely appends the footer to the file if '## Related Notes' is not present.
    Returns True if the file was modified, False otherwise.
    """
    if not os.path.exists(filepath) or not filepath.endswith(".md"):
        return False

    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()

        # Check if already processed
        if "## Related Notes" in content:
            return False

        filename = os.path.basename(filepath)
        current_title = filename[:-3] if filename.endswith(".md") else filename

        if all_titles is None:
            all_titles = get_all_vault_note_titles()

        # 1. Semantic Search
        related_notes = find_related_notes(content, current_title, top_k=3)

        # 2. Unlinked Mentions
        unlinked_mentions = find_unlinked_mentions(content, current_title, all_titles)

        # 3. Build and append footer
        footer = generate_semantic_footer(related_notes, unlinked_mentions)
        if not footer:
            return False

        updated_content = content.rstrip() + footer
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(updated_content)

        return True
    except Exception as e:
        print(f"[Synthesis] Error processing {filepath}: {e}")
        return False
