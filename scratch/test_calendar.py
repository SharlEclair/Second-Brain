import os
import sys

# Ensure project root is in path
project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(project_root)

from core.calendar_sync import create_calendar_event, get_credentials

def main():
    print("=== Google Calendar Integration Verification ===")
    credentials_path = os.path.join(project_root, 'credentials.json')
    token_path = os.path.join(project_root, 'token.json')

    print(f"Project root: {project_root}")
    print(f"Looking for credentials.json at: {credentials_path}")
    
    if not os.path.exists(credentials_path):
        print("\n[!] WARNING: credentials.json is missing in the project root!")
        print("To enable Google Calendar integration, follow these steps:")
        print("1. Go to Google Cloud Console (https://console.cloud.google.com).")
        print("2. Create a project and search for/enable 'Google Calendar API'.")
        print("3. Navigate to 'APIs & Services' -> 'Credentials'.")
        print("4. Click '+ Create Credentials' -> 'OAuth client ID'.")
        print("5. Choose Application Type: 'Desktop App', name it, and click 'Create'.")
        print("6. Download the JSON credentials file and rename/save it to project root as 'credentials.json'.")
        print("7. Run this script again to perform the OAuth authentication flow.")
        return

    print("[OK] Found credentials.json. Attempting authentication flow...")
    creds = get_credentials()
    
    if creds:
        print("[OK] Authentication successful!")
        if os.path.exists(token_path):
            print(f"[OK] token.json saved successfully at: {token_path}")
        
        print("\nAttempting to create a test event on your calendar...")
        import datetime
        test_title = f"Second-Brain Integration Test ({datetime.datetime.now().strftime('%Y-%m-%d %H:%M')})"
        event_date = (datetime.datetime.now() + datetime.timedelta(days=1)).strftime("%Y-%m-%dT10:00:00")
        
        event = create_calendar_event(
            title=test_title,
            event_date_str=event_date,
            source_url="http://localhost:8000/api/notes/test-event.md",
            description="This is a test event created automatically by the Second-Brain Google Calendar integration script."
        )
        
        if event:
            print(f"\n[SUCCESS]: Calendar event created successfully!")
            print(f"Event Link: {event.get('htmlLink')}")
        else:
            print("\n[FAILURE]: Could not create calendar event. Check API console logs/permissions.")
    else:
        print("\n[X] FAILURE: Authentication failed. Please check the terminal/consent screen steps.")

if __name__ == "__main__":
    main()
