import os
import json
from fastapi import APIRouter, HTTPException
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel
from core.state import get_url_index, save_url_index
from core.config import OBSIDIAN_INBOX_PATH, PROJECT_VAULT_PATH
from api.utils.markdown_parser import update_markdown_frontmatter_fields, update_markdown_frontmatter_coordinates

router = APIRouter()

class LocationOverrideRequest(BaseModel):
    latitude: float
    longitude: float

class HideLocationRequest(BaseModel):
    name: str = None
    lat: float = None
    lng: float = None

@router.get("/api/notes")
async def get_notes():
    index = get_url_index()
    notes = []
    for url, data in index.items():
        if isinstance(data, dict):
            notes.append(data)
        else:
            notes.append({"title": data.replace(".md", ""), "fileName": data, "date": "Unknown"})
    return sorted(notes, key=lambda x: x.get('date', ''), reverse=True)

@router.get("/api/notes/{filename:path}")
async def get_note_content(filename: str):
    paths = [os.path.join(OBSIDIAN_INBOX_PATH, filename), os.path.join(PROJECT_VAULT_PATH, filename)]
    for p in paths:
        if os.path.exists(p):
            with open(p, "r", encoding="utf-8") as f:
                return PlainTextResponse(f.read(), media_type="text/markdown")
    raise HTTPException(status_code=404, detail="Note not found")

@router.patch("/api/notes/{filename:path}/hide_location")
async def hide_note_location(filename: str, request: HideLocationRequest):
    normalized_filename = filename.replace("\\", "/")
    
    paths = [os.path.join(OBSIDIAN_INBOX_PATH, filename), os.path.join(PROJECT_VAULT_PATH, filename)]
    updated_files = 0
    
    new_hidden_item = None
    if request.name:
        new_hidden_item = request.name
    elif request.lat is not None and request.lng is not None:
        new_hidden_item = {"lat": request.lat, "lng": request.lng}
    else:
        raise HTTPException(status_code=400, detail="Must provide name or coordinates to hide a location")
        
    for p in paths:
        if os.path.exists(p):
            try:
                import re
                current_hidden = []
                with open(p, "r", encoding="utf-8") as f:
                    content = f.read()
                frontmatter_pattern = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)
                match = frontmatter_pattern.match(content)
                if match:
                    lines = match.group(1).splitlines()
                    for line in lines:
                        if line.strip().startswith("hidden_locations:"):
                            val_part = line.split(":", 1)[1].strip()
                            try:
                                current_hidden = json.loads(val_part)
                            except:
                                pass
                
                is_duplicate = False
                for item in current_hidden:
                    if isinstance(item, str) and isinstance(new_hidden_item, str):
                        if item.lower() == new_hidden_item.lower():
                            is_duplicate = True
                            break
                    elif isinstance(item, dict) and isinstance(new_hidden_item, dict):
                        item_lat = item.get("lat") or item.get("latitude")
                        item_lng = item.get("lng") or item.get("longitude")
                        new_lat = new_hidden_item.get("lat")
                        new_lng = new_hidden_item.get("lng")
                        if item_lat is not None and item_lng is not None and new_lat is not None and new_lng is not None:
                            if abs(float(item_lat) - float(new_lat)) < 0.0001 and abs(float(item_lng) - float(new_lng)) < 0.0001:
                                is_duplicate = True
                                break
                                
                if not is_duplicate:
                    current_hidden.append(new_hidden_item)
                    
                if update_markdown_frontmatter_fields(p, {"hidden_locations": current_hidden}):
                    updated_files += 1
            except Exception as e:
                print(f"Error updating hidden locations for {p}: {e}")
                
    if updated_files == 0:
        raise HTTPException(status_code=404, detail="Note file not found on disk")
        
    index = get_url_index()
    found_in_index = False
    for url, note_data in index.items():
        if isinstance(note_data, dict):
            fn = note_data.get("fileName")
            if fn and fn.replace("\\", "/") == normalized_filename:
                curr_hidden = note_data.get("hidden_locations", [])
                if not isinstance(curr_hidden, list):
                    curr_hidden = []
                
                is_duplicate = False
                for item in curr_hidden:
                    if isinstance(item, str) and isinstance(new_hidden_item, str):
                        if item.lower() == new_hidden_item.lower():
                            is_duplicate = True
                            break
                    elif isinstance(item, dict) and isinstance(new_hidden_item, dict):
                        item_lat = item.get("lat") or item.get("latitude")
                        item_lng = item.get("lng") or item.get("longitude")
                        new_lat = new_hidden_item.get("lat")
                        new_lng = new_hidden_item.get("lng")
                        if item_lat is not None and item_lng is not None and new_lat is not None and new_lng is not None:
                            if abs(float(item_lat) - float(new_lat)) < 0.0001 and abs(float(item_lng) - float(new_lng)) < 0.0001:
                                is_duplicate = True
                                break
                if not is_duplicate:
                    curr_hidden.append(new_hidden_item)
                
                note_data["hidden_locations"] = curr_hidden
                found_in_index = True
                break
                
    if found_in_index:
        save_url_index(index)
        
    return {"status": "success", "message": f"Added hidden location in {updated_files} file(s) and index."}

@router.patch("/api/notes/{filename:path}/location")
async def update_note_location(filename: str, request: LocationOverrideRequest):
    normalized_filename = filename.replace("\\", "/")
    
    paths = [os.path.join(OBSIDIAN_INBOX_PATH, filename), os.path.join(PROJECT_VAULT_PATH, filename)]
    updated_files = 0
    for p in paths:
        if os.path.exists(p):
            try:
                if update_markdown_frontmatter_coordinates(p, request.latitude, request.longitude):
                    updated_files += 1
            except Exception as e:
                print(f"Error updating file frontmatter for {p}: {e}")
                
    if updated_files == 0:
        raise HTTPException(status_code=404, detail="Note file not found on disk")
        
    index = get_url_index()
    found_in_index = False
    for url, note_data in index.items():
        if isinstance(note_data, dict):
            fn = note_data.get("fileName")
            if fn and fn.replace("\\", "/") == normalized_filename:
                note_data["latitude"] = request.latitude
                note_data["longitude"] = request.longitude
                found_in_index = True
                break
                
    if found_in_index:
        save_url_index(index)
        
    return {"status": "success", "message": f"Updated coordinates in {updated_files} file(s) and index."}
