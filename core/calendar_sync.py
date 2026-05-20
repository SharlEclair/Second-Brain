import os
import datetime
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build

SCOPES = ['https://www.googleapis.com/auth/calendar.events']

def get_credentials():
    creds = None
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    token_path = os.path.join(project_root, 'token.json')
    credentials_path = os.path.join(project_root, 'credentials.json')

    if os.path.exists(token_path):
        try:
            creds = Credentials.from_authorized_user_file(token_path, SCOPES)
        except Exception as e:
            print(f"[Calendar] Error loading token.json: {e}")
            creds = None

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            try:
                creds.refresh(Request())
                with open(token_path, 'w') as token:
                    token.write(creds.to_json())
            except Exception as e:
                print(f"[Calendar] Error refreshing credentials: {e}")
                creds = None

        if not creds:
            if not os.path.exists(credentials_path):
                print("[Calendar] credentials.json not found in project root. Google Calendar sync is disabled.")
                return None
            try:
                flow = InstalledAppFlow.from_client_secrets_file(credentials_path, SCOPES)
                creds = flow.run_local_server(port=0, open_browser=False)
                with open(token_path, 'w') as token:
                    token.write(creds.to_json())
            except Exception as e:
                print(f"[Calendar] Failed to run OAuth local server: {e}")
                return None

    return creds

def create_calendar_event(title: str, event_date_str: str, source_url: str, description: str):
    """
    Parse the ISO-8601 event_date_str, calculate end time, and create a Google Calendar event.
    """
    creds = get_credentials()
    if not creds:
        print("[Calendar] Google Calendar sync skipped due to missing or invalid credentials.")
        return None

    try:
        # Parse the datetime. Example format: "2026-05-25T20:00:00"
        # We handle cases where timezone or seconds offset is included
        try:
            # Try parsing ISO format
            start_time = datetime.datetime.fromisoformat(event_date_str)
        except Exception:
            # Fallback to standard strptime
            clean_date = event_date_str.split('.')[0].rstrip('Z')
            start_time = datetime.datetime.strptime(clean_date, "%Y-%m-%dT%H:%M:%S")

        end_time = start_time + datetime.timedelta(hours=1)

        service = build('calendar', 'v3', credentials=creds)

        formatted_desc = f"\n\n---\nSource Note: {source_url}\n\n{description}"

        event = {
            'summary': title,
            'description': formatted_desc,
            'start': {
                'dateTime': start_time.isoformat(),
                'timeZone': 'UTC',
            },
            'end': {
                'dateTime': end_time.isoformat(),
                'timeZone': 'UTC',
            },
        }

        created_event = service.events().insert(calendarId='primary', body=event).execute()
        print(f"[Calendar] Event created successfully: {created_event.get('htmlLink')}")
        return created_event
    except Exception as e:
        print(f"[Calendar] Failed to create Google Calendar event: {e}")
        return None
