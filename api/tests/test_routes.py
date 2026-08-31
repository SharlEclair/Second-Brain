import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_health_check():
    """Verify that the API health endpoint works."""
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

def test_root():
    """Verify the root endpoint is online and provides API details."""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert "Second Brain API is Online" in data.get("message", "")
    assert data.get("docs") == "/docs"

def test_get_notes(monkeypatch):
    """Test retrieving notes and verify mocks operate correctly."""
    # Mock the index database call in notes router
    monkeypatch.setattr("api.routes.notes.get_url_index", lambda: {
        "https://example.com/test": {
            "title": "Test Note",
            "fileName": "Test Note.md",
            "date": "2026-05-26"
        }
    })
    
    response = client.get("/api/notes")
    assert response.status_code == 200
    notes_list = response.json()
    assert len(notes_list) == 1
    assert notes_list[0]["title"] == "Test Note"
    assert notes_list[0]["fileName"] == "Test Note.md"

def test_celery_ingest_mocked(monkeypatch):
    """Verify enqueuing a task triggers Celery correctly when mocked."""
    # Mock Celery delay method to prevent enqueuing into real Redis broker
    called = []
    
    class MockTask:
        def delay(self, url, task_id):
            called.append((url, task_id))
            
    monkeypatch.setattr("api.tasks.ingest_url_task", MockTask())
    
    # Trigger the ingest post
    response = client.post(
        "/api/ingest",
        json={"url": "https://example.com/mock-task-test"},
        headers={"X-Queue": "true"}
    )
    
    assert response.status_code == 200
    assert response.json()["status"] == "queued"
    assert len(called) == 1
    assert called[0][0] == "https://example.com/mock-task-test"


def test_sync_vault_no_git(monkeypatch):
    """Test sync fails with 400 when .git folder does not exist."""
    monkeypatch.setattr("os.path.exists", lambda path: False if ".git" in str(path) else True)
    response = client.post("/api/sync")
    assert response.status_code == 400
    assert "Vault is not initialized as a Git repository" in response.json()["detail"]


def test_sync_vault_success(monkeypatch):
    """Test sync succeeds with 200 when git operations succeed."""
    monkeypatch.setattr("os.path.exists", lambda path: True)
    import subprocess
    def mock_run(args, **kwargs):
        class MockCompletedProcess:
            stdout = "Everything up-to-date"
            stderr = ""
            returncode = 0
        return MockCompletedProcess()
    monkeypatch.setattr("subprocess.run", mock_run)
    response = client.post("/api/sync")
    assert response.status_code == 200
    assert response.json()["status"] == "success"


def test_sync_vault_failure(monkeypatch):
    """Test sync returns 500 when git push raises CalledProcessError."""
    monkeypatch.setattr("os.path.exists", lambda path: True)
    import subprocess
    def mock_run(args, **kwargs):
        if "push" in args:
            raise subprocess.CalledProcessError(
                returncode=1,
                cmd=args,
                stderr="fatal: remote error: authentication failed"
            )
        class MockCompletedProcess:
            stdout = ""
            stderr = ""
            returncode = 0
        return MockCompletedProcess()
    monkeypatch.setattr("subprocess.run", mock_run)
    response = client.post("/api/sync")
    assert response.status_code == 500
    assert "authentication failed" in response.json()["detail"]

