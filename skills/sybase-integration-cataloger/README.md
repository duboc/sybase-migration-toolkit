# Sybase Integration Cataloger

A Gemini CLI skill for cataloging all external integration points connecting to the Sybase ASE environment and mapping each to GCP target technologies.

## What It Does

This skill scans project files for Sybase client library references, application framework artifacts, middleware configurations, and financial messaging protocol integrations. It classifies each integration by migration complexity (DRIVER_SWAP, APP_MODIFICATION, FULL_REPLACEMENT, DECOMMISSION) and maps to GCP equivalents including Spanner client libraries, Looker, Cloud Run, and Pub/Sub.

## When to Use

- "Catalog all integrations connecting to our Sybase databases"
- "Inventory database client libraries and connection strings"
- "Map our Sybase connections to GCP target technologies"
- "Which applications use PowerBuilder DataWindows against Sybase?"
- "Assess migration effort for our FIX engine's Sybase persistence layer"
- "Find all ODBC DSNs and JDBC connections pointing to Sybase"

## Installation

### Gemini CLI

```bash
gemini skills install https://github.com/duboc/gemini-cli-skills.git --path skills/sybase-integration-cataloger
```

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/duboc/gemini-cli-skills/main/scripts/install.sh | bash -s -- sybase-integration-cataloger
```

## Output

- **HTML Dashboard**: `./diagrams/sybase-integration-catalog.html`
- **Markdown Report**: `./reports/sybase-integration-cataloger-<YYYYMMDDTHHMMSS>.md`

## Related Skills

- [sybase-tsql-analyzer](../sybase-tsql-analyzer/) — Analyze T-SQL stored procedures for Spanner compatibility
- [sybase-schema-profiler](../sybase-schema-profiler/) — Profile schemas and data types for Spanner conversion
- [sybase-replication-mapper](../sybase-replication-mapper/) — Map Replication Server topology to GCP CDC architecture
