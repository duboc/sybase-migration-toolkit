# Sybase Data Flow Mapper

Trace data flows across the Sybase ecosystem to build a comprehensive data lineage graph for Cloud Spanner migration ordering.

## What It Does

This skill analyzes cross-database references, proxy table federations, ASE-to-IQ data loading pipelines, and batch ETL chains to build a directed acyclic graph of migration dependencies. It produces a recommended migration wave plan that ensures databases are migrated in the correct order, with tightly coupled databases identified for co-migration.

## When to Use

- "Map data flows across our Sybase databases"
- "Trace cross-database dependencies for migration planning"
- "Build a data lineage graph for our trading platform"
- "Determine the migration sequence for our Sybase environment"
- "Analyze proxy table federations in our Sybase setup"
- "Trace batch ETL chains across our databases"

## Installation

### Gemini CLI

```bash
gemini skills install https://github.com/duboc/gemini-cli-skills.git --path skills/sybase-data-flow-mapper
```

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/duboc/gemini-cli-skills/main/scripts/install.sh | bash -s -- sybase-data-flow-mapper
```

## Output

- **HTML Dashboard**: `./diagrams/sybase-data-flow-mapper-report.html`
- **Markdown Report**: `./reports/sybase-data-flow-mapper-<YYYYMMDDTHHMMSS>.md`

## Phase

Phase 2: Data Flow & Dependency Mapping (depends on Phase 1 outputs)

## Related Skills

- [sybase-tsql-analyzer](../sybase-tsql-analyzer/) - Phase 1: T-SQL code analysis (input)
- [sybase-schema-profiler](../sybase-schema-profiler/) - Phase 1: Schema inventory (input)
- [sybase-transaction-analyzer](../sybase-transaction-analyzer/) - Phase 2: Transaction pattern analysis
- [sybase-performance-profiler](../sybase-performance-profiler/) - Phase 2: Performance baseline
- [sybase-to-spanner-schema-designer](../sybase-to-spanner-schema-designer/) - Phase 3: Schema design (consumer)
