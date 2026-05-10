import os
import shutil

# Paths
OBSIDIAN_PATH = r"C:\Users\91704\Documents\Obsidian Vault\Reels"
PROJECT_VAULT_PATH = r"c:\Users\91704\Desktop\Second-Brain\vault"

def sync():
    if not os.path.exists(PROJECT_VAULT_PATH):
        os.makedirs(PROJECT_VAULT_PATH)
        print(f"Created project vault folder: {PROJECT_VAULT_PATH}")

    print(f"Syncing from {OBSIDIAN_PATH} to {PROJECT_VAULT_PATH}...")
    
    files_copied = 0
    for filename in os.listdir(OBSIDIAN_PATH):
        if filename.endswith(".md"):
            src = os.path.join(OBSIDIAN_PATH, filename)
            dst = os.path.join(PROJECT_VAULT_PATH, filename)
            
            # Copy if it doesn't exist or if obsidian version is newer
            if not os.path.exists(dst) or os.path.getmtime(src) > os.path.getmtime(dst):
                shutil.copy2(src, dst)
                print(f"Copied: {filename}")
                files_copied += 1

    print(f"\nDone! Copied {files_copied} new/updated files to your project vault.")
    print("You can now run 'git add .' and 'git commit' to push them to GitHub.")

if __name__ == "__main__":
    sync()
