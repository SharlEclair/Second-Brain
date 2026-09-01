import pytest
import json
from core.graph_rag import (
    extract_knowledge_graph,
    upsert_note_graph,
    traverse_subgraph,
)
from api.services.chat import (
    extract_query_keywords,
    format_hybrid_rag_prompt,
    run_hybrid_chat,
)


def test_extract_knowledge_graph_mocked(monkeypatch):
    mock_llm_json = json.dumps({
        "entities": [
            {"name": "FastAPI", "type": "Framework"},
            {"name": "Python", "type": "Language"},
            {"name": "Redis", "type": "Database"}
        ],
        "relationships": [
            {"source": "FastAPI", "target": "Python", "relation": "WRITTEN_IN"},
            {"source": "FastAPI", "target": "Redis", "relation": "CACHES_IN"}
        ]
    })

    class MockResponse:
        text = f"```json\n{mock_llm_json}\n```"

    monkeypatch.setattr(
        "core.graph_rag.generate_content_with_fallback",
        lambda prompt, purpose="kg_extraction": (MockResponse(), "mock-model")
    )

    result = extract_knowledge_graph("FastAPI is a modern web framework for Python using Redis.")
    assert len(result["entities"]) == 3
    assert result["entities"][0]["name"] == "FastAPI"
    assert len(result["relationships"]) == 2
    assert result["relationships"][0]["relation"] == "WRITTEN_IN"


def test_upsert_note_graph_mocked():
    cypher_queries = []

    class MockSession:
        def __enter__(self):
            return self
        def __exit__(self, exc_type, exc_val, exc_tb):
            pass
        def run(self, query, **kwargs):
            cypher_queries.append((query.strip(), kwargs))
            return []

    class MockDriver:
        def session(self):
            return MockSession()

    entities = [{"name": "Neo4j", "type": "Database"}]
    relationships = [{"source": "Cortex", "target": "Neo4j", "relation": "USES"}]

    success = upsert_note_graph(
        note_title="Graph Architecture",
        entities=entities,
        relationships=relationships,
        driver=MockDriver()
    )

    assert success is True
    assert len(cypher_queries) >= 3  # Note merge, entity merge, and relation merge


def test_traverse_subgraph_mocked():
    class MockRecord(dict):
        def __getitem__(self, key):
            return super().__getitem__(key)

    mock_records = [
        MockRecord({"source": "FastAPI", "relation": "WRITTEN_IN", "target": "Python", "source_note": "Backend Guide"}),
        MockRecord({"source": "Celery", "relation": "USES", "target": "Redis", "source_note": "Task Queue"})
    ]

    class MockSession:
        def __enter__(self):
            return self
        def __exit__(self, exc_type, exc_val, exc_tb):
            pass
        def run(self, query, **kwargs):
            return mock_records

    class MockDriver:
        def session(self):
            return MockSession()

    triples = traverse_subgraph(["FastAPI", "Celery"], max_hops=2, driver=MockDriver())
    assert len(triples) == 2
    assert "FastAPI is WRITTEN_IN Python (Source: [[Backend Guide]])" in triples
    assert "Celery is USES Redis (Source: [[Task Queue]])" in triples


def test_extract_query_keywords():
    keywords = extract_query_keywords("How does Celery use Redis for task scheduling?")
    assert "Celery" in keywords
    assert "Redis" in keywords
    assert "task" in keywords
    assert "scheduling" in keywords
    assert "how" not in keywords
    assert "for" not in keywords


def test_format_hybrid_rag_prompt():
    prompt = format_hybrid_rag_prompt(
        query="Explain the backend architecture",
        vector_context="FastAPI is the ASGI web framework.",
        graph_context="* FastAPI is WRITTEN_IN Python",
        note_context="Active Note on Architecture",
        history_context="User: Hi\nAI: Hello\n"
    )

    assert "=== Active Note Context ===" in prompt
    assert "=== Vector Knowledge Context ===" in prompt
    assert "=== Knowledge Graph Relationships ===" in prompt
    assert "FastAPI is the ASGI web framework." in prompt
    assert "* FastAPI is WRITTEN_IN Python" in prompt
    assert "Question: Explain the backend architecture" in prompt


def test_run_hybrid_chat_mocked(monkeypatch):
    class MockDocCollection:
        def query(self, query_texts, n_results=5):
            return {"documents": [["ChromaDB vector doc about GraphRAG"]]}

    monkeypatch.setattr("api.services.chat.get_vault_collection", lambda: MockDocCollection())
    monkeypatch.setattr(
        "api.services.chat.traverse_subgraph",
        lambda keywords, max_hops=2: ["Cortex is INTEGRATED_WITH Neo4j (Source: [[Architecture]])"]
    )

    class MockLLMResponse:
        text = "Cortex uses [[Neo4j]] alongside [[ChromaDB]] for hybrid retrieval."

    monkeypatch.setattr(
        "api.services.chat.generate_content_with_fallback",
        lambda prompt, purpose="rag_chat": (MockLLMResponse(), "gemini-2.5-flash")
    )

    result = run_hybrid_chat("How does GraphRAG work in Cortex?")
    assert result["response"] == "Cortex uses [[Neo4j]] alongside [[ChromaDB]] for hybrid retrieval."
    assert result["model"] == "gemini-2.5-flash"
    assert result["graph_relationships_count"] == 1
