import os
import re
import json

def extract_summary_from_md(filepath):
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()
        match = re.search(r'> \*\*AI Summary:\*\* (.*)', content)
        if match:
            return match.group(1).strip()
        body = content
        if content.startswith("---\n"):
            end_idx = content.find("\n---\n", 4)
            if end_idx != -1:
                body = content[end_idx+5:]
        
        lines = [l.strip() for l in body.split("\n") if l.strip() and not l.strip().startswith("#") and not l.strip().startswith(">")]
        if lines:
            summary = lines[0]
            if len(summary) > 100:
                summary = summary[:97] + "..."
            return summary
    except Exception:
        pass
    return "No summary available."

def is_location_hidden(loc_name: str, loc_lat: float, loc_lng: float, hidden_locations: list) -> bool:
    if not hidden_locations:
        return False
    for hl in hidden_locations:
        if isinstance(hl, str):
            if loc_name and hl.strip().lower() == loc_name.strip().lower():
                return True
        elif isinstance(hl, dict):
            hl_lat = hl.get("lat") or hl.get("latitude")
            hl_lng = hl.get("lng") or hl.get("longitude")
            if hl_lat is not None and hl_lng is not None:
                if abs(float(hl_lat) - loc_lat) < 0.0001 and abs(float(hl_lng) - loc_lng) < 0.0001:
                    return True
            hl_name = hl.get("name")
            if hl_name and loc_name and hl_name.strip().lower() == loc_name.strip().lower():
                return True
    return False

def update_markdown_frontmatter_coordinates(filepath: str, lat: float, lng: float):
    if not os.path.exists(filepath):
        return False
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
        
    frontmatter_pattern = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)
    match = frontmatter_pattern.match(content)
    
    if match:
        frontmatter_text = match.group(1)
        remaining_content = content[match.end():]
        
        lines = frontmatter_text.splitlines()
        new_lines = []
        lat_found = False
        lng_found = False
        
        for line in lines:
            if line.strip().startswith("latitude:"):
                new_lines.append(f"latitude: {lat}")
                lat_found = True
            elif line.strip().startswith("longitude:"):
                new_lines.append(f"longitude: {lng}")
                lng_found = True
            else:
                new_lines.append(line)
                
        if not lat_found:
            new_lines.append(f"latitude: {lat}")
        if not lng_found:
            new_lines.append(f"longitude: {lng}")
            
        new_frontmatter = "\n".join(new_lines)
        new_content = f"---\n{new_frontmatter}\n---\n{remaining_content}"
    else:
        new_content = f"---\nlatitude: {lat}\nlongitude: {lng}\n---\n{content}"

    with open(filepath, "w", encoding="utf-8") as f:
        f.write(new_content)
    return True

def update_markdown_frontmatter_fields(filepath: str, updates: dict) -> bool:
    if not os.path.exists(filepath):
        return False
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
        
    frontmatter_pattern = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)
    match = frontmatter_pattern.match(content)
    
    if match:
        frontmatter_text = match.group(1)
        remaining_content = content[match.end():]
        
        lines = frontmatter_text.splitlines()
        new_lines = []
        
        skip_mode = False
        for line in lines:
            stripped = line.strip()
            matched_key = None
            for key in updates.keys():
                if line.startswith(f"{key}:") or line.startswith(f"{key} :"):
                    matched_key = key
                    break
            
            if matched_key:
                skip_mode = True
                continue
                
            if skip_mode:
                if stripped.startswith("-") or stripped.startswith(" ") or stripped.startswith("\t") or not stripped:
                    continue
                else:
                    skip_mode = False
            
            new_lines.append(line)
            
        for key, val in updates.items():
            if isinstance(val, (list, dict)):
                new_lines.append(f"{key}: {json.dumps(val)}")
            else:
                new_lines.append(f"{key}: {val}")
                
        new_frontmatter = "\n".join(new_lines)
        new_content = f"---\n{new_frontmatter}\n---\n{remaining_content}"
    else:
        new_lines = []
        for key, val in updates.items():
            if isinstance(val, (list, dict)):
                new_lines.append(f"{key}: {json.dumps(val)}")
            else:
                new_lines.append(f"{key}: {val}")
        new_frontmatter = "\n".join(new_lines)
        new_content = f"---\n{new_frontmatter}\n---\n{content}"
        
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(new_content)
    return True
