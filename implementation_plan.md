# Second Brain: Obsidian-RAG Integration & Advanced Functionality Plan

This implementation plan outlines a new set of features to make the app more functional, interactive, and dynamic. It directly incorporates the core philosophies and architectural patterns extracted from the `obsidian-rag-tutorial.pdf` (Local-First, AI Librarian, Hierarchical Markdown Indexing, and Synthesis Loops).

## User Review Required

> [!IMPORTANT]
> **Architectural Decision: Vector DB vs. Pure Hierarchical Search**
> The PDF advocates for a "No Vector DB" approach, relying purely on the AI reading a `_master-index.md` -> topic `_index.md` -> target files. Our app currently uses ChromaDB for fast semantic search. 
> **Question:** Should we *replace* the vector database with this strict hierarchical reading method, or should we *combine* them (keep ChromaDB for quick retrieval, but implement the `_master-index` structure for browsing, organization, and LLM context)?
> *(My recommendation is to combine them: use the hierarchical indexes to structure the vault and feed context, but keep ChromaDB for blazing-fast semantic queries.)*

## Open Questions

- **Audit Actionability**: When the AI runs an "Audit" and finds broken links or missing topics, should it automatically generate placeholder notes for missing topics, or strictly output a read-only report for you to review?
- **Inbox Pattern**: Do you want to adopt the strict `raw/` (Inbox) -> `wiki/` (Processed) folder structure recommended by the PDF, or continue auto-sorting directly into categories as we currently do?

---

## 1. Hierarchical Markdown Indexing (The "AI Librarian" System)

The PDF emphasizes that the AI should act as a librarian maintaining structured index files, allowing the system to scale without relying solely on complex databases.

### Backend Implementation
- **Index Generators**: Create logic to automatically generate and update a `_master-index.md` in the root of `PROJECT_VAULT_PATH` and `OBSIDIAN_INBOX_PATH`. This file will contain a high-level summary of every category.
- **Topic Indexes**: Automatically maintain an `_index.md` inside every category directory (e.g., `/Recipe/_index.md`) that lists and summarizes every article within that topic.
- **Ingestion Hook**: Modify the existing ingestion pipeline so that whenever a new note is added, it updates the corresponding topic `_index.md` and the `_master-index.md`.

### Frontend Integration
- Add a "Library Directory" view to the Home Page that visually parses and displays the `_master-index.md` in a clean, interactive folder-tree UI, allowing rapid top-down navigation.

---

## 2. Vault Auditing & Hygiene (The "Audit" Verb)

To keep the knowledge base pristine and dense, we will implement the PDF's "Audit" concept.

### Backend Implementation
- **`POST /api/audit`**: Create a background job that walks the vault and uses the LLM to check for:
  - Conflicting claims or outdated information across articles.
  - "Ghost topics": Topics referenced via `[[links]]` that don't have their own actual article yet.
  - Gaps in coverage (suggesting 3-5 articles to add).
- Save the results to an `output/Vault-Audit-[Date].md` file.

### Frontend Integration
- **Hygiene Dashboard Widget**: Add an "Audit Vault" button to the Mission Control tab. When an audit is completed, display the flagged inconsistencies and "ghost topics" in an interactive checklist so users can easily click to create the missing articles.

---

## 3. The Synthesis Loop (Closing the Knowledge Loop)

The PDF highlights the "Magic Move" of Synthesis: queries that cross-reference multiple concepts and save the answer back into the wiki.

### Backend Implementation
- **Enhanced `save_answer`**: Modify the existing `/api/save_answer` endpoint so that when a chat answer is saved, the AI automatically:
  1. Injects proper `[[wiki links]]` back to the source notes it referenced.
  2. Places it in the correct category folder (not just a generic "Synthesis" folder).
  3. Updates the `_master-index` and topic `_index` to include this new synthesized knowledge.

### Frontend Integration
- In the Chat interface, when a user asks a synthesis question, provide a prominent "Promote to Wiki Article" button on the AI's response that triggers this advanced saving flow.

---

## 4. Inbox & "Compile" Workflow (Optional Refactoring)

### Backend Implementation
- **Raw Inbox Mode**: Create a configuration toggle that routes all raw clippings (from the web or mobile app) into a `raw/` folder instead of auto-categorizing them immediately.
- **`POST /api/compile`**: An endpoint that iterates through everything in `raw/`, categorizes them, extracts key takeaways, writes the tight markdown articles, drops them into the correct topic folders, and clears the inbox.

### Frontend Integration
- Add a "Compile Inbox (X items pending)" notification badge to the Home Page dashboard. Clicking it shows a neat animation of items moving from raw data to structured knowledge nodes.

---

## Verification Plan

### Automated Tests
- Create dummy notes in multiple categories and verify that `_master-index.md` and topic `_index.md` files are generated correctly.
- Verify the Audit endpoint accurately detects intentionally broken `[[links]]` and missing articles.

### Manual Verification
- Ask the Chat to synthesize two disparate concepts, click "Promote to Wiki Article", and manually verify in the filesystem that the new note contains proper back-links and the indexes were updated.
- Verify the new UI elements blend seamlessly with the existing dark/tech "Mission Control" aesthetic.
