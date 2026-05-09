import express from 'express';
import { createServer as createViteServer } from 'vite';
import path from 'path';
import fs from 'fs/promises';
import { existsSync, createReadStream } from 'fs';
import cors from 'cors';
import { GoogleGenAI } from "@google/genai";
import dotenv from 'dotenv';

dotenv.config();

const app = express();
const PORT = 3000;
const VAULT_PATH = path.join(process.cwd(), 'vault');
const TEMP_PATH = path.join(process.cwd(), 'temp');
const INDEX_FILE = path.join(process.cwd(), 'url_index.json');
const VECTOR_DB_PATH = path.join(process.cwd(), 'vector_db.json');

app.use(cors());
app.use(express.json());

// Ensure directories exist
async function ensureDirs() {
  try {
    if (!existsSync(VAULT_PATH)) await fs.mkdir(VAULT_PATH, { recursive: true });
    if (!existsSync(TEMP_PATH)) await fs.mkdir(TEMP_PATH, { recursive: true });
    if (!existsSync(INDEX_FILE)) await fs.writeFile(INDEX_FILE, JSON.stringify({}));
  } catch (err) {
    console.error("Failed to ensure directories:", err);
  }
}

function isValidUrl(urlString: string) {
  try {
    new URL(urlString);
    return true;
  } catch (e) {
    return false;
  }
}

// Gemini Initialization
let apiKey = process.env.GEMINI_API_KEY;
if (!apiKey || apiKey === 'MY_GEMINI_API_KEY' || apiKey === '') {
  console.warn("GEMINI_API_KEY is not set or is invalid. API calls will fail.");
}
const genAI = new GoogleGenAI({ apiKey: apiKey || 'invalid_key' });

function dotProduct(a: number[], b: number[]) {
  return a.reduce((sum, val, i) => sum + val * b[i], 0);
}

class LocalVectorDB {
  data: { id: string, doc: string, metadata: any, embedding: number[] }[] = [];

  constructor() {
    this.load();
  }

  async load() {
    try {
      if (existsSync(VECTOR_DB_PATH)) {
        const content = await fs.readFile(VECTOR_DB_PATH, 'utf-8');
        this.data = JSON.parse(content);
      } else {
        this.data = [];
      }
    } catch(e) {
      console.error("Failed to load vector DB:", e);
      this.data = [];
    }
  }

  async save() {
    await fs.writeFile(VECTOR_DB_PATH, JSON.stringify(this.data));
  }

  async add({ids, documents, metadatas}: {ids: string[], documents: string[], metadatas: any[]}) {
    for (let i = 0; i < ids.length; i++) {
        try {
            const result = await genAI.models.embedContent({
                model: 'text-embedding-004',
                contents: documents[i]
            });
            const embedding = (result as any).embedding?.values || (result as any).embeddings?.[0]?.values || (result as any).embeddings?.values;
            if (embedding) {
               // Remove existing entry if id exists
               this.data = this.data.filter(item => item.id !== ids[i]);
               this.data.push({
                   id: ids[i],
                   doc: documents[i],
                   metadata: metadatas[i],
                   embedding
               });
            }
        } catch(e) {
            console.error("Embedding generation failed for document", ids[i]);
        }
    }
    await this.save();
  }

  async query({queryTexts, nResults}: {queryTexts: string[], nResults: number}) {
    const results = { documents: [[] as string[]] };
    if (this.data.length === 0) return results;

    let qEmbed;
    try {
      const queryEmbedResult = await genAI.models.embedContent({
          model: 'text-embedding-004',
          contents: queryTexts[0]
      });
      qEmbed = (queryEmbedResult as any).embedding?.values || (queryEmbedResult as any).embeddings?.[0]?.values || (queryEmbedResult as any).embeddings?.values;
    } catch (e: any) {
      console.error("Embedding generation failed during query:", e.message);
    }
    if (!qEmbed || !Array.isArray(qEmbed)) return results;

    const scored = this.data.map(item => ({
        ...item,
        score: dotProduct(qEmbed, item.embedding || [])
    }));
    
    scored.sort((a, b) => b.score - a.score);
    const top = scored.slice(0, nResults);
    results.documents[0] = top.map(t => t.doc);
    return results;
  }
}

