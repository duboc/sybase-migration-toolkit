# Sybase Dead Component Detector

Cross-reference static Sybase object analysis with production execution data to identify unused stored procedures, dormant tables, obsolete replication subscriptions, and dead integration endpoints safe for exclusion from the Spanner migration scope.

## What It Does

This skill parses MDA tables (monCachedProcedures, monOpenObjectActivity), sp_sysmon output, application logs, and audit trails to identify Sybase objects with zero production activity. It applies financial domain exclusion rules to prevent incorrectly flagging SOX audit code, regulatory reporting, seasonal processing, and disaster recovery procedures as dead. Each candidate is confidence-scored (HIGH/MEDIUM/LOW) and the overall migration scope reduction is quantified with effort savings estimates.

## When to Use

- "Find dead code in our Sybase databases before migration"
- "Reduce migration scope by identifying unused Sybase objects"
- "Which stored procedures have zero executions in production?"
- "Detect dormant tables and obsolete replication subscriptions"
- "Quantify scope reduction for our Spanner migration project"
- "Identify Sybase components safe to exclude from migration"

## Installation

### Gemini CLI

```bash
gemini skills install https://github.com/duboc/gemini-cli-skills.git --path skills/sybase-dead-component-detector
```

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/duboc/gemini-cli-skills/main/scripts/install.sh | bash -s -- sybase-dead-component-detector
```

## Output

- **HTML Dashboard**: `./diagrams/sybase-dead-component-detector-report.html`
- **Markdown Report**: `./reports/sybase-dead-component-detector-<YYYYMMDDTHHMMSS>.md`

## Phase

Phase 3 - Risk & Scope Reduction (Skill 8 of 14)

**Dependencies:**
- sybase-schema-profiler (Phase 1) - table and object inventory
- sybase-tsql-analyzer (Phase 1) - stored procedure inventory
- sybase-integration-cataloger (Phase 2) - integration endpoint inventory
- sybase-performance-profiler (Phase 1) - execution metrics
- sybase-replication-mapper (Phase 2) - replication subscription inventory

## Related Skills

| Skill | Relationship |
|-------|-------------|
| **sybase-schema-profiler** | Provides base object inventory for zero-hit detection |
| **sybase-tsql-analyzer** | Provides stored procedure inventory and dependency chains |
| **sybase-integration-cataloger** | Provides integration endpoint inventory (BCP, MQ, Crystal Reports) |
| **sybase-performance-profiler** | Provides execution counts and access patterns from MDA tables |
| **sybase-replication-mapper** | Provides replication subscription activity data |
| **sybase-analytics-assessor** | Uses dead component results to refine OLTP/analytics classification |
| **sybase-to-spanner-schema-designer** | Consumes dead component exclusions to reduce schema conversion scope |
