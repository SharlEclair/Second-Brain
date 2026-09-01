import os
import pytest
from core.taxonomy import (
    extract_note_metadata,
    update_note_tags,
    cluster_tags_with_gemini,
    generate_maps_of_content,
    run_taxonomy_and_moc_pipeline,
)


def test_extract_note_metadata(tmp_path):
    note = tmp_path / "AI_Note.md"
    note.write_text("""---
type: article
tags: ["#ai", "#career/resume"]
---
# AI Note Title

> **AI Summary:** A note about artificial intelligence in job applications.
""", encoding="utf-8")

    meta = extract_note_metadata(str(note))
    assert meta["title"] == "AI_Note"
    assert "#ai" in meta["tags"]
    assert "#career/resume" in meta["tags"]
    assert "A note about artificial intelligence" in meta["summary"]


def test_update_note_tags(tmp_path):
    note = tmp_path / "Tech_Note.md"
    note.write_text("""---
title: Tech Note
tags: ["#ai", "#llm", "#job-search"]
---
# Content Body
Some text here.
""", encoding="utf-8")

    tag_map = {
        "#ai": "#ArtificialIntelligence",
        "#llm": "#ArtificialIntelligence",
        "#job-search": "#Career",
    }

    updated = update_note_tags(str(note), tag_map)
    assert updated is True

    # Read back note content
    new_meta = extract_note_metadata(str(note))
    assert "#ArtificialIntelligence" in new_meta["tags"]
    assert "#Career" in new_meta["tags"]
    # Verify deduplication (ai and llm both map to #ArtificialIntelligence)
    assert new_meta["tags"].count("#ArtificialIntelligence") == 1
    assert "#ai" not in new_meta["tags"]


def test_generate_maps_of_content(tmp_path):
    vault = tmp_path / "vault"
    vault.mkdir()

    # Note 1 with #AI
    n1 = vault / "Note_1.md"
    n1.write_text("""---
tags: ["#ArtificialIntelligence"]
---
> **AI Summary:** First note discussing transformers.
""", encoding="utf-8")

    # Note 2 with #AI
    n2 = vault / "Note_2.md"
    n2.write_text("""---
tags: ["#ArtificialIntelligence"]
---
> **AI Summary:** Second note discussing diffusion models.
""", encoding="utf-8")

    # Note 3 with unique single tag (should not generate MOC because count < 2)
    n3 = vault / "Note_3.md"
    n3.write_text("""---
tags: ["#SingleTopic"]
---
> **AI Summary:** Solo note.
""", encoding="utf-8")

    mocs = generate_maps_of_content(str(vault))
    assert "ArtificialIntelligence" in mocs

    moc_file = vault / "Maps" / "ArtificialIntelligence_Index.md"
    assert moc_file.exists()

    content = moc_file.read_text(encoding="utf-8")
    assert "type: moc" in content
    assert "tag: ArtificialIntelligence" in content
    assert "# ArtificialIntelligence Map of Content" in content
    assert "## Indexed Notes" in content
    assert "* [[Note_1]] - First note discussing transformers." in content
    assert "* [[Note_2]] - Second note discussing diffusion models." in content

    # Verify SingleTopic was not generated
    single_moc = vault / "Maps" / "SingleTopic_Index.md"
    assert not single_moc.exists()


def test_run_taxonomy_and_moc_pipeline(tmp_path, monkeypatch):
    vault = tmp_path / "vault"
    vault.mkdir()

    n1 = vault / "AI_1.md"
    n1.write_text("""---
tags: ["#ai"]
---
> **AI Summary:** Overview of LLMs.
""", encoding="utf-8")

    n2 = vault / "AI_2.md"
    n2.write_text("""---
tags: ["#generative-ai"]
---
> **AI Summary:** Overview of text generation.
""", encoding="utf-8")

    # Mock Gemini clustering to avoid external API calls during testing
    monkeypatch.setattr(
        "core.taxonomy.cluster_tags_with_gemini",
        lambda tags: {"#ai": "#ArtificialIntelligence", "#generative-ai": "#ArtificialIntelligence"}
    )

    res = run_taxonomy_and_moc_pipeline(str(vault))
    assert res["status"] == "success"
    assert res["updated_notes_count"] == 2
    assert "ArtificialIntelligence" in res["mocs_generated"]
