import fs from 'fs/promises';
import path from 'path';

const OBSIDIAN_PATH = 'C:\\Users\\91704\\Documents\\Obsidian Vault\\Reels';
const API_URL = 'http://localhost:3000/api/import_local';

async function importNotes() {
    console.log(`Starting import from: ${OBSIDIAN_PATH}`);
    try {
        const files = await fs.readdir(OBSIDIAN_PATH);
        const mdFiles = files.filter(f => f.endsWith('.md'));
        
        console.log(`Found ${mdFiles.length} markdown files. Importing...`);
        let successCount = 0;

        for (const file of mdFiles) {
            const filePath = path.join(OBSIDIAN_PATH, file);
            const content = await fs.readFile(filePath, 'utf-8');
            
            try {
                const response = await fetch(API_URL, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ filename: file, content })
                });

                if (response.ok) {
                    successCount++;
                    console.log(`[SUCCESS] Imported: ${file}`);
                } else {
                    const errText = await response.text();
                    console.error(`[FAILED] ${file} (Status: ${response.status}):`, errText);
                }
            } catch (e: any) {
                console.error(`[ERROR] Failed to send ${file}:`, e.message);
            }
        }
        
        console.log(`\nImport complete! Successfully imported ${successCount}/${mdFiles.length} files.`);
    } catch (e: any) {
        console.error("Failed to read directory:", e.message);
    }
}

importNotes();
