# Sybase Transaction Analyzer

Analyze Sybase transaction patterns, isolation levels, and locking behavior to design Spanner-compatible transaction strategies for financial applications.

## What It Does

This skill catalogs transaction patterns across stored procedures and application code, maps Sybase isolation levels and locking hints to Spanner equivalents, and identifies distributed transactions that require database consolidation or saga pattern redesign. It produces per-pattern Spanner transaction type recommendations with code examples, ensuring financial data consistency guarantees are maintained during migration.

## When to Use

- "Analyze transaction patterns in our Sybase stored procedures"
- "Map our Sybase isolation levels to Spanner"
- "Assess locking behavior for Spanner migration"
- "Design Spanner transaction strategies for our trading platform"
- "Evaluate distributed transaction usage across our databases"
- "Review lock contention patterns in our Sybase environment"

## Installation

### Gemini CLI

```bash
gemini skills install https://github.com/duboc/gemini-cli-skills.git --path skills/sybase-transaction-analyzer
```

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/duboc/gemini-cli-skills/main/scripts/install.sh | bash -s -- sybase-transaction-analyzer
```

## Output

- **HTML Dashboard**: `./diagrams/sybase-transaction-analyzer-report.html`
- **Markdown Report**: `./reports/sybase-transaction-analyzer-<YYYYMMDDTHHMMSS>.md`

## Phase

Phase 2: Data Flow & Dependency Mapping (depends on Phase 1 outputs)

## Related Skills

- [sybase-tsql-analyzer](../sybase-tsql-analyzer/) - Phase 1: T-SQL code analysis (input)
- [sybase-data-flow-mapper](../sybase-data-flow-mapper/) - Phase 2: Cross-database dependency context
- [sybase-performance-profiler](../sybase-performance-profiler/) - Phase 2: Performance baseline
- [sybase-to-spanner-schema-designer](../sybase-to-spanner-schema-designer/) - Phase 3: Schema design (consumer)
