# Sybase Migration Toolkit

A collection of [Gemini CLI](https://github.com/google-gemini/gemini-cli) skills, agents, and hooks for migrating Sybase ASE databases to Cloud Spanner in financial enterprise environments.

The toolkit ships three coordinated layers:

- **Skills** — focused, on-demand expertise (12 skills across 4 phases).
- **Agents** — autonomous specialists that produce numbered reports (9 agents).
- **Hooks** — Gemini CLI hooks that turn the pipeline into a stateful, auditable, guarded workflow (7 hooks).

---

## Migration Subagents

Nine specialized Gemini CLI subagents that coordinate a complete Sybase ASE to Cloud Spanner migration pipeline. Each agent produces numbered reports that downstream agents consume as prerequisites -- no recursive subagent calls, just file-based coordination.

### Quick Install

```bash
# Install all 9 agents + settings (user scope, recommended)
curl -fsSL https://raw.githubusercontent.com/duboc/sybase-migration-toolkit/main/scripts/install-agents.sh | bash

# Install to current project only
curl -fsSL https://raw.githubusercontent.com/duboc/sybase-migration-toolkit/main/scripts/install-agents.sh | bash -s -- --scope project
```

### Agent Catalog

| # | Agent | Phase | Reports | Description |
|---|-------|:-----:|---------|-------------|
| 1 | `@sybase-inventory` | 1 | 01-03, 05-06 | Schema profiling, T-SQL analysis, stored proc complexity, SBOM, batch job scanning |
| 2 | `@dead-component` | 1, 3 | 04, 17 | Dead code detection with financial domain preservation rules, scope reduction |
| 3 | `@data-flow` | 2 | 07, 08, 12 | Data flow mapping, cross-DB dependency tracing, replication topology |
| 4 | `@integration-catalog` | 2 | 09-11 | JDBC/SOAP/MQ integration catalog, ESB analysis, routing extraction |
| 5 | `@risk-assessment` | 3 | 13-16 | Business risk scoring, performance profiling, transaction analysis, OLTP/analytics split |
| 6 | `@spanner-schema` | 4 | 18 | Cloud Spanner DDL with interleaved tables, bit-reversed sequences, Change Streams |
| 7 | `@service-extraction` | 4 | 19-20 | T-SQL business logic to Cloud Run microservices with OpenAPI specs |
| 8 | `@modernization` | 4 | 21-23 | ESB-to-event-driven, batch-to-serverless, Spring Boot upgrade paths |
| 9 | `@migration-orchestrator` | All | 24 | Master orchestrator: 30-question intake, phase gates, state management |

### Execution Order

```
Phase 1 (parallel):  @sybase-inventory + @dead-component
Phase 2 (parallel):  @data-flow + @integration-catalog
Phase 3:             @risk-assessment + @dead-component (pass 2)
Phase 4 (parallel):  @spanner-schema + @service-extraction + @modernization
Synthesis:           @migration-orchestrator
```

### Usage

1. **Place your Sybase source code** in a project directory (SQL files, Java apps, configs).

2. **Start with the orchestrator** for guided execution:
   ```
   gemini> @migration-orchestrator Analyze this Sybase system for Cloud Spanner migration
   ```

3. **Or run individual agents** for targeted analysis:
   ```
   gemini> @sybase-inventory Profile the schema and stored procedures in this codebase
   gemini> @risk-assessment Assess migration risks based on reports 01-12
   gemini> @spanner-schema Design the Spanner schema from the inventory reports
   ```

4. **Reports are written** to `<project>/reports/` as numbered markdown files (01-24).

### Architecture

```
                    +-------------------------+
                    | migration-orchestrator  |
                    |   (coordinates phases)  |
                    +----------+--------------+
                               |
          Phase 1              |              Phase 2
    +----------------+   +-----+-----+   +-------------------+
    | sybase-        |   | dead-     |   | data-flow         |
    | inventory      |   | component |   | integration-      |
    | (01-03,05-06)  |   | (04, 17)  |   | catalog (07-12)   |
    +-------+--------+   +-----+-----+   +---------+---------+
            |                   |                   |
            +-------------------+-------------------+
                               |
                          Phase 3
                    +------------------+
                    | risk-assessment  |
                    | (13-16)          |
                    +--------+---------+
                             |
          Phase 4            |
    +-----------+   +--------+--------+   +----------------+
    | spanner-  |   | service-        |   | modernization  |
    | schema    |   | extraction      |   | (21-23)        |
    | (18)      |   | (19-20)         |   |                |
    +-----------+   +-----------------+   +----------------+
```

---

## Skills

### Phase 1: Sybase Inventory & Discovery

| Skill | Description | Install |
|-------|-------------|---------|
| [sybase-tsql-analyzer](skills/sybase-tsql-analyzer/) | Parse Sybase T-SQL stored procedures, classify by complexity, and flag Spanner-incompatible constructs | `curl -fsSL https://raw.githubusercontent.com/duboc/sybase-migration-toolkit/main/scripts/install.sh \| bash -s -- sybase-tsql-analyzer` |
| [sybase-schema-profiler](skills/sybase-schema-profiler/) | Profile Sybase schemas, data types, and indexes to assess Spanner conversion complexity and hotspot risks | `curl -fsSL https://raw.githubusercontent.com/duboc/sybase-migration-toolkit/main/scripts/install.sh \| bash -s -- sybase-schema-profiler` |
| [sybase-replication-mapper](skills/sybase-replication-mapper/) | Catalog Replication Server configs and topology to design Change Streams and Pub/Sub replacements | `curl -fsSL https://raw.githubusercontent.com/duboc/sybase-migration-toolkit/main/scripts/install.sh \| bash -s -- sybase-replication-mapper` |
| [sybase-integration-cataloger](skills/sybase-integration-cataloger/) | Catalog Open Client/Server, JDBC, PowerBuilder, Crystal Reports, MQ, and FIX/SWIFT connections | `curl -fsSL https://raw.githubusercontent.com/duboc/sybase-migration-toolkit/main/scripts/install.sh \| bash -s -- sybase-integration-cataloger` |

### Phase 2: Data Flow & Dependency Mapping

| Skill | Description | Install |
|-------|-------------|---------|
| [sybase-data-flow-mapper](skills/sybase-data-flow-mapper/) | Trace cross-database references, proxy table federations, and batch ETL chains for migration ordering | `curl -fsSL https://raw.githubusercontent.com/duboc/sybase-migration-toolkit/main/scripts/install.sh \| bash -s -- sybase-data-flow-mapper` |
| [sybase-transaction-analyzer](skills/sybase-transaction-analyzer/) | Analyze transaction patterns, isolation levels, and locking behavior for Spanner transaction strategy | `curl -fsSL https://raw.githubusercontent.com/duboc/sybase-migration-toolkit/main/scripts/install.sh \| bash -s -- sybase-transaction-analyzer` |
| [sybase-performance-profiler](skills/sybase-performance-profiler/) | Profile query performance from MDA tables to design Spanner indexes and read/write split strategies | `curl -fsSL https://raw.githubusercontent.com/duboc/sybase-migration-toolkit/main/scripts/install.sh \| bash -s -- sybase-performance-profiler` |

### Phase 3: Risk & Scope Reduction

| Skill | Description | Install |
|-------|-------------|---------|
| [sybase-dead-component-detector](skills/sybase-dead-component-detector/) | Identify unused Sybase objects safe for migration exclusion with financial domain preservation rules | `curl -fsSL https://raw.githubusercontent.com/duboc/sybase-migration-toolkit/main/scripts/install.sh \| bash -s -- sybase-dead-component-detector` |
| [sybase-analytics-assessor](skills/sybase-analytics-assessor/) | Assess OLTP vs analytics workloads to recommend Spanner/BigQuery split strategy | `curl -fsSL https://raw.githubusercontent.com/duboc/sybase-migration-toolkit/main/scripts/install.sh \| bash -s -- sybase-analytics-assessor` |

### Phase 4: Spanner Target Architecture

| Skill | Description | Install |
|-------|-------------|---------|
| [sybase-to-spanner-schema-designer](skills/sybase-to-spanner-schema-designer/) | Design Spanner schema with interleaved tables, bit-reversed keys, Change Streams, and optimized DDL | `curl -fsSL https://raw.githubusercontent.com/duboc/sybase-migration-toolkit/main/scripts/install.sh \| bash -s -- sybase-to-spanner-schema-designer` |
| [tsql-to-application-extractor](skills/tsql-to-application-extractor/) | Extract T-SQL business logic into Cloud Run microservices with Spanner client libs and saga patterns | `curl -fsSL https://raw.githubusercontent.com/duboc/sybase-migration-toolkit/main/scripts/install.sh \| bash -s -- tsql-to-application-extractor` |

### Orchestration

| Skill | Description | Install |
|-------|-------------|---------|
| [sybase-spanner-migration-orchestrator](skills/sybase-spanner-migration-orchestrator/) | Orchestrate the full Sybase-to-Spanner migration lifecycle across 4 phases, coordinating 11 skills with compliance gates and executive dashboards | `curl -fsSL https://raw.githubusercontent.com/duboc/sybase-migration-toolkit/main/scripts/install.sh \| bash -s -- sybase-spanner-migration-orchestrator` |

---

## Hooks

The agent installer (`install-agents.sh`) also deploys seven [Gemini CLI hooks](https://github.com/google-gemini/gemini-cli) that fire during the agent loop. They make the pipeline:

- **Stateful** — `migration-state.json` is updated automatically after every report write.
- **Guarded** — destructive shell commands and writes containing secrets are blocked before execution.
- **Auditable** — every tool call is appended to `.gemini/audit/migration-audit.jsonl` for compliance review.
- **Phase-gated** — downstream agents (`@spanner-schema`, `@service-extraction`, `@modernization`, `@risk-assessment`) refuse to run until their prerequisite reports exist.

| Hook | Event | Matcher | What it does |
|---|---|---|---|
| `session-start` | `SessionStart` | `*` | Detects a Sybase project and injects the current phase, last completed report, and reports-present list into the session. |
| `before-tool-shell` | `BeforeTool` | `run_shell_command` | Blocks `DROP`, `TRUNCATE`, `DELETE FROM`, `rm -rf reports/`, force pushes, fork bombs, direct DML against Sybase/Spanner instances. |
| `before-tool-write` | `BeforeTool` | `write_file\|replace\|edit\|create_file` | Enforces `NN-name.md` report naming under `reports/`; refuses writes containing AWS/GCP/GitHub/Slack tokens, PEM keys, or embedded passwords. |
| `after-tool-report` | `AfterTool` | `write_file\|replace\|edit\|create_file` | Updates `reports/migration-state.json` with the new phase, the last completed report, and a fresh report list. |
| `before-agent` | `BeforeAgent` | `*` | Phase-gate validator. Refuses `@spanner-schema` until reports 01-03, 13-16 are present; similar gates for the other downstream agents. |
| `audit-log` | `AfterTool`, `Notification` | `*` | Appends a JSONL record (timestamp, session, tool, file, command preview) to `.gemini/audit/migration-audit.jsonl`. |
| `pre-compress` | `PreCompress` | `*` | Snapshots `migration-state.json` and the report inventory to `.gemini/snapshots/pre-compress-<ts>.md` so the post-compression agent can re-orient cheaply. |

### Where things land

```
<project>/
  reports/
    01-schema-profile.md        # written by @sybase-inventory
    ...
    migration-state.json        # written by after-tool-report.sh
  .gemini/
    audit/
      migration-audit.jsonl     # append-only, by audit-log.sh
    snapshots/
      pre-compress-<ts>.md      # by pre-compress.sh
```

### Managing hooks

Hooks are namespaced `sybase-migration/<name>` so they can be toggled individually without touching the others:

```
/hooks panel
/hooks disable sybase-migration/before-tool-shell
/hooks enable  sybase-migration/before-tool-shell
```

To install only the hooks (e.g., after editing them locally):

```bash
./scripts/install-agents.sh --hooks-only
```

To install agents + settings without hooks:

```bash
./scripts/install-agents.sh --no-hooks
```

See [`hooks/README.md`](hooks/README.md) for the contract details and security notes.

---

## Settings Configuration

These skills enforce a **Multi-Turn Deep Analysis Mandate** and require increased turn/time/output limits. Update your `~/.gemini/settings.json`:

```json
{
  "agents": {
    "overrides": {
      "generalist": {
        "enabled": true,
        "runConfig": {
          "maxTurns": 100,
          "maxTimeMinutes": 45
        }
      },
      "codebase_investigator": {
        "enabled": true,
        "runConfig": {
          "maxTurns": 100,
          "maxTimeMinutes": 45
        }
      },
      "sybase-spanner-migration-orchestrator": {
        "enabled": true,
        "runConfig": {
          "maxTurns": 150,
          "maxTimeMinutes": 60
        }
      }
    }
  },
  "modelConfigs": {
    "overrides": [
      {
        "match": {
          "overrideScope": "generalist"
        },
        "modelConfig": {
          "generateContentConfig": {
            "maxOutputTokens": 65000
          }
        }
      },
      {
        "match": {
          "overrideScope": "codebase_investigator"
        },
        "modelConfig": {
          "generateContentConfig": {
            "maxOutputTokens": 65000
          }
        }
      }
    ]
  }
}
```

All agents use `gemini-3.1-pro-preview` with low temperature (0.1-0.3) for deterministic analysis output.

## Installation

### Method 1: One-liner with curl

```bash
curl -fsSL https://raw.githubusercontent.com/duboc/sybase-migration-toolkit/main/scripts/install.sh | bash -s -- <skill-name>
```

Install to user scope:

```bash
curl -fsSL https://raw.githubusercontent.com/duboc/sybase-migration-toolkit/main/scripts/install.sh | bash -s -- <skill-name> --scope user
```

### Method 2: Manual download

1. Clone this repository.
2. Copy the desired skill folder into your Gemini skills directory:
   ```bash
   cp -r skills/sybase-tsql-analyzer ~/.gemini/skills/sybase-tsql-analyzer
   ```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on creating and submitting new skills.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
