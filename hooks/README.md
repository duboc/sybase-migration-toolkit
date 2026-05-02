# Sybase Migration Toolkit — Gemini CLI Hooks

The hook layer is **observation + adaptive gating only**. It does not block destructive commands or scrub secrets — that responsibility lives outside the toolkit. The hooks exist to make the migration pipeline:

- **Auditable** — every tool call is appended to `.gemini/audit/migration-audit.jsonl` with enough context for a separate review agent to inspect what happened.
- **Phase-gated** — downstream agents refuse to run until their prerequisite reports exist, and **adapt their mode** (static-only vs full) based on which data sources the user reported.
- **Stateful** — `migration-state.json` is updated after every numbered report write so a fresh session can resume mid-pipeline.

## Hook inventory

| Hook | Event(s) | Purpose | Blocks? |
|---|---|---|---|
| `session-start.sh` | `SessionStart` | Inject phase / state context. If `intake_answers.data_sources` is missing, prompt the orchestrator to ask the user the 5 data-source questions before launching Phase 1+ agents. | No. |
| `before-agent.sh` | `BeforeAgent` | (1) Deny when prerequisite reports are missing, including a suggested next agent. (2) Allow with a `systemMessage` instructing the agent to run in static-only mode or skip a specific report when a required data source is absent. | Only on missing prereqs. |
| `after-tool-report.sh` | `AfterTool` | Update `migration-state.json` whenever a numbered report is written. | No. |
| `audit-log.sh` | `AfterTool`, `Notification` | Append a rich JSON record (timestamp, session, tool, agent, file, report ID, phase, outcome, size) for every event so a reviewer can reconstruct the run. | No. |
| `pre-compress.sh` | `PreCompress` | Snapshot state and report inventory before context compression. | No. |

`audit-summary.sh` and `lib/common.sh` are **not hooks** — `lib/common.sh` is shared infrastructure, and `audit-summary.sh` is a stand-alone CLI utility for review agents (see below).

## Adaptive gating: how it works

`before-agent.sh` decides mode based on `migration-state.json` → `intake_answers.data_sources`:

| Agent | Data source missing | Hook behavior |
|---|---|---|
| `@risk-assessment` | `production_telemetry` | Allow + systemMessage: run reports 14, 15 static-only with reduced confidence. |
| `@risk-assessment` | `git_history` | Allow + systemMessage: skip churn-based scoring in report 13. |
| `@risk-assessment` | `iq_exports` (with IQ in scope) | Allow + systemMessage: report 16 incomplete; flag as gap. |
| `@dead-component` | both `production_telemetry` and `application_logs` | Allow + systemMessage: pure static mode; zero-reference detection only. |
| `@dead-component` | `production_telemetry` only | Allow + systemMessage: report 04 static; report 17 uses logs. |
| `@dead-component` | `application_logs` only | Allow + systemMessage: report 17 static; report 04 uses MDA. |
| `@data-flow` | `replication_config` | Allow + systemMessage: skip report 12 entirely. |
| `@modernization` | `git_history` | Allow + systemMessage: rely on dependency manifests only for report 23. |

If the intake itself is missing, the hook still allows the run but emits a strong systemMessage telling the agent to ask the user before doing work.

## Review path: `audit-summary.sh`

A separate agent (or a human) can inspect the run after the fact:

```bash
# Markdown digest for a reviewer agent to read
hooks/audit-summary.sh --markdown

# JSON for programmatic consumption
hooks/audit-summary.sh --json --pretty

# Just the events for a single report
hooks/audit-summary.sh --report 18

# Events since a given UTC timestamp
hooks/audit-summary.sh --since 2026-05-02T00:00:00Z

# Raw JSONL lines passing the filters
hooks/audit-summary.sh --raw
```

The summary tells the reviewer: how many events fired, the time window, which canonical reports (01–24) have been written and which are still missing, activity by phase / tool / agent, and the list of files touched. A reviewer agent can chain this with reads of the actual report files to judge whether the work was done correctly.

## Audit record shape

Each line in `migration-audit.jsonl` is a JSON object:

```json
{
  "ts":              "2026-05-02T17:55:20Z",
  "session":         "<GEMINI_SESSION_ID>",
  "event":           "AfterTool" | "Notification" | ...,
  "tool":            "write_file" | "replace" | ...,
  "agent":           "sybase-inventory" | null,
  "file":            "reports/01-schema-profile.md" | null,
  "report_id":       "01" | null,
  "phase":           "1" | "2" | "3" | "4" | "synthesis" | null,
  "outcome":         "success" | "error",
  "command_preview": "first 240 chars of any shell command",
  "input_preview":   "first 240 chars of any write content",
  "size":            length of write content (or null)
}
```

Phase is derived from `report_id` automatically — the reviewer does not need to map IDs to phases manually.

## Filesystem layout

```
<project>/
  reports/
    01-schema-profile.md
    ...
    migration-state.json        # updated by after-tool-report.sh, owned by orchestrator
  .gemini/
    audit/
      migration-audit.jsonl     # append-only, by audit-log.sh
    snapshots/
      pre-compress-<ts>.md      # by pre-compress.sh
```

## Hook contract reminders

All hooks follow the Gemini CLI hook spec:

- **stdout** is exactly one JSON object (or empty). Anything else breaks parsing.
- **stderr** is for logging.
- Exit `0` = allow / parse stdout. Exit `2` = system block (we do not use this).
- All hooks degrade to `allow` if `jq` is missing, with a stderr warning.

## Disabling individual hooks

The toolkit's hooks are namespaced (`sybase-migration/<name>`) so each can be toggled independently:

```
/hooks panel
/hooks disable sybase-migration/before-agent
/hooks enable  sybase-migration/before-agent
```

To turn off the entire toolkit's hook layer at install time, pass `--no-hooks` to `install-agents.sh`.
