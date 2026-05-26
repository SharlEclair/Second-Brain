"""
Serendipity notification logic — standalone module importable by Celery workers.
Selects random notes for daily rediscovery and sends FCM push notifications.
"""
import os
import re
import json
import random
import datetime

from core.config import OBSIDIAN_INBOX_PATH, PROJECT_VAULT_PATH
from core.state import get_url_index


def _get_serendipity_picks(max_results: int = 3) -> list:
    """Select serendipity notes: urgent events first, then random from least-reviewed."""
    index = get_url_index()
    all_notes = []
    urgent_event_notes = []
    now = datetime.datetime.now()

    for url, data in index.items():
        if not isinstance(data, dict):
            continue
        date_str = data.get("date")
        if date_str:
            try:
                dt = datetime.datetime.fromisoformat(date_str.replace("Z", "+00:00"))
            except Exception:
                dt = now
        else:
            dt = now

        note_entry = {
            "url": url,
            "title": data.get("title", ""),
            "fileName": data.get("fileName", ""),
            "date": date_str,
            "last_reviewed": data.get("last_reviewed"),
            "category": data.get("category"),
            "event_date": data.get("event_date"),
            "dt": dt,
        }
        all_notes.append(note_entry)

        # Check for urgent event notes (event_date within 7 days)
        if data.get("category") == "Event" and data.get("event_date"):
            try:
                evt_dt = datetime.datetime.fromisoformat(
                    str(data["event_date"]).replace("Z", "+00:00")
                ).replace(tzinfo=None)
                days_away = (evt_dt.date() - now.date()).days
                if 0 <= days_away <= 7:
                    urgent_event_notes.append(note_entry)
            except Exception:
                pass

    if not all_notes:
        return []

    # Urgent events first, then fill remaining slots randomly
    selected = []
    urgent_urls = set()
    for note in urgent_event_notes[:max_results]:
        selected.append(note)
        urgent_urls.add(note["url"])

    remaining_slots = max_results - len(selected)
    if remaining_slots > 0:
        def sort_key(note):
            last_rev = note["last_reviewed"]
            has_rev = 1 if last_rev else 0
            rev_time = last_rev if last_rev else ""
            return (has_rev, rev_time, note["date"])

        pool_candidates = [n for n in all_notes if n["url"] not in urgent_urls]
        sorted_notes = sorted(pool_candidates, key=sort_key)
        pool = sorted_notes[: min(15, len(sorted_notes))]
        random_picks = random.sample(pool, min(remaining_slots, len(pool)))
        selected.extend(random_picks)

    # Enrich with summary from the note file
    results = []
    for note in selected:
        summary = ""
        filename = note["fileName"]
        for base in [OBSIDIAN_INBOX_PATH, PROJECT_VAULT_PATH]:
            p = os.path.join(base, filename)
            if os.path.exists(p):
                try:
                    with open(p, "r", encoding="utf-8") as f:
                        content = f.read()
                    match = re.search(r'> \*\*AI Summary:\*\* (.*)', content)
                    if match:
                        summary = match.group(1).strip()
                    else:
                        match_body = re.search(r'# .*\n\n> (.*)', content)
                        if match_body:
                            summary = match_body.group(1).strip()
                except Exception:
                    pass
                break

        results.append({
            "url": note["url"],
            "title": note["title"],
            "fileName": filename,
            "date": note["date"],
            "last_reviewed": note["last_reviewed"],
            "summary": summary,
            "category": note.get("category"),
            "event_date": note.get("event_date"),
        })

    return results


async def send_serendipity_notifications():
    """
    Select serendipity notes and send FCM push notifications to registered devices.
    Called by the daily Celery Beat task.
    """
    picks = _get_serendipity_picks()
    if not picks:
        print("[Serendipity] No notes available for serendipity picks.")
        return

    # Build notification body
    titles = [p["title"] for p in picks if p.get("title")]
    body = "Rediscover: " + ", ".join(titles[:3]) if titles else "Check your knowledge vault!"

    # Attempt to send FCM notification
    try:
        import firebase_admin
        from firebase_admin import messaging

        # Check if Firebase is initialised (it's initialised in main.py at startup)
        if not firebase_admin._apps:
            # Try to initialise if credentials exist
            from firebase_admin import credentials
            cred_path = "firebase_credentials.json"
            if os.path.exists(cred_path):
                cred = credentials.Certificate(cred_path)
                firebase_admin.initialize_app(cred)
            else:
                print("[Serendipity] Firebase credentials not found. Skipping push notification.")
                return

        # Load stored device tokens
        tokens_file = "device_tokens.json"
        if not os.path.exists(tokens_file):
            print("[Serendipity] No device tokens registered. Skipping push notification.")
            return

        with open(tokens_file, "r") as f:
            tokens_data = json.load(f)

        device_tokens = []
        if isinstance(tokens_data, list):
            for t in tokens_data:
                token = t.get("token") if isinstance(t, dict) else t
                if token:
                    device_tokens.append(token)
        elif isinstance(tokens_data, dict):
            token = tokens_data.get("token")
            if token:
                device_tokens.append(token)

        if not device_tokens:
            print("[Serendipity] No valid device tokens found. Skipping push notification.")
            return

        # Send to each registered device
        notification = messaging.Notification(
            title="🧠 Daily Serendipity",
            body=body,
        )
        data_payload = {
            "type": "serendipity",
            "picks": json.dumps(picks, default=str),
        }

        for token in device_tokens:
            try:
                message = messaging.Message(
                    notification=notification,
                    data=data_payload,
                    token=token,
                )
                messaging.send(message)
            except Exception as e:
                print(f"[Serendipity] Failed to send to token {token[:20]}...: {e}")

        print(f"[Serendipity] Sent daily serendipity to {len(device_tokens)} device(s).")

    except ImportError:
        print("[Serendipity] firebase-admin not installed. Skipping push notification.")
    except Exception as e:
        print(f"[Serendipity] Error sending notifications: {e}")
