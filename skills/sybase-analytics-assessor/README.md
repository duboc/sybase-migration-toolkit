# Sybase Analytics Assessor

Assess whether the Sybase database or parts of it serve analytical workloads to recommend a BigQuery vs Spanner split strategy with CDC pipeline designs for hybrid tables.

## What It Does

This skill identifies Sybase IQ instances (automatically classified as ANALYTICS), detects star/snowflake schemas in ASE databases, classifies query patterns as OLTP or ANALYTICS, and inventories reporting tool connections (Crystal Reports, Business Objects, Tableau). It produces a per-table workload classification (OLTP to Cloud Spanner, ANALYTICS to BigQuery, HYBRID with Change Streams CDC, ARCHIVE to Cloud Storage) with CDC pipeline designs and bulk migration sizing estimates.

## When to Use

- "Assess analytics workloads in our Sybase environment"
- "Which Sybase tables should go to BigQuery vs Spanner?"
- "Identify reporting databases and BI tool connections"
- "Plan the OLTP/analytics split for our migration"
- "Design CDC pipelines for hybrid OLTP/analytics tables"
- "Classify our Sybase IQ databases for BigQuery migration"

## Installation

### Gemini CLI

```bash
gemini skills install https://github.com/duboc/gemini-cli-skills.git --path skills/sybase-analytics-assessor
```

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/duboc/gemini-cli-skills/main/scripts/install.sh | bash -s -- sybase-analytics-assessor
```

## Output

- **HTML Dashboard**: `./diagrams/sybase-analytics-assessor-report.html`
- **Markdown Report**: `./reports/sybase-analytics-assessor-<YYYYMMDDTHHMMSS>.md`

## Phase

Phase 3 - Risk & Scope Reduction (Skill 9 of 14)

**Dependencies:**
- sybase-schema-profiler (Phase 1) - schema structure and table metadata
- sybase-performance-profiler (Phase 1) - read/write ratios and access patterns
- sybase-integration-cataloger (Phase 2) - reporting tool connections

## Related Skills

| Skill | Relationship |
|-------|-------------|
| **sybase-schema-profiler** | Provides table DDL, column types, and FK relationships for schema pattern detection |
| **sybase-performance-profiler** | Provides read/write ratios and query patterns for workload classification |
| **sybase-integration-cataloger** | Provides reporting connection inventory (Crystal Reports, BI tools) |
| **sybase-dead-component-detector** | Provides dead object exclusions to refine classification scope |
| **sybase-to-spanner-schema-designer** | Consumes OLTP classification to determine Spanner schema scope |
| **sybase-replication-mapper** | Provides CDC requirements for hybrid table pipeline design |
