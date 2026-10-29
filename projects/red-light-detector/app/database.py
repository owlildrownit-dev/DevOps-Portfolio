import json
import sqlite3
from app.config import settings


def _conn() -> sqlite3.Connection:
    conn = sqlite3.connect(str(settings.db_path))
    conn.row_factory = sqlite3.Row
    return conn


def init_database() -> None:
    with _conn() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS analyses (
                id TEXT PRIMARY KEY,
                created_at TEXT NOT NULL,
                source_name TEXT NOT NULL,
                media_type TEXT NOT NULL,
                status TEXT NOT NULL,
                traffic_light_state TEXT,
                stop_line_mode TEXT,
                stop_line TEXT,
                detected_vehicles INTEGER DEFAULT 0,
                violations INTEGER DEFAULT 0,
                processing_seconds REAL,
                result_path TEXT,
                evidence_path TEXT,
                details TEXT
            )
        """)


def save_analysis(record: dict) -> None:
    with _conn() as conn:
        conn.execute("""
            INSERT OR REPLACE INTO analyses VALUES (
                :id, :created_at, :source_name, :media_type, :status,
                :traffic_light_state, :stop_line_mode,
                :stop_line_json, :detected_vehicles, :violations,
                :processing_seconds,
                :result_path, :evidence_path, :details_json
            )
        """, {
            **record,
            "stop_line_json": json.dumps(record.get("stop_line"), ensure_ascii=False),
            "details_json": json.dumps(record.get("details", {}), ensure_ascii=False),
        })


def list_analyses(limit: int = 100) -> list[dict]:
    with _conn() as conn:
        rows = conn.execute(
            "SELECT * FROM analyses ORDER BY created_at DESC LIMIT ?", (limit,)
        ).fetchall()
    return [_deserialize(dict(r)) for r in rows]


def get_analysis(analysis_id: str) -> dict | None:
    with _conn() as conn:
        row = conn.execute("SELECT * FROM analyses WHERE id = ?", (analysis_id,)).fetchone()
    return _deserialize(dict(row)) if row else None


def _deserialize(row: dict) -> dict:
    row["stop_line"] = json.loads(row.pop("stop_line", None) or "null")
    row["details"] = json.loads(row.pop("details", None) or "{}")
    return row
