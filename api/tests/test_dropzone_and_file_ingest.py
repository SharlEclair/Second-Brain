import os
import io
import pytest
from fastapi.testclient import TestClient
from main import app
from core.processors import process_local_file, _sync_extract_pdf_pypdf
from api.tasks import ingest_file_task
from scripts.desktop_dropzone import upload_file_to_cortex, wait_for_file_settled

client = TestClient(app)


def test_api_ingest_file_queued(monkeypatch):
    queued_calls = []

    class MockTask:
        def delay(self, temp_path, filename, task_id):
            queued_calls.append((temp_path, filename, task_id))

    monkeypatch.setattr("api.tasks.ingest_file_task", MockTask())

    file_content = b"# Test Markdown Note\nThis is a sample document for testing dropzone file ingestion."
    response = client.post(
        "/api/ingest/file",
        files={"file": ("sample_note.md", io.BytesIO(file_content), "text/markdown")}
    )

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "queued"
    assert data["filename"] == "sample_note.md"
    assert "task_id" in data
    assert len(queued_calls) == 1
    assert queued_calls[0][1] == "sample_note.md"


def test_process_local_file_text(tmp_path, monkeypatch):
    import asyncio

    # Setup test file
    sample_file = tmp_path / "SystemDesign.md"
    sample_file.write_text("# System Design\nDiscussion of microservices and event queues.", encoding="utf-8")

    # Mock analyze text to return predictable AI metadata
    monkeypatch.setattr(
        "core.processors._sync_analyze_text",
        lambda text, title: {
            "title": "System Design Overview",
            "category": "Architecture",
            "tags": ["#system-design", "#microservices"],
            "summary": "Overview of microservices architecture.",
            "formatted_content": "Detailed breakdown of system architecture."
        }
    )

    # Set vault path to tmp_path
    monkeypatch.setattr("core.config.PROJECT_VAULT_PATH", str(tmp_path / "vault"))
    monkeypatch.setattr("core.config.OBSIDIAN_INBOX_PATH", str(tmp_path / "obsidian"))

    result = asyncio.run(process_local_file(str(sample_file), "SystemDesign.md", task_id="test_task_123"))
    assert result["status"] == "success"
    assert result["note"]["category"] == "Architecture"
    assert result["note"]["type"] == "text-document"

    # Verify markdown file was written to category directory
    created_note = tmp_path / "vault" / "Architecture"
    assert created_note.exists()
    md_files = list(created_note.glob("*.md"))
    assert len(md_files) == 1
    content = md_files[0].read_text(encoding="utf-8")
    assert "type: text-document" in content
    assert "# Architecture - System Design Overview" in content



def test_ingest_file_task_execution_and_cleanup(tmp_path, monkeypatch):
    temp_file = tmp_path / "temp_drop.txt"
    temp_file.write_text("Hello from dropzone text file.", encoding="utf-8")

    # Mock process_local_file
    async def mock_process(path, fn, tid):
        return {"status": "success"}

    monkeypatch.setattr("core.processors.process_local_file", mock_process)

    result = ingest_file_task(str(temp_file), "temp_drop.txt", "task_cleanup_test")
    assert result["status"] == "success"
    # Ensure temporary file was removed in finally block
    assert not temp_file.exists()


def test_dropzone_upload_flow(tmp_path, monkeypatch):
    drop_file = tmp_path / "SampleDoc.pdf"
    drop_file.write_bytes(b"%PDF-1.4 Mock PDF Content")

    processed_dir = tmp_path / "Processed"
    monkeypatch.setattr("scripts.desktop_dropzone.PROCESSED_DIR", str(processed_dir))
    monkeypatch.setattr("scripts.desktop_dropzone.API_ENDPOINT", "http://mock-cortex/api/ingest/file")

    class MockResponse:
        status_code = 200
        def json(self):
            return {"status": "queued", "task_id": "task_abc123"}

    monkeypatch.setattr("requests.post", lambda url, files, timeout: MockResponse())

    upload_file_to_cortex(str(drop_file))

    # Verify original file was archived into Processed/
    assert not drop_file.exists()
    archived_file = processed_dir / "SampleDoc.pdf"
    assert archived_file.exists()