async function startServer() {
  await ensureDirs();

  const collection = new LocalVectorDB();
  await collection.load();

  // --- API Routes ---

  // Ingest URL
  app.post('/api/ingest', async (req, res) => {
    const { url } = req.body;
    if (!url) return res.status(400).json({ error: "URL is required" });
    if (!isValidUrl(url)) return res.status(400).json({ error: "Invalid URL format" });

    try {
      const indexContent = await fs.readFile(INDEX_FILE, 'utf-8');
      const index = JSON.parse(indexContent || '{}');
      
      if (index[url]) {
        // Check if file still exists
        const fullPath = path.join(VAULT_PATH, index[url].fileName);
        if (existsSync(fullPath)) {
          return res.json({ status: 'existing', note: index[url] });
        }
      }

      console.log(`Ingesting: ${url}`);
      
      let sourceText = "";
      try {
        const response = await fetch(url);
        if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
        let text = await response.text();
        // Truncate to avoid massive payloads for huge sites
        sourceText = text.substring(0, 50000); 
      } catch (e: any) {
        throw new Error(`Failed to fetch URL: ${e.message}`);
      }

      const model = "gemini-2.5-flash"; // Using a more stable model name for safety
      const prompt = `Please analyze the following raw content extracted from the URL (${url}) and structure it into a professional, structured Markdown note for a personal knowledge base. Include key takeaways, a summary, and detailed notes. If the content is an HTML page, extract the meaningful text.\n\nContent:\n${sourceText}`;

      let result;
      try {
        result = await genAI.models.generateContent({
          model: model,
          contents: prompt
        });
      } catch (geminiErr: any) {
        throw new Error(`Gemini API Error during analysis: ${geminiErr.message}`);
      }

      const noteContent = result.text || "Failed to generate content";
      
      // 3. Save to Vault
      let rawTitle = "Untitled Note";
      try {
        const titleResult = await genAI.models.generateContent({
          model: model,
          contents: `Based on this content, generate a short (3-5 words) obsidian-friendly filename (no extension). Return ONLY the words, no preamble:\n\n${noteContent.substring(0, 1000)}`
        });
        rawTitle = titleResult.text?.trim().replace(/\n/g, ' ') || rawTitle;
      } catch (e: any) {
        console.error("Failed to generate title:", e.message);
      }
      const safeTitle = rawTitle.replace(/[^a-z0-9]/gi, '_').toLowerCase().substring(0, 50);
      const noteFileName = `${safeTitle || 'note'}_${Date.now()}.md`;
      const notePath = path.join(VAULT_PATH, noteFileName);

      const finalMarkdown = `---\nsource: ${url}\ndate: ${new Date().toISOString()}\ntag: #ingestion\n---\n\n# ${rawTitle}\n\n${noteContent}`;
      await fs.writeFile(notePath, finalMarkdown);

      // 4. Index
      if (collection) {
        await collection.add({
          ids: [url],
          documents: [finalMarkdown],
          metadatas: [{ source: url, title: rawTitle, date: new Date().toISOString() }]
        });
      }

      // 5. Update index
      index[url] = { title: rawTitle, fileName: noteFileName, date: new Date().toISOString() };
      await fs.writeFile(INDEX_FILE, JSON.stringify(index, null, 2));

      res.json({ status: 'success', note: index[url] });

    } catch (error: any) {
      console.error("Ingestion error:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Query Brain (Chat)
  app.post('/api/chat', async (req, res) => {
    const { message } = req.body;
    if (!message) return res.status(400).json({ error: "Message is required" });

    try {
      let context = "";
      if (collection) {
        const results = await collection.query({
          queryTexts: [message],
          nResults: 3
        });
        context = results.documents[0].join("\n\n---\n\n");
      }

      const prompt = `You are a helpful "Second Brain" assistant. Answer the user's question based on the following context from their personal vault. If the context doesn't contain the answer, use your general knowledge but mention that the vault didn't have specific info.\n\nContext:\n${context}\n\nUser Question: ${message}`;

      let result;
      try {
        result = await genAI.models.generateContent({
          model: "gemini-2.5-flash",
          contents: prompt
        });
      } catch (geminiErr: any) {
        throw new Error(`Gemini API Error during chat: ${geminiErr.message}`);
      }

      res.json({ response: result.text });
    } catch (error: any) {
      console.error("Chat error:", error);
      res.status(500).json({ error: error.message });
    }
  });

  // Get Notes
  app.get('/api/notes', async (req, res) => {
    try {
      const index = JSON.parse(await fs.readFile(INDEX_FILE, 'utf-8'));
      res.json(Object.values(index));
    } catch (e) {
      res.json([]);
    }
  });

  // Get Note Content
  app.get('/api/notes/:fileName', async (req, res) => {
    try {
      const content = await fs.readFile(path.join(VAULT_PATH, req.params.fileName), 'utf-8');
      res.send(content);
    } catch (e) {
      res.status(404).send("Note not found");
    }
  });

  // Save Answer (from Mobile/Chat)
  app.post('/api/save_answer', async (req, res) => {
    const { title, content } = req.body;
    if (!title || !content) return res.status(400).json({ error: "Title and content are required" });

    try {
      const safeTitle = title.replace(/[^a-z0-9]/gi, '_').toLowerCase();
      const noteFileName = `${safeTitle}.md`;
      const notePath = path.join(VAULT_PATH, noteFileName);

      const finalMarkdown = `---\nsource: Chat\ndate: ${new Date().toISOString()}\ntag: #chat-save\n---\n\n# ${title}\n\n${content}`;
      await fs.writeFile(notePath, finalMarkdown);

      // Update index
      const index = JSON.parse(await fs.readFile(INDEX_FILE, 'utf-8'));
      // For chat saves, use filename as key since there's no source URL
      index[noteFileName] = { title, fileName: noteFileName, date: new Date().toISOString() };
      await fs.writeFile(INDEX_FILE, JSON.stringify(index, null, 2));

      // Add to vector DB
      if (collection) {
        await collection.add({
          ids: [noteFileName],
          documents: [finalMarkdown],
          metadatas: [{ source: 'Chat', title, date: new Date().toISOString() }]
        });
      }

      res.json({ status: 'success', fileName: noteFileName });
    } catch (error: any) {
      res.status(500).json({ error: error.message });
    }
  });

  // Sync (Mock)
  app.post('/api/sync', async (req, res) => {
    // In a real app, we'd run git commands
    // subprocess.run(["git", "add", "."], cwd=VAULT_PATH) etc.
    res.json({ status: 'success', message: "Vault synced with remote repository" });
  });

  // --- Vite Middleware ---
  if (process.env.NODE_ENV !== "production") {
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: "spa",
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.join(process.cwd(), 'dist');
    app.use(express.static(distPath));
    app.get('*', (req, res) => {
      res.sendFile(path.join(distPath, 'index.html'));
    });
  }

  app.listen(PORT, "0.0.0.0", () => {
    console.log(`Server running on http://localhost:${PORT}`);
  });
}

startServer();
