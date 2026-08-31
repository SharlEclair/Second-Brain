import os
import json
import requests
from fastapi import APIRouter, HTTPException
from fastapi.responses import RedirectResponse, HTMLResponse
from urllib.parse import urlencode

try:
    from core.calendar_sync import SCOPES
except ImportError:
    SCOPES = ['https://www.googleapis.com/auth/calendar']

router = APIRouter()

@router.get("/api/auth/google")
async def auth_google():
    """
    Initiates the Google OAuth2 flow by redirecting the user to Google's authorization page.
    """
    project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    credentials_path = os.path.join(project_root, 'credentials.json')
    
    if not os.path.exists(credentials_path):
        raise HTTPException(status_code=404, detail="credentials.json not found in project root.")
        
    try:
        with open(credentials_path, 'r') as f:
            creds_data = json.load(f)
        client_id = creds_data['web']['client_id']
        redirect_uri = creds_data['web']['redirect_uris'][0]
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to read credentials from credentials.json: {e}")

    try:
        auth_base_url = "https://accounts.google.com/o/oauth2/v2/auth"
        params = {
            "client_id": client_id,
            "redirect_uri": redirect_uri,
            "response_type": "code",
            "scope": " ".join(SCOPES),
            "access_type": "offline",
            "prompt": "consent"
        }
        authorization_url = f"{auth_base_url}?{urlencode(params)}"
        return RedirectResponse(url=authorization_url)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to initiate OAuth flow: {e}")

@router.get("/api/auth/callback")
async def oauth_callback(code: str, state: str = None):
    """
    Callback endpoint where Google redirects the user with authorization code.
    Exchanges authorization code for credentials and saves token.json.
    """
    project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    credentials_path = os.path.join(project_root, 'credentials.json')
    token_path = os.path.join(project_root, 'token.json')
    
    if not os.path.exists(credentials_path):
        raise HTTPException(status_code=404, detail="credentials.json not found in project root.")
        
    try:
        with open(credentials_path, 'r') as f:
            creds_data = json.load(f)
        client_id = creds_data['web']['client_id']
        client_secret = creds_data['web']['client_secret']
        redirect_uri = creds_data['web']['redirect_uris'][0]
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to read credentials from credentials.json: {e}")

    try:
        from google.oauth2.credentials import Credentials
        
        token_url = "https://oauth2.googleapis.com/token"
        payload = {
            'code': code,
            'client_id': client_id,
            'client_secret': client_secret,
            'redirect_uri': redirect_uri,
            'grant_type': 'authorization_code'
        }
        
        response = requests.post(token_url, data=payload, timeout=25)
        token_data = response.json()
        
        if 'error' in token_data:
            raise HTTPException(
                status_code=400, 
                detail=f"Google token exchange error: {token_data.get('error_description', token_data['error'])}"
            )
            
        creds = Credentials(
            token=token_data.get('access_token'),
            refresh_token=token_data.get('refresh_token'),
            token_uri=token_url,
            client_id=client_id,
            client_secret=client_secret,
            scopes=SCOPES
        )
        
        with open(token_path, 'w') as token_file:
            token_file.write(creds.to_json())
            
        html_content = """
        <html>
            <head>
                <title>Authentication Successful</title>
                <style>
                    body {
                        font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                        background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
                        color: white;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                        height: 100vh;
                        margin: 0;
                    }
                    .container {
                        text-align: center;
                        background: rgba(255, 255, 255, 0.1);
                        padding: 3rem;
                        border-radius: 15px;
                        box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.3);
                        backdrop-filter: blur(10px);
                        border: 1px solid rgba(255, 255, 255, 0.2);
                        max-width: 450px;
                    }
                    h1 {
                        margin-top: 0;
                        color: #4caf50;
                        font-size: 2.5rem;
                        margin-bottom: 1.5rem;
                    }
                    p {
                        font-size: 1.1rem;
                        line-height: 1.6;
                        margin-bottom: 2rem;
                        color: #e0e0e0;
                    }
                    .icon {
                        font-size: 4rem;
                        margin-bottom: 1rem;
                        display: inline-block;
                        animation: bounce 2s infinite;
                    }
                    @keyframes bounce {
                        0%, 100% { transform: translateY(0); }
                        50% { transform: translateY(-10px); }
                    }
                </style>
            </head>
            <body>
                <div class="container">
                    <div class="icon">📅</div>
                    <h1>Success!</h1>
                    <p>Google Calendar has been successfully authorized for your Second Brain. You can now close this tab.</p>
                </div>
            </body>
        </html>
        """
        return HTMLResponse(content=html_content, status_code=200)
    except Exception as e:
        import traceback
        tb = traceback.format_exc()
        print(f"[Calendar OAuth Error]: {tb}")
        raise HTTPException(status_code=500, detail=f"Failed to exchange authorization code: {e}")
