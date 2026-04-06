# Sybase-to-Spanner Schema Designer

Design the Cloud Spanner target schema with interleaved table hierarchies, bit-reversed sequence keys, secondary indexes, commit timestamp columns, and Change Stream definitions from Sybase source schemas.

## What It Does

This skill consumes outputs from Phase 1 and Phase 3 skills to build a consolidated source model, then transforms the Sybase physical schema into a Spanner-optimized logical schema. It replaces IDENTITY columns with bit-reversed sequences, designs interleaved table hierarchies based on access patterns and FK relationships, optimizes secondary indexes with STORING clauses, configures commit timestamps for audit tables, and defines Change Streams for CDC. It produces complete Spanner DDL with Harbourbridge/DMS configuration snippets and data validation checkpoints.

## When to Use

- "Design the Spanner schema from our Sybase source"
- "Convert our Sybase DDL to Spanner DDL"
- "Generate interleaved table design for our trading tables"
- "Optimize Spanner primary keys to avoid hotspots"
- "Create Change Stream definitions for our replication requirements"
- "Generate Harbourbridge configuration for Sybase-to-Spanner migration"

## Installation

### Gemini CLI

```bash
gemini skills install https://github.com/duboc/gemini-cli-skills.git --path skills/sybase-to-spanner-schema-designer
```

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/duboc/gemini-cli-skills/main/scripts/install.sh | bash -s -- sybase-to-spanner-schema-designer
```

## Output

- **HTML Dashboard**: `./diagrams/sybase-to-spanner-schema-designer-report.html`
- **Markdown Report**: `./reports/sybase-to-spanner-schema-designer-<YYYYMMDDTHHMMSS>.md`

## Phase

Phase 4 - Spanner Target Architecture (Skill 10 of 14)

**Dependencies:**
- sybase-schema-profiler (Phase 1) - source table DDL, column types, indexes, constraints
- sybase-performance-profiler (Phase 1) - access patterns, hot tables, query plans
- sybase-transaction-analyzer (Phase 2) - transaction boundaries, isolation levels
- sybase-analytics-assessor (Phase 3) - OLTP-classified tables only
- sybase-dead-component-detector (Phase 3) - dead objects excluded from scope
- sybase-replication-mapper (Phase 2) - replication topology for Change Stream design

## Related Skills

| Skill | Relationship |
|-------|-------------|
| **sybase-schema-profiler** | Provides source DDL, column types, indexes, and constraints |
| **sybase-performance-profiler** | Provides access patterns and query plans for index optimization |
| **sybase-transaction-analyzer** | Provides transaction scope data for interleaving decisions |
| **sybase-analytics-assessor** | Provides OLTP scope filter (only OLTP tables go to Spanner) |
| **sybase-dead-component-detector** | Provides dead object exclusions to reduce conversion scope |
| **sybase-replication-mapper** | Provides CDC requirements for Change Stream design |
| **tsql-to-application-extractor** | Consumes Spanner schema for client library code generation |
