"""
api/services/chat.py — Hybrid GraphRAG service combining ChromaDB Vector Search and Neo4j Graph Traversal.
"""
import os
import re
import uuid
import datetime
from core.config import OBSIDIAN_INBOX_PATH, PROJECT_VAULT_PATH
from core.db import get_vault_collection
from core.graph_rag import traverse_subgraph
from core.processors import generate_content_with_fallback


def extract_query_keywords(query: str) -> list[str]:
    """
    Extracts key nouns/concepts from a user message to use as seed entities
    for GraphRAG subgraph traversal.
    """
    # Remove common conversational stop words
    stopwords = {
        "what", "is", "the", "a", "an", "how", "do", "i", "can", "you", "tell",
        "me", "about", "why", "where", "when", "which", "who", "whom", "this",
        "that", "these", "those", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "does", "did", "and", "or", "but", "in", "on",
        "at", "to", "for", "with", "from", "by", "of", "my", "your", "our", "their",
        "give", "show", "find", "explain", "summarize", "list"
    }
    # Match words and hyphenated terms
    tokens = re.findall(r'[A-Za-z0-9_\-\.\#]+', query)
    keywords = [t for t in tokens if len(t) > 2 and t.lower() not in stopwords]
    return keywords


def format_hybrid_rag_prompt(
    query: str,
    vector_context: str,
    graph_context: str,
    note_context: str = "",
    history_context: str = "",
) -> str:
    """
    Builds the combined Hybrid GraphRAG prompt structure for Gemini.
    """
    sections = []

    if note_context:
        sections.append(f"=== Active Note Context ===\n{note_context.strip()}")

    if vector_context:
        sections.append(f"=== Vector Knowledge Context ===\n{vector_context.strip()}")

    if graph_context:
        sections.append(f"=== Knowledge Graph Relationships ===\n{graph_context.strip()}")

    joined_context = "\n\n".join(sections) if sections else "No specific context available."

    prompt = f"""You are the Cortex Second Brain Assistant. Answer the user's question using the provided Vector Knowledge and Knowledge Graph contexts.

{joined_context}

{history_context}Question: {query}

INSTRUCTIONS:
1. Ground your answer primarily in the provided Vector Knowledge Context and Knowledge Graph Relationships.
2. Highlight relationships and connections between entities discovered in the knowledge graph.
3. When referencing key concepts, people, tools, or notes in your answer, wrap them in Obsidian-style wiki links like [[Concept Name]].
"""
    return prompt


def run_hybrid_chat(
    message: str,
    session_id: str = None,
    note_context_file: str = None,
    history: list = None,
) -> dict:
    """
    Executes the hybrid Vector + Graph RAG pipeline:
    1. Vector retrieval from ChromaDB.
    2. Subgraph traversal from Neo4j using query keywords.
    3. LLM answer synthesis via Gemini.
    """
    session_id = session_id or str(uuid.uuid4())

    # 1. Format history context
    history_context = ""
    if history:
        history_context = "Previous conversation:\n"
        for msg in history[-5:]:
            history_context += f"User: {msg.get('query', '')}\nAI: {msg.get('response', '')}\n"
        history_context += "\n"

    # 2. Active note context
    note_context_text = ""
    if note_context_file:
        paths = [
            os.path.join(OBSIDIAN_INBOX_PATH, note_context_file),
            os.path.join(PROJECT_VAULT_PATH, note_context_file),
        ]
        for p in paths:
            if os.path.exists(p):
                try:
                    with open(p, "r", encoding="utf-8", errors="ignore") as f:
                        note_content = f.read()
                        note_context_text = f"{note_content}\n"
                except Exception:
                    pass
                break

    # 3. Vector Search via ChromaDB
    vector_context = ""
    try:
        results = get_vault_collection().query(query_texts=[message], n_results=5)
        if results and results.get('documents') and results['documents'][0]:
            vector_context = "\n---\n".join(results['documents'][0])
    except Exception as e:
        print(f"[Chat Service] ChromaDB query error: {e}")

    # 4. Graph Search via Neo4j
    graph_context = ""
    try:
        keywords = extract_query_keywords(message)
        # Also add keywords from active note title if provided
        if note_context_file:
            clean_title = os.path.basename(note_context_file).replace(".md", "")
            keywords.extend(extract_query_keywords(clean_title))

        graph_triples = traverse_subgraph(keywords, max_hops=2)
        if graph_triples:
            graph_context = "\n".join(f"* {triple}" for triple in graph_triples)
    except Exception as e:
        print(f"[Chat Service] Graph traversal error: {e}")

    # 5. Build Hybrid Prompt
    prompt = format_hybrid_rag_prompt(
        query=message,
        vector_context=vector_context,
        graph_context=graph_context,
        note_context=note_context_text,
        history_context=history_context,
    )

    # 6. Synthesize Response with Gemini
    response, model_used = generate_content_with_fallback(prompt, purpose="rag_chat")

    return {
        "response": response.text,
        "model": model_used,
        "session_id": session_id,
        "vector_context_length": len(vector_context),
        "graph_relationships_count": len(graph_triples) if 'graph_triples' in locals() and graph_triples else 0,
    }
