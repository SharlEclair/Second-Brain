"""
core/graph_rag.py — Knowledge Graph extraction, Neo4j upsertion, and Subgraph Traversal.
"""
import re
import json
from typing import Optional
from neo4j import Driver
from core.graph_db import get_graph_driver
from core.processors import generate_content_with_fallback


def extract_knowledge_graph(text: str) -> dict:
    """
    Uses Gemini to extract entities and semantic relationships from note text.
    Returns:
    {
        "entities": [{"name": "FastAPI", "type": "Framework"}, ...],
        "relationships": [{"source": "FastAPI", "target": "Python", "relation": "WRITTEN_IN"}, ...]
    }
    """
    if not text or len(text.strip()) < 20:
        return {"entities": [], "relationships": []}

    prompt = f"""
You are an expert Knowledge Graph engineer.
Extract key domain entities (tools, frameworks, languages, concepts, people, companies, methodologies, locations) and their semantic relationships from the provided note text.

Input Text:
{text[:4000]}

Rules:
1. Extract distinct, specific entity names (e.g. "FastAPI", "Python", "Celery", "Redis", "Obsidian").
2. Assign each entity a high-level Type (e.g. "Language", "Framework", "Database", "Concept", "Tool", "Person", "Company").
3. Extract explicit relationships between these entities in UPPER_SNAKE_CASE (e.g., "WRITTEN_IN", "USES", "INTEGRATES_WITH", "CREATED_BY", "ALTERNATIVE_TO", "PART_OF").
4. Output STRICT JSON with no markdown wrapping or preamble.

Expected JSON Structure:
{{
  "entities": [
    {{"name": "FastAPI", "type": "Framework"}},
    {{"name": "Python", "type": "Language"}}
  ],
  "relationships": [
    {{"source": "FastAPI", "target": "Python", "relation": "WRITTEN_IN"}}
  ]
}}
"""
    try:
        response, _ = generate_content_with_fallback(prompt, purpose="kg_extraction")
        raw = response.text.strip()
        if raw.startswith("```"):
            raw = re.sub(r'^```(?:json)?\s*', '', raw)
            raw = re.sub(r'\s*```$', '', raw)
        data = json.loads(raw)
        entities = data.get("entities", [])
        relationships = data.get("relationships", [])

        # Clean entities
        clean_entities = []
        seen_entities = set()
        for e in entities:
            name = str(e.get("name", "")).strip()
            etype = str(e.get("type", "Concept")).strip()
            if name and name.lower() not in seen_entities:
                seen_entities.add(name.lower())
                clean_entities.append({"name": name, "type": etype or "Concept"})

        # Clean relationships
        clean_relationships = []
        for r in relationships:
            src = str(r.get("source", "")).strip()
            tgt = str(r.get("target", "")).strip()
            rel = re.sub(r'[^A-Za-z0-9_]', '_', str(r.get("relation", "RELATED_TO"))).upper()
            if not rel or rel == "_":
                rel = "RELATED_TO"
            if src and tgt and src.lower() != tgt.lower():
                clean_relationships.append({
                    "source": src,
                    "target": tgt,
                    "relation": rel,
                })

        return {"entities": clean_entities, "relationships": clean_relationships}
    except Exception as e:
        print(f"[GraphRAG] KG extraction error: {e}")
        return {"entities": [], "relationships": []}


def upsert_note_graph(
    note_title: str,
    entities: list[dict],
    relationships: list[dict],
    driver: Optional[Driver] = None
) -> bool:
    """
    Inserts or updates the Note, Entity nodes, and dynamic relationship edges in Neo4j.
    """
    driver = driver or get_graph_driver()
    if driver is None:
        return False

    try:
        with driver.session() as session:
            # 1. Merge Note node
            session.run(
                """
                MERGE (n:Note {title: $note_title})
                ON CREATE SET n.created_at = datetime()
                ON MATCH SET n.updated_at = datetime()
                """,
                note_title=note_title,
            )

            # 2. Merge Entities and connect Note -[:MENTIONS]-> Entity
            for ent in entities:
                session.run(
                    """
                    MERGE (e:Entity {name: $name})
                    ON CREATE SET e.type = $type
                    WITH e
                    MATCH (n:Note {title: $note_title})
                    MERGE (n)-[:MENTIONS]->(e)
                    """,
                    name=ent["name"],
                    type=ent.get("type", "Concept"),
                    note_title=note_title,
                )

            # 3. Create Entity -[RELATION]-> Entity edges
            for rel in relationships:
                src = rel["source"]
                tgt = rel["target"]
                rel_type = re.sub(r'[^A-Za-z0-9_]', '_', str(rel.get("relation", "RELATED_TO"))).upper()
                if not rel_type or rel_type == "_":
                    rel_type = "RELATED_TO"

                cypher = f"""
                MATCH (e1:Entity {{name: $src}})
                MATCH (e2:Entity {{name: $tgt}})
                MERGE (e1)-[r:{rel_type}]->(e2)
                SET r.source_note = $note_title
                """
                session.run(cypher, src=src, tgt=tgt, note_title=note_title)

        return True
    except Exception as e:
        print(f"[GraphRAG] Neo4j upsert error for note '{note_title}': {e}")
        return False


def traverse_subgraph(
    entity_names: list[str],
    max_hops: int = 2,
    driver: Optional[Driver] = None
) -> list[str]:
    """
    Given a list of entity names/keywords, traverses up to max_hops in Neo4j
    and returns human-readable relationship statements for GraphRAG context.
    """
    driver = driver or get_graph_driver()
    if driver is None or not entity_names:
        return []

    clean_names = [n.strip() for n in entity_names if n.strip()]
    clean_lower = [n.lower() for n in clean_names]
    if not clean_names:
        return []

    # Bounded hop syntax for Cypher
    hops = max(1, min(max_hops, 3))
    cypher = f"""
    MATCH (e1:Entity)
    WHERE e1.name IN $names OR toLower(e1.name) IN $names_lower
    MATCH path = (e1)-[r*1..{hops}]-(e2:Entity)
    WITH DISTINCT relationships(path) AS rels
    UNWIND rels AS rel
    WITH DISTINCT startNode(rel) AS s, type(rel) AS t, endNode(rel) AS e, rel.source_note AS src
    RETURN s.name AS source, t AS relation, e.name AS target, src AS source_note
    LIMIT 40
    """

    results_formatted = []
    try:
        with driver.session() as session:
            res = session.run(cypher, names=clean_names, names_lower=clean_lower)
            seen_triples = set()
            for record in res:
                s = record["source"]
                t = record["relation"]
                e = record["target"]
                src = record["source_note"]
                triple_key = (s, t, e)
                if triple_key not in seen_triples:
                    seen_triples.add(triple_key)
                    line = f"{s} is {t} {e}"
                    if src:
                        line += f" (Source: [[{src}]])"
                    results_formatted.append(line)
    except Exception as e:
        print(f"[GraphRAG] Subgraph traversal query error: {e}")

    return results_formatted
