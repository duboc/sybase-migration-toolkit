# Sybase Performance Profiler

Profile Sybase query performance and access patterns to design Spanner-optimized schemas, secondary indexes, and read/write split strategies.

## What It Does

This skill analyzes MDA table exports, sp_sysmon output, and query patterns to classify table access profiles, identify hot tables, and map financial workload timing characteristics. It produces per-table Spanner optimization recommendations including interleaved table candidates, secondary index designs with STORING clauses, stale read opportunities, and autoscaling node provisioning guidance aligned to market hours.

## When to Use

- "Profile our Sybase database performance for Spanner migration"
- "Analyze query patterns to optimize Spanner schema design"
- "Identify hot tables that need special treatment in Spanner"
- "Establish a performance baseline before migration"
- "Recommend secondary indexes for our Spanner schema"
- "Map our trading workload timing profile for Spanner autoscaling"

## Installation

### Gemini CLI

```bash
gemini skills install https://github.com/duboc/gemini-cli-skills.git --path skills/sybase-performance-profiler
```

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/duboc/gemini-cli-skills/main/scripts/install.sh | bash -s -- sybase-performance-profiler
```

## Output

- **HTML Dashboard**: `./diagrams/sybase-performance-profiler-report.html`
- **Markdown Report**: `./reports/sybase-performance-profiler-<YYYYMMDDTHHMMSS>.md`

## Phase

Phase 2: Data Flow & Dependency Mapping (depends on Phase 1 outputs)

## Related Skills

- [sybase-schema-profiler](../sybase-schema-profiler/) - Phase 1: Schema inventory (input)
- [sybase-tsql-analyzer](../sybase-tsql-analyzer/) - Phase 1: T-SQL code analysis (input)
- [sybase-data-flow-mapper](../sybase-data-flow-mapper/) - Phase 2: Data lineage context
- [sybase-transaction-analyzer](../sybase-transaction-analyzer/) - Phase 2: Transaction scope context
- [sybase-to-spanner-schema-designer](../sybase-to-spanner-schema-designer/) - Phase 3: Schema design (consumer)
