# T-SQL to Application Extractor

Extract business logic from Sybase Transact-SQL stored procedures and translate into Cloud Run microservices with Spanner client library integration, OpenAPI specifications, and saga patterns for distributed transactions.

## What It Does

This skill consumes sybase-tsql-analyzer output to prioritize stored procedures by complexity and business criticality, then translates T-SQL patterns into Java Spring Boot or Python FastAPI service code with Spanner client library integration. It designs saga patterns with Cloud Workflows for cross-database transactions, generates OpenAPI 3.0 specifications from procedure signatures, and creates a parallel-run validation framework to verify monetary calculation accuracy with zero tolerance for discrepancies.

## When to Use

- "Extract business logic from our Sybase stored procedures"
- "Convert T-SQL stored procs to Cloud Run microservices"
- "Design saga patterns for our cross-database transactions"
- "Generate OpenAPI specs from our stored procedure signatures"
- "Build a parallel-run framework to validate our migration"
- "Migrate database logic from Sybase to application layer"

## Installation

### Gemini CLI

```bash
gemini skills install https://github.com/duboc/gemini-cli-skills.git --path skills/tsql-to-application-extractor
```

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/duboc/gemini-cli-skills/main/scripts/install.sh | bash -s -- tsql-to-application-extractor
```

## Output

- **HTML Dashboard**: `./diagrams/tsql-to-application-extractor-report.html`
- **Markdown Report**: `./reports/tsql-to-application-extractor-<YYYYMMDDTHHMMSS>.md`

## Phase

Phase 4 - Spanner Target Architecture (Skill 11 of 14)

**Dependencies:**
- sybase-tsql-analyzer (Phase 1) - stored procedure classification and complexity analysis
- sybase-to-spanner-schema-designer (Phase 4) - target Spanner schema for client library code
- sybase-transaction-analyzer (Phase 2) - transaction patterns for saga design
- sybase-integration-cataloger (Phase 2) - external system integration points

## Related Skills

| Skill | Relationship |
|-------|-------------|
| **sybase-tsql-analyzer** | Provides stored procedure inventory, classification, and complexity scoring |
| **sybase-to-spanner-schema-designer** | Provides target Spanner schema for client library integration |
| **sybase-transaction-analyzer** | Provides transaction patterns and isolation levels for saga design |
| **sybase-integration-cataloger** | Provides external system integration points for service boundary design |
| **sybase-performance-profiler** | Provides execution counts for extraction priority ranking |
| **sybase-analytics-assessor** | Identifies ETL procedures suitable for Dataflow instead of Cloud Run |
