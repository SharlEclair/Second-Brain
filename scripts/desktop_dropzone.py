"""
scripts/desktop_dropzone.py — Desktop Dropzone daemon for automatic file ingestion into Cortex.

Monitors ~/Desktop/CortexDrop using watchdog. When files (PDFs, Markdown, Text, Images, Audio)
are dragged and dropped into the folder, it automatically uploads them to POST /api/ingest/file
and archives processed files into ~/Desktop/CortexDrop/Processed/.
"""
import os
import sys
import time
import shutil
import datetime
import requests
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# Default configuration
DROPZONE_DIR = os.path.join(os.path.expanduser("~"), "Desktop", "CortexDrop")
PROCESSED_DIR = os.path.join(DROPZONE_DIR, "Processed")
API_ENDPOINT = os.getenv("CORTEX_API_URL", "http://localhost:8000/api/ingest/file")

# Supported file extensions
VALID_EXTENSIONS = {
    ".pdf", ".txt", ".md", ".markdown",
    ".jpg", ".jpeg", ".png", ".webp",
    ".mp3", ".wav", ".m4a", ".ogg", ".aac"
}

# Colors for terminal output
COLOR_BLUE = "\033[94m"
COLOR_GREEN = "\033[92m"
COLOR_YELLOW = "\033[93m"
COLOR_RED = "\033[91m"
COLOR_CYAN = "\033[96m"
COLOR_RESET = "\033[0m"


def log_info(msg: str):
    ts = datetime.datetime.now().strftime("%H:%M:%S")
    print(f"{COLOR_CYAN}[{ts}]{COLOR_RESET} {msg}", flush=True)


def log_success(msg: str):
    ts = datetime.datetime.now().strftime("%H:%M:%S")
    print(f"{COLOR_GREEN}[{ts}] ✓ {msg}{COLOR_RESET}", flush=True)


def log_warn(msg: str):
    ts = datetime.datetime.now().strftime("%H:%M:%S")
    print(f"{COLOR_YELLOW}[{ts}] ⚠ {msg}{COLOR_RESET}", flush=True)


def log_error(msg: str):
    ts = datetime.datetime.now().strftime("%H:%M:%S")
    print(f"{COLOR_RED}[{ts}] ✗ {msg}{COLOR_RESET}", flush=True)


def wait_for_file_settled(filepath: str, max_retries: int = 10, delay: float = 0.5) -> bool:
    """Waits until file copy/write is finished and file is accessible."""
    prev_size = -1
    for _ in range(max_retries):
        if not os.path.exists(filepath):
            return False
        try:
            curr_size = os.path.getsize(filepath)
            if curr_size > 0 and curr_size == prev_size:
                with open(filepath, "rb"):
                    return True
            prev_size = curr_size
        except (PermissionError, OSError):
            pass
        time.sleep(delay)
    return os.path.exists(filepath) and os.path.getsize(filepath) > 0


def upload_file_to_cortex(filepath: str):
    filename = os.path.basename(filepath)
    ext = os.path.splitext(filename)[1].lower()

    if ext not in VALID_EXTENSIONS:
        log_warn(f"Skipping unsupported file: {filename}")
        return

    log_info(f"Detected new drop: {COLOR_YELLOW}{filename}{COLOR_RESET}")

    # Wait for OS write operation to settle
    time.sleep(1.0)
    if not wait_for_file_settled(filepath):
        log_error(f"File {filename} could not be read or is still locked by OS.")
        return

    log_info(f"Uploading {filename} to Cortex backend ({API_ENDPOINT})...")
    try:
        with open(filepath, "rb") as f:
            files = {"file": (filename, f, "application/octet-stream")}
            response = requests.post(API_ENDPOINT, files=files, timeout=30)

        if response.status_code == 200:
            data = response.json()
            task_id = data.get("task_id", "N/A")
            log_success(f"Successfully queued {filename} for ingestion! Task ID: {task_id}")

            # Archive file to Processed folder
            os.makedirs(PROCESSED_DIR, exist_ok=True)
            dest_path = os.path.join(PROCESSED_DIR, filename)

            # Collision resolution in Processed/
            if os.path.exists(dest_path):
                stem, fext = os.path.splitext(filename)
                dest_path = os.path.join(PROCESSED_DIR, f"{stem}_{int(time.time())}{fext}")

            shutil.move(filepath, dest_path)
            log_info(f"Moved {filename} -> Processed/{os.path.basename(dest_path)}")
        else:
            log_error(f"Upload failed ({response.status_code}): {response.text}")
    except requests.exceptions.ConnectionError:
        log_error(f"Cannot connect to Cortex API at {API_ENDPOINT}. Is the backend running?")
    except Exception as e:
        log_error(f"Unexpected error during upload: {e}")


class DropzoneHandler(FileSystemEventHandler):
    def on_created(self, event):
        if event.is_directory:
            return

        filepath = event.src_path
        # Ignore files created inside Processed directory
        if os.path.commonpath([PROCESSED_DIR, filepath]) == PROCESSED_DIR:
            return

        # Ignore temporary and hidden files
        filename = os.path.basename(filepath)
        if filename.startswith((".", "~$", "tmp_")) or filename.endswith(".tmp") or filename.endswith(".crdownload"):
            return

        upload_file_to_cortex(filepath)


def main():
    try:
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stderr.reconfigure(encoding='utf-8')
    except AttributeError:
        pass

    os.makedirs(DROPZONE_DIR, exist_ok=True)
    os.makedirs(PROCESSED_DIR, exist_ok=True)

    print(f"{COLOR_CYAN}====================================================={COLOR_RESET}")
    print(f"{COLOR_CYAN}          CORTEX DESKTOP DROPZONE DAEMON             {COLOR_RESET}")
    print(f"{COLOR_CYAN}====================================================={COLOR_RESET}")
    log_info(f"Monitoring Dropzone folder: {COLOR_GREEN}{DROPZONE_DIR}{COLOR_RESET}")
    log_info(f"Processed files archive:   {COLOR_GREEN}{PROCESSED_DIR}{COLOR_RESET}")
    log_info(f"Target API Endpoint:       {COLOR_GREEN}{API_ENDPOINT}{COLOR_RESET}")
    log_info("Drag and drop any PDF, Text, Markdown, Image, or Audio file into CortexDrop.")
    print(f"{COLOR_CYAN}-----------------------------------------------------{COLOR_RESET}")

    event_handler = DropzoneHandler()
    observer = Observer()
    observer.schedule(event_handler, path=DROPZONE_DIR, recursive=False)
    observer.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        log_info("Stopping Dropzone observer...")
        observer.stop()
    observer.join()
    log_info("Dropzone daemon stopped cleanly.")


if __name__ == "__main__":
    main()
