"""
core/db.py — Shared ChromaDB singleton.

Provides a single, lazily-initialized ChromaDB collection that is safe to
call from both the FastAPI process and Celery worker processes.

This module exists to break the circular import pattern where
core/synthesis_loop.py, core/retroactive_backlink.py, and api/tasks.py
all previously imported `vault_collection` directly from `main`.
"""
import chromadb

_chroma_client: "chromadb.PersistentClient | None" = None
_vault_collection: "chromadb.Collection | None" = None


def get_vault_collection() -> "chromadb.Collection":
    """
    Return the shared ChromaDB 'vault_embeddings' collection.

    The client and collection are created on the first call and reused
    for all subsequent calls in the same process. Thread-safe via the
    GIL for the initialization check; ChromaDB's own client is
    thread-safe for concurrent reads and writes.
    """
    global _chroma_client, _vault_collection
    if _vault_collection is None:
        _chroma_client = chromadb.PersistentClient(path="./chroma_db")
        _vault_collection = _chroma_client.get_or_create_collection(
            name="vault_embeddings"
        )
    return _vault_collection
