import os
from dotenv import load_dotenv

load_dotenv()

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
GOOGLE_MAPS_API_KEY = os.getenv("Maps_API_KEY") or os.getenv("GOOGLE_MAPS_API_KEY")
OBSIDIAN_INBOX_PATH = os.getenv("OBSIDIAN_VAULT_PATH") or os.getenv("OBSIDIAN_INBOX_PATH") or "./vault"
URL_INDEX_FILE = "url_index.json"
TAGS_FILE = "tags.txt"
PROJECT_VAULT_PATH = os.getenv("PROJECT_VAULT_PATH") or "vault"

# Neo4j Graph Database Configuration
NEO4J_URI = os.getenv("NEO4J_URI", "bolt://localhost:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "cortexpassword123")


# AI Configuration
AI_MODEL_PRIMARY = "models/gemini-2.5-flash-lite"
AI_MODEL_FALLBACK = "models/gemini-2.5-flash"
AI_MODEL_CHAIN = [AI_MODEL_PRIMARY, AI_MODEL_FALLBACK]

# Backwards-compatible alias used by older code paths and the config endpoint.
AI_MODEL = AI_MODEL_PRIMARY

# Load tags
TAGS_LIST = []
if os.path.exists(TAGS_FILE):
    try:
        with open(TAGS_FILE, "r", encoding="utf-8") as f:
            TAGS_LIST = [line.strip() for line in f if line.strip()]
    except Exception as e:
        print(f"Error loading tags.txt: {e}")

# Ensure folders exist
os.makedirs(OBSIDIAN_INBOX_PATH, exist_ok=True)
os.makedirs(PROJECT_VAULT_PATH, exist_ok=True)
