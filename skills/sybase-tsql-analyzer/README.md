# Sybase T-SQL Analyzer

A Gemini CLI skill for parsing Sybase ASE Transact-SQL stored procedures, triggers, and functions to produce a Spanner-compatible migration inventory.

## What It Does

This skill reads Sybase DDL exports (defncopy, ddlgen, isql output), classifies every stored procedure by complexity and business purpose, and produces a Cloud Spanner compatibility matrix. It identifies incompatible constructs such as server-side cursors, temp tables, COMPUTE BY, and identity columns, mapping each to its Spanner migration strategy.

## When to Use

- "Analyze all Sybase stored procedures in this project"
- "Inventory our Sybase T-SQL code for Spanner migration"
- "Assess the complexity of our Sybase procedures"
- "Which Sybase constructs are incompatible with Cloud Spanner?"
- "Map our settlement procedures for migration planning"
- "Flag all cursors, temp tables, and identity columns in our Sybase code"

## Installation

### Gemini CLI

```bash
gemini skills install https://github.com/duboc/gemini-cli-skills.git --path skills/sybase-tsql-analyzer
```

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/duboc/gemini-cli-skills/main/scripts/install.sh | bash -s -- sybase-tsql-analyzer
```

## Output

- **HTML Dashboard**: `./diagrams/sybase-tsql-inventory.html`
- **Markdown Report**: `./reports/sybase-tsql-analyzer-<YYYYMMDDTHHMMSS>.md`

## Related Skills

- [sybase-schema-profiler](../sybase-schema-profiler/) — Profile schemas and data types for Spanner conversion
- [sybase-replication-mapper](../sybase-replication-mapper/) — Map Replication Server topology to GCP CDC architecture
- [sybase-integration-cataloger](../sybase-integration-cataloger/) — Catalog external integration points and client connections
