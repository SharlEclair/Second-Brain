import os
import pytest
from core.synthesis import (
    get_all_vault_note_titles,
    find_related_notes,
    find_unlinked_mentions,
    generate_semantic_footer,
    process_note_synthesis,
)
from api.tasks import nightly_vault_synthesis_task


def test_find_unlinked_mentions():
    content = """# Machine Learning Note
Here is some text discussing Deep Learning and Neural Networks.
We also already linked [[Deep Learning]].
Another concept is Artificial Intelligence.
"""
    all_titles = {
        "deep learning": "Deep Learning",
        "neural networks": "Neural Networks",
        "artificial intelligence": "Artificial Intelligence",
        "unrelated note": "Unrelated Note",
    }
    current_title = "Machine Learning Note"

    mentions = find_unlinked_mentions(content, current_title, all_titles)
    # Deep Learning is already linked with [[]], so only Neural Networks & Artificial Intelligence should appear
    assert "Neural Networks" in mentions
    assert "Artificial Intelligence" in mentions
    assert "Deep Learning" not in mentions
    assert "Unrelated Note" not in mentions


def test_generate_semantic_footer():
    related = ["Note A", "Note B"]
    unlinked = ["Note C"]
    footer = generate_semantic_footer(related, unlinked)

    assert "## Related Notes" in footer
    assert "* [[Note A]]" in footer
    assert "* [[Note B]]" in footer
    assert "## Suggested Links (Unlinked Mentions)" in footer
    assert "* [[Note C]]" in footer


def test_process_note_synthesis_and_idempotence(tmp_path, monkeypatch):
    # Setup test file
    test_note = tmp_path / "Quantum Computing.md"
    test_note.write_text(
        "# Quantum Computing\nDiscussing Superposition and Entanglement.\n",
        encoding="utf-8"
    )

    all_titles = {
        "superposition": "Superposition",
        "entanglement": "Entanglement",
    }

    # Mock ChromaDB related notes
    monkeypatch.setattr(
        "core.synthesis.find_related_notes",
        lambda content, current_title, top_k=3: ["Qubits", "Quantum Algorithms"]
    )

    # First run: should process and append footer
    modified = process_note_synthesis(str(test_note), all_titles=all_titles)
    assert modified is True

    content_after = test_note.read_text(encoding="utf-8")
    assert "## Related Notes" in content_after
    assert "* [[Qubits]]" in content_after
    assert "* [[Quantum Algorithms]]" in content_after
    assert "## Suggested Links (Unlinked Mentions)" in content_after
    assert "* [[Superposition]]" in content_after

    # Second run: should be skipped because '## Related Notes' already exists
    modified_second = process_note_synthesis(str(test_note), all_titles=all_titles)
    assert modified_second is False


def test_nightly_vault_synthesis_task(tmp_path, monkeypatch):
    # Create two notes in tmp_path
    note1 = tmp_path / "Note 1.md"
    note1.write_text("# Note 1\nMentioning Note 2 in text.\n", encoding="utf-8")

    note2 = tmp_path / "Note 2.md"
    note2.write_text("# Note 2\n## Related Notes\n* [[Note 1]]\n", encoding="utf-8")

    monkeypatch.setattr("core.config.PROJECT_VAULT_PATH", str(tmp_path))
    monkeypatch.setattr(
        "core.synthesis.find_related_notes",
        lambda content, current_title, top_k=3: ["Related Note X"]
    )

    result = nightly_vault_synthesis_task()
    assert result["status"] == "success"
    assert result["processed"] == 1  # note1 processed
    assert result["modified"] == 1
    assert result["skipped"] == 1    # note2 skipped because it has '## Related Notes'
