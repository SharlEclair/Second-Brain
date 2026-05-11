import json
import os
import datetime

INDEX_FILE = "url_index.json"

def migrate():
    if not os.path.exists(INDEX_FILE):
        print("No index file found. Nothing to migrate.")
        return

    with open(INDEX_FILE, "r") as f:
        try:
            index = json.load(f)
        except json.JSONDecodeError:
            print("Error: Index file is corrupted.")
            return

    new_index = {}
    migrated_count = 0
    
    print(f"Analyzing {len(index)} entries...")

    for key, value in index.items():
        if isinstance(value, dict):
            # Already a dict, keep it
            new_index[key] = value
        else:
            # Old format (string filename)
            filename = value
            new_index[key] = {
                "title": filename.replace(".md", ""),
                "fileName": filename,
                "date": datetime.datetime.now().isoformat(),
                "url": key if key.startswith("http") else ""
            }
            migrated_count += 1

    with open(INDEX_FILE, "w") as f:
        json.dump(new_index, f, indent=4)

    print(f"Success! Migrated {migrated_count} legacy entries to the new format.")

if __name__ == "__main__":
    migrate()
