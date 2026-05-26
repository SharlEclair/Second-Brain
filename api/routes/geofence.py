from fastapi import APIRouter, HTTPException
from core.state import get_url_index
from api.utils.markdown_parser import is_location_hidden
import math

router = APIRouter()

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate the great-circle distance between two points on Earth (in km)."""
    R = 6371.0  # Earth's radius in km
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat / 2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon / 2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

@router.get("/api/geofences")
async def get_geofences():
    index = get_url_index()
    spots = []
    for url, note in index.items():
        if not isinstance(note, dict):
            continue
        category = note.get("category")
        filename = note.get("fileName", "")
        if category == "Spot to Visit" or "Spot to Visit" in filename:
            locations = note.get("locations")
            if not isinstance(locations, list):
                locations = []
            if not locations:
                lat = note.get("latitude")
                lng = note.get("longitude")
                if lat is not None and lng is not None:
                    locations = [{"name": note.get("title") or "Unknown Spot", "lat": lat, "lng": lng}]
            
            hidden_locations = note.get("hidden_locations", [])
            if not isinstance(hidden_locations, list):
                hidden_locations = []
                
            for loc in locations:
                if not isinstance(loc, dict):
                    continue
                loc_name = loc.get("name")
                loc_lat = loc.get("lat")
                loc_lng = loc.get("lng")
                if loc_lat is not None and loc_lng is not None:
                    try:
                        loc_lat_f = float(loc_lat)
                        loc_lng_f = float(loc_lng)
                        if is_location_hidden(loc_name, loc_lat_f, loc_lng_f, hidden_locations):
                            continue
                        spots.append({
                            "title": loc_name or note.get("title"),
                            "fileName": filename,
                            "latitude": loc_lat_f,
                            "longitude": loc_lng_f,
                        })
                    except (ValueError, TypeError):
                        pass
    return spots

@router.get("/api/nearby")
async def get_nearby(lat: float, lng: float, radius: float = None, radius_km: float = None):
    try:
        limit_radius = 5.0
        if radius_km is not None:
            limit_radius = radius_km
        elif radius is not None:
            limit_radius = radius

        index = get_url_index()
        nearby = []
        seen = set()
        for url, note in index.items():
            if not isinstance(note, dict):
                continue
            
            locations = note.get("locations")
            if not isinstance(locations, list):
                locations = []
            if not locations:
                note_lat = note.get("latitude")
                note_lng = note.get("longitude")
                if note_lat is not None and note_lng is not None:
                    locations = [{"name": note.get("title") or "Unknown Spot", "lat": note_lat, "lng": note_lng}]
                    
            hidden_locations = note.get("hidden_locations", [])
            if not isinstance(hidden_locations, list):
                hidden_locations = []
                
            for loc in locations:
                if not isinstance(loc, dict):
                    continue
                loc_name = loc.get("name")
                loc_lat = loc.get("lat")
                loc_lng = loc.get("lng")
                if loc_lat is not None and loc_lng is not None:
                    try:
                        loc_lat_f = float(loc_lat)
                        loc_lng_f = float(loc_lng)
                        
                        loc_id = (loc_name, loc_lat_f, loc_lng_f, url)
                        if loc_id in seen:
                            continue
                        seen.add(loc_id)
                        
                        if is_location_hidden(loc_name, loc_lat_f, loc_lng_f, hidden_locations):
                            continue
                            
                        dist = haversine_distance(lat, lng, loc_lat_f, loc_lng_f)
                        if dist <= limit_radius:
                            nearby.append({
                                "place_name": loc_name,
                                "type": note.get("category") or note.get("type") or "Spot to Visit",
                                "distance": dist,
                                "distance_km": round(dist, 3),
                                "source_note": note.get("fileName") or note.get("title") or "Unknown Note",
                                "latitude": loc_lat_f,
                                "longitude": loc_lng_f,
                                "url": url,
                                "note_title": note.get("title"),
                                "category": note.get("category"),
                            })
                    except (ValueError, TypeError):
                        pass
        nearby.sort(key=lambda x: x["distance_km"])
        return nearby
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
