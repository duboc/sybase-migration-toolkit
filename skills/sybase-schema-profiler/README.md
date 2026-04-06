# Sybase Schema Profiler

A Gemini CLI skill for profiling Sybase ASE database schemas and producing Cloud Spanner conversion plans with hotspot risk assessment.

## What It Does

This skill analyzes Sybase ASE table structures, data types, indexes, constraints, and partitioning strategies to generate a comprehensive Cloud Spanner schema conversion plan. It identifies monotonically increasing key hotspot risks, recommends interleaved table hierarchies, and maps every Sybase data type to its Spanner equivalent with precision validation for financial applications.

## When to Use

- "Profile our Sybase database schema for Spanner migration"
- "Map Sybase data types to Cloud Spanner equivalents"
- "Which tables have hotspot risk from IDENTITY columns?"
- "Recommend interleaved table design for our Sybase schema"
- "Assess schema migration complexity for our trading database"
- "Check MONEY column precision for Spanner NUMERIC mapping"

## Installation

### Gemini CLI

```bash
gemini skills install https://github.com/duboc/gemini-cli-skills.git --path skills/sybase-schema-profiler
```

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/duboc/gemini-cli-skills/main/scripts/install.sh | bash -s -- sybase-schema-profiler
```

## Output

- **HTML Dashboard**: `./diagrams/sybase-schema-profile.html`
- **Markdown Report**: `./reports/sybase-schema-profiler-<YYYYMMDDTHHMMSS>.md`

## Related Skills

- [sybase-tsql-analyzer](../sybase-tsql-analyzer/) — Analyze T-SQL stored procedures for Spanner compatibility
- [sybase-replication-mapper](../sybase-replication-mapper/) — Map Replication Server topology to GCP CDC architecture
- [sybase-integration-cataloger](../sybase-integration-cataloger/) — Catalog external integration points and client connections
