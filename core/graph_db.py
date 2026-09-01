"""
core/graph_db.py — Neo4j Knowledge Graph connection and schema management.
"""
import os
from typing import Optional
from neo4j import GraphDatabase, Driver
from core.config import NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD

_graph_driver: Optional[Driver] = None
_schema_initialized: bool = False


def get_graph_driver() -> Optional[Driver]:
    """
    Returns the singleton Neo4j Driver instance, initializing connection
    and required schema constraints on first access.
    """
    global _graph_driver, _schema_initialized
    if _graph_driver is None:
        try:
            _graph_driver = GraphDatabase.driver(
                NEO4J_URI,
                auth=(NEO4J_USER, NEO4J_PASSWORD),
                max_connection_lifetime=3600,
            )
            _graph_driver.verify_connectivity()
            if not _schema_initialized:
                init_graph_schema(_graph_driver)
                _schema_initialized = True
        except Exception as e:
            print(f"[Neo4j] Failed to connect to Neo4j at {NEO4J_URI}: {e}")
            return None
    return _graph_driver


def init_graph_schema(driver: Driver):
    """
    Creates necessary unique constraints and indexes in Neo4j.
    """
    constraints = [
        "CREATE CONSTRAINT entity_name_unique IF NOT EXISTS FOR (e:Entity) REQUIRE e.name IS UNIQUE",
        "CREATE CONSTRAINT note_title_unique IF NOT EXISTS FOR (n:Note) REQUIRE n.title IS UNIQUE",
    ]
    try:
        with driver.session() as session:
            for c in constraints:
                try:
                    session.run(c)
                except Exception as e:
                    print(f"[Neo4j] Constraint warning: {e}")
    except Exception as e:
        print(f"[Neo4j] Schema initialization error: {e}")


def check_graph_health() -> bool:
    """Checks if the Neo4j instance is reachable and healthy."""
    driver = get_graph_driver()
    if driver is None:
        return False
    try:
        driver.verify_connectivity()
        return True
    except Exception:
        return False


def close_graph_driver():
    """Closes the Neo4j driver connection cleanly."""
    global _graph_driver
    if _graph_driver is not None:
        try:
            _graph_driver.close()
        except Exception:
            pass
        _graph_driver = None
