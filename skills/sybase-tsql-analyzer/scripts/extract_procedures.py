#!/usr/bin/env python3
"""
extract_procedures.py — deterministic extractor for Sybase T-SQL objects.

Walks the given path looking for *.sql / *.ddl / defncopy output and emits a
JSON array on stdout, one object per CREATE PROCEDURE / TRIGGER / FUNCTION /
VIEW found. Each object includes complexity signals the agent uses to classify
the procedure without re-doing regex itself.

Output schema (one element per object):

  {
    "name": "dbname.owner.procname",          # fully qualified if detectable
    "object_type": "PROCEDURE|TRIGGER|FUNCTION|VIEW",
    "source_file": "relative/path/to/file.sql",
    "start_line": 42,                          # 1-indexed
    "end_line": 198,
    "line_count": 156,
    "param_count": 4,                          # for procedures/functions; null otherwise
    "signals": {                               # boolean flags, all derived locally
      "has_cursor": true,                      # DECLARE CURSOR or WHILE/FETCH
      "has_dynamic_sql": false,                # EXEC(@sql) or sp_executesql
      "has_temp_table": true,                  # #temp or ##temp creation
      "has_proxy_table": false,                # CREATE PROXY_TABLE or EXISTING TABLE
      "has_xp_cmdshell": false,                # OS shell-out
      "has_sybase_specific": true,             # @@identity, sp_procxmode, COMPUTE BY, etc.
      "has_compute_by": false,
      "has_set_rowcount": false,
      "has_holdlock": false,
      "has_waitfor": false,
      "has_raiserror": true,
      "cross_db_references": ["other_db.dbo.foo"],  # database.owner.object hits
      "transaction_keywords": ["BEGIN TRAN", "COMMIT"],
      "savepoint_used": false                  # SAVE TRAN
    },
    "complexity_hint": "simple|medium|complex" # rough bucket for triage
  }

Usage:

  ./extract_procedures.py path/to/sources                  # prints JSON array
  ./extract_procedures.py path/to/sources --pretty         # indented
  ./extract_procedures.py path/to/sources --summary        # one-line counts only

Designed for "agentic ergonomics": minimal stdout, no tracebacks on partial
failures (failed files are reported under a `_errors` key in --summary mode and
otherwise suppressed). Exit 0 on success even if some files failed to parse.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

SUPPORTED_SUFFIXES = (".sql", ".ddl", ".prc", ".trg", ".syb", ".ase")

# CREATE [OR REPLACE] PROCEDURE [owner.]name [(params)] AS
# Capture: object_type, qualified_name, params (optional)
CREATE_OBJ_RE = re.compile(
    r"""
    ^\s*
    CREATE \s+ (?:OR\s+REPLACE\s+)?
    (?P<type>PROCEDURE|PROC|TRIGGER|FUNCTION|VIEW)
    \s+
    (?P<name>[A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*){0,2})
    (?:\s*\(\s*(?P<params>[^)]*)\s*\))?
    """,
    re.IGNORECASE | re.VERBOSE | re.MULTILINE,
)

# Object terminator. Sybase typically uses "go" on its own line, MS-style uses ";".
TERMINATOR_RE = re.compile(r"^\s*(go|GO)\s*$|^\s*;\s*$", re.MULTILINE)

CROSS_DB_REF_RE = re.compile(
    r"\b([A-Za-z_]\w*)\.([A-Za-z_]\w*)\.([A-Za-z_]\w*)\b"
)

# Each pattern is checked against the procedure body. False positives are
# acceptable here because the agent does final classification.
SIGNAL_PATTERNS: dict[str, re.Pattern[str]] = {
    "has_cursor": re.compile(r"\bDECLARE\s+\w+\s+CURSOR\b|\bFETCH\s+(?:NEXT\s+)?FROM\b", re.IGNORECASE),
    "has_dynamic_sql": re.compile(r"\bEXEC\s*\(\s*@\w+\s*\)|\bsp_executesql\b", re.IGNORECASE),
    "has_temp_table": re.compile(r"#{1,2}\w+|\bCREATE\s+TABLE\s+#", re.IGNORECASE),
    "has_proxy_table": re.compile(r"\bCREATE\s+(?:PROXY_TABLE|EXISTING\s+TABLE)\b", re.IGNORECASE),
    "has_xp_cmdshell": re.compile(r"\bxp_cmdshell\b", re.IGNORECASE),
    "has_compute_by": re.compile(r"\bCOMPUTE\s+(?:BY|SUM|AVG|MIN|MAX|COUNT)\b", re.IGNORECASE),
    "has_set_rowcount": re.compile(r"\bSET\s+ROWCOUNT\s+\d+\b", re.IGNORECASE),
    "has_holdlock": re.compile(r"\b(?:HOLDLOCK|NOHOLDLOCK|READPAST)\b", re.IGNORECASE),
    "has_waitfor": re.compile(r"\bWAITFOR\s+(?:DELAY|TIME)\b", re.IGNORECASE),
    "has_raiserror": re.compile(r"\bRAISERROR\b", re.IGNORECASE),
    "savepoint_used": re.compile(r"\bSAVE\s+TRAN(?:SACTION)?\b", re.IGNORECASE),
}

SYBASE_SPECIFIC_RE = re.compile(
    r"@@identity|sp_procxmode|sp_addtype|sp_helpindex|"
    r"\bSET\s+CHAINED\b|\bWAITFOR\s+(?:DELAY|TIME)\b|"
    r"\bCOMPUTE\s+(?:BY|SUM|AVG|MIN|MAX|COUNT)\b|"
    r"\bCREATE\s+PROXY_TABLE\b",
    re.IGNORECASE,
)

TRANSACTION_KW_RE = re.compile(
    r"\b(BEGIN\s+TRAN(?:SACTION)?|COMMIT(?:\s+TRAN(?:SACTION)?)?|ROLLBACK(?:\s+TRAN(?:SACTION)?)?)\b",
    re.IGNORECASE,
)


def detect_signals(body: str) -> dict[str, Any]:
    signals: dict[str, Any] = {}
    for key, pat in SIGNAL_PATTERNS.items():
        signals[key] = bool(pat.search(body))
    signals["has_sybase_specific"] = bool(SYBASE_SPECIFIC_RE.search(body))

    cross_refs = sorted({".".join(m.groups()) for m in CROSS_DB_REF_RE.finditer(body)})
    signals["cross_db_references"] = cross_refs

    txn_keywords = sorted({m.group(1).upper() for m in TRANSACTION_KW_RE.finditer(body)})
    signals["transaction_keywords"] = txn_keywords

    return signals


def complexity_hint(line_count: int, signals: dict[str, Any]) -> str:
    """Cheap triage bucket. Agent will re-classify with full context."""
    score = 0
    if line_count > 500:
        score += 3
    elif line_count > 150:
        score += 2
    elif line_count > 40:
        score += 1
    if signals["has_cursor"]:
        score += 2
    if signals["has_dynamic_sql"]:
        score += 2
    if signals["savepoint_used"]:
        score += 2
    if signals["cross_db_references"]:
        score += 2
    if signals["has_xp_cmdshell"]:
        score += 3
    if signals["has_proxy_table"]:
        score += 2
    if score >= 5:
        return "complex"
    if score >= 2:
        return "medium"
    return "simple"


def count_params(params_raw: str | None) -> int | None:
    """Count parameters from the parenthesized form, if present."""
    if params_raw is None:
        return None
    if not params_raw.strip():
        return 0
    # Naive split on commas not inside parentheses. Sybase params don't nest deeply.
    depth = 0
    count = 1
    for ch in params_raw:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        elif ch == "," and depth == 0:
            count += 1
    return count


# Sybase commonly declares parameters without parens:
#   CREATE PROCEDURE foo
#       @account_id INT,
#       @as_of_date DATETIME
#   AS
# Count distinct @-prefixed names declared between CREATE and the next AS.
PARAM_DECL_RE = re.compile(r"@\w+\s+[A-Za-z_][\w()]*", re.MULTILINE)


def count_params_from_header(header: str) -> int:
    return len({m.group(0).split()[0].lower() for m in PARAM_DECL_RE.finditer(header)})


def parse_file(path: Path, root: Path) -> tuple[list[dict[str, Any]], str | None]:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        return [], f"{path}: {e}"

    objects: list[dict[str, Any]] = []

    # Find all CREATE statements. We slice out each object's body up to the
    # next CREATE or terminator.
    matches = list(CREATE_OBJ_RE.finditer(text))
    for i, m in enumerate(matches):
        start = m.start()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)

        # Stop earlier if we hit a "go" terminator on its own line.
        terminator = TERMINATOR_RE.search(text, m.end(), end)
        if terminator:
            end = terminator.start()

        body = text[m.end():end]

        # Line numbers (1-indexed).
        start_line = text.count("\n", 0, start) + 1
        end_line = text.count("\n", 0, end) + 1
        line_count = max(end_line - start_line, 1)

        signals = detect_signals(body)
        obj_type = m.group("type").upper()
        if obj_type == "PROC":
            obj_type = "PROCEDURE"

        # Param count: prefer parenthesized form (group "params"); fall back to
        # the no-parens declaration style used widely in Sybase ASE, where
        # `@var TYPE,` lines appear between the CREATE header and the first AS.
        param_count: int | None = None
        if obj_type in ("PROCEDURE", "FUNCTION"):
            paren_params = m.group("params")
            if paren_params is not None:
                param_count = count_params(paren_params)
            else:
                as_match = re.search(r"\bAS\b", body, re.IGNORECASE)
                header_text = body[:as_match.start()] if as_match else body[:200]
                param_count = count_params_from_header(header_text)

        objects.append({
            "name": m.group("name"),
            "object_type": obj_type,
            "source_file": str(path.relative_to(root)) if path.is_relative_to(root) else str(path),
            "start_line": start_line,
            "end_line": end_line,
            "line_count": line_count,
            "param_count": param_count,
            "signals": signals,
            "complexity_hint": complexity_hint(line_count, signals),
        })

    return objects, None


def walk(root: Path) -> list[Path]:
    if root.is_file():
        return [root]
    files = []
    for suffix in SUPPORTED_SUFFIXES:
        files.extend(root.rglob(f"*{suffix}"))
    return sorted(set(files))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", help="Directory or file to scan")
    ap.add_argument("--pretty", action="store_true", help="Indent JSON output")
    ap.add_argument("--summary", action="store_true", help="One-line counts instead of full JSON")
    args = ap.parse_args()

    root = Path(args.path).resolve()
    if not root.exists():
        print(f"path does not exist: {root}", file=sys.stderr)
        return 2

    files = walk(root)
    if not files:
        print(f"no .sql/.ddl files found under {root}", file=sys.stderr)
        return 0

    all_objects: list[dict[str, Any]] = []
    errors: list[str] = []
    for f in files:
        objs, err = parse_file(f, root if root.is_dir() else root.parent)
        all_objects.extend(objs)
        if err:
            errors.append(err)

    if args.summary:
        by_type: dict[str, int] = {}
        by_complexity: dict[str, int] = {}
        for o in all_objects:
            by_type[o["object_type"]] = by_type.get(o["object_type"], 0) + 1
            by_complexity[o["complexity_hint"]] = by_complexity.get(o["complexity_hint"], 0) + 1
        summary = {
            "files_scanned": len(files),
            "objects_found": len(all_objects),
            "by_type": by_type,
            "by_complexity": by_complexity,
            "errors": len(errors),
        }
        json.dump(summary, sys.stdout)
        sys.stdout.write("\n")
        return 0

    if args.pretty:
        json.dump(all_objects, sys.stdout, indent=2)
    else:
        json.dump(all_objects, sys.stdout)
    sys.stdout.write("\n")

    if errors:
        for e in errors:
            print(e, file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
