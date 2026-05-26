import time
import json
import os
import urllib.request
import urllib.error
from datetime import datetime

# Configurations
PUBLIC_URL = "https://tissue-dogs-ours-legislative.trycloudflare.com/api/health"
LOCAL_API_URL = "http://127.0.0.1:8000/api/health"
CHECK_INTERVAL_SECONDS = 30
LOG_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ngrok_monitor.log")

def log_message(message: str):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    formatted_log = f"[{timestamp}] {message}"
    print(formatted_log)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(formatted_log + "\n")

def check_url(url: str, timeout: int = 10) -> tuple[bool, str]:
    """
    Checks if a URL is reachable.
    Returns (is_accessible, status_description)
    """
    try:
        req = urllib.request.Request(
            url,
            headers={
                "User-Agent": "Tunnel-Monitor-Script/1.0"
            }
        )
        with urllib.request.urlopen(req, timeout=timeout) as response:
            status = response.getcode()
            if status == 200:
                return True, "HTTP 200"
            return False, f"HTTP {status}"
    except urllib.error.HTTPError as e:
        return False, f"HTTP Error {e.code}: {e.reason}"
    except urllib.error.URLError as e:
        return False, f"Network Error: {e.reason}"
    except Exception as e:
        return False, f"Unexpected Error: {str(e)}"

def monitor():
    log_message(f"Starting Tunnel Monitor. Logging to: {LOG_FILE}")
    log_message(f"Monitoring Local Backend API: {LOCAL_API_URL}")
    log_message(f"Monitoring Public Cloudflare Tunnel: {PUBLIC_URL}")

    last_local_status = None
    last_public_status = None

    while True:
        # 1. Check local backend API
        local_ok, local_desc = check_url(LOCAL_API_URL)
        
        # 2. Check public Cloudflare tunnel
        public_ok, public_desc = check_url(PUBLIC_URL)

        # Handle local status changes
        if local_ok != last_local_status:
            if last_local_status is not None:
                status_str = "ONLINE" if local_ok else "OFFLINE"
                log_message(f"[STATUS CHANGE] Local Backend is now {status_str} ({local_desc})")
            elif not local_ok:
                log_message(f"[ALERT] Local Backend is starting OFFLINE ({local_desc})")
            last_local_status = local_ok

        # Handle public status changes
        if public_ok != last_public_status:
            if last_public_status is not None:
                status_str = "ONLINE" if public_ok else "OFFLINE"
                log_message(f"[STATUS CHANGE] Public Cloudflare Tunnel is now {status_str} ({public_desc})")
            elif not public_ok:
                log_message(f"[ALERT] Public Cloudflare Tunnel is starting OFFLINE ({public_desc})")
            last_public_status = public_ok

        # Log periodic errors if any component is offline
        if not local_ok:
            log_message(f"[ERROR] Local Backend API is inaccessible: {local_desc}")
        if local_ok and not public_ok:
            log_message(f"[ERROR] Public Cloudflare Tunnel is inaccessible while Local Backend is running: {public_desc}")

        time.sleep(CHECK_INTERVAL_SECONDS)

if __name__ == "__main__":
    try:
        monitor()
    except KeyboardInterrupt:
        log_message("Monitoring stopped by user.")
