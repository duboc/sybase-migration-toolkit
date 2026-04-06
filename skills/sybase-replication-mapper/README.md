# Sybase Replication Mapper

A Gemini CLI skill for mapping Sybase Replication Server topology to GCP Change Data Capture architecture using Spanner Change Streams, Pub/Sub, and Dataflow.

## What It Does

This skill analyzes Sybase Replication Server configurations, replication routes, function strings, and subscription sets to produce a target CDC architecture design on GCP. It classifies function strings by complexity, documents latency SLAs, and maps each replication path to its Cloud Spanner Change Streams, Pub/Sub, or Dataflow equivalent for financial enterprise applications.

## When to Use

- "Map our Sybase Replication Server topology"
- "Inventory all RepServer routes and subscriptions"
- "Design CDC replacements for our Sybase replication"
- "Analyze function strings for migration complexity"
- "What GCP services replace our warm standby configuration?"
- "How do we replicate our active-active Sybase setup in Spanner?"

## Installation

### Gemini CLI

```bash
gemini skills install https://github.com/duboc/gemini-cli-skills.git --path skills/sybase-replication-mapper
```

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/duboc/gemini-cli-skills/main/scripts/install.sh | bash -s -- sybase-replication-mapper
```

## Output

- **HTML Dashboard**: `./diagrams/sybase-replication-topology.html`
- **Markdown Report**: `./reports/sybase-replication-mapper-<YYYYMMDDTHHMMSS>.md`

## Related Skills

- [sybase-tsql-analyzer](../sybase-tsql-analyzer/) — Analyze T-SQL stored procedures for Spanner compatibility
- [sybase-schema-profiler](../sybase-schema-profiler/) — Profile schemas and data types for Spanner conversion
- [sybase-integration-cataloger](../sybase-integration-cataloger/) — Catalog external integration points and client connections
