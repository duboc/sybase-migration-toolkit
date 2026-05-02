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

The agent installer (`install-agents.sh`) deploys five [Gemini CLI hooks](https://github.com/google-gemini/gemini-cli) plus one CLI utility. The hook layer is **observation + adaptive gating only** — it does not block destructive commands or scrub secrets. Its three goals:

- **Auditable** — every tool call appends a rich JSON record to `.gemini/audit/migration-audit.jsonl`. A separate review agent (or a human) can then run `hooks/audit-summary.sh --markdown` to inspect the run after the fact: which reports were produced, in what order, what is still missing, what each agent did.
- **Phase-gated and adaptive** — `before-agent.sh` denies a downstream agent when its prerequisite reports are missing, AND emits a `systemMessage` instructing the agent to run in *static-only mode* or *skip a specific report* when a required data source is absent. Sometimes the user only has source code; the gate adapts instead of demanding telemetry that does not exist.
- **Stateful** — `migration-state.json` is updated after every numbered report write so a fresh session resumes mid-pipeline.

| Hook / utility | Event(s) | What it does |
|---|---|---|
| `session-start` | `SessionStart` | Inject phase + state context. If the data-source intake is not yet captured, prompt the orchestrator to ask the user 5 yes/no questions before launching Phase 1+ agents. |
| `before-agent` | `BeforeAgent` | Deny when prereq reports are missing (with suggested next agent). Allow with a `systemMessage` when a data source is missing — agent runs in static-only mode or skips a specific report. |
| `after-tool-report` | `AfterTool` | Update `reports/migration-state.json` after every numbered report write. |
| `audit-log` | `AfterTool`, `Notification` | Append an enriched JSON record (ts, session, tool, agent, file, report ID, phase, outcome, content size) for every event. |
| `pre-compress` | `PreCompress` | Snapshot state + report inventory before context compression. |
| `audit-summary` (CLI utility, not a hook) | — | Read the audit log and emit a JSON or markdown digest. Designed for a review agent to run as a tool call and reason about whether the pipeline did its job. |

### Data-source intake (asked once, drives every downstream gate)

At the start of a project the orchestrator asks 5 yes/no questions and persists the answers to `reports/migration-state.json` under `intake_answers.data_sources`. The gate then adapts:

| Data source | When `false`, what changes |
|---|---|
| `production_telemetry` (MDA tables, sp_sysmon) | `@risk-assessment` reports 14, 15 → static-only with reduced confidence; `@dead-component` report 04 → static-only. |
| `application_logs` (APM, prod logs) | `@dead-component` report 17 → zero-reference detection only. |
| `replication_config` (Sybase RepServer files) | `@data-flow` skips report 12 entirely. |
| `iq_exports` (Sybase IQ DDL/data) | `@risk-assessment` report 16 IQ→BigQuery analysis flagged as gap. |
| `git_history` (full repo history) | `@risk-assessment` report 13 cannot use churn scoring; `@modernization` report 23 cannot use commit-history evidence. |

If `production_telemetry` AND `application_logs` are both `false`, `@dead-component` runs in pure static mode and every finding is marked confidence=`static-only`.

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

### Inspect the run with `audit-summary.sh`

```bash
hooks/audit-summary.sh --markdown          # human / LLM-readable digest
hooks/audit-summary.sh --json --pretty     # programmatic
hooks/audit-summary.sh --report 18         # all events touching report 18
hooks/audit-summary.sh --since 2026-05-02T00:00:00Z
hooks/audit-summary.sh --raw               # raw JSONL lines after filters
```

The markdown output lists: total events, time window, errors, every report written (with timestamp + size + write count), every canonical ID still missing, and activity by phase / tool / agent. A reviewer agent reads this first, then opens the specific report files to evaluate quality.

### Managing hooks

Hooks are namespaced `sybase-migration/<name>` so they can be toggled individually:

```
/hooks panel
/hooks disable sybase-migration/before-agent
/hooks enable  sybase-migration/before-agent
```

To install only the hooks (e.g., after editing them locally):

```bash
./scripts/install-agents.sh --hooks-only
```

To install agents + settings without hooks:

```bash
./scripts/install-agents.sh --no-hooks
```

See [`hooks/README.md`](hooks/README.md) for the full contract, record schema, and per-agent gating logic.

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
