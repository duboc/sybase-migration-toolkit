# Sybase Migration Toolkit — Gemini CLI Hooks

Hooks that turn the migration toolkit into a stateful, auditable, guarded pipeline. They run synchronously inside the Gemini CLI agent loop and are configured via `settings.json`.

## What's installed

| Hook script | Event(s) | Matcher | Purpose |
|---|---|---|---|
| `session-start.sh` | `SessionStart` | `*` | Detect a Sybase migration project, summarize phase/state, list reports present. |
| `before-tool-shell.sh` | `BeforeTool` | `run_shell_command` | Block destructive shell commands (DROP, TRUNCATE, `rm -rf reports/`, force pushes). |
| `before-tool-write.sh` | `BeforeTool` | `write_file\|replace\|edit\|create_file` | Enforce report naming convention (`NN-name.md`) and refuse writes containing secrets. |
| `after-tool-report.sh` | `AfterTool` | `write_file\|replace\|edit\|create_file` | Auto-update `reports/migration-state.json` when a numbered report is written. |
| `before-agent.sh` | `BeforeAgent` | `*` | Phase-gate validator: refuses `@spanner-schema`, `@service-extraction`, `@modernization`, `@risk-assessment` if upstream reports are missing. |
| `audit-log.sh` | `Notification`, `AfterTool` | `*` | Append every event to `.gemini/audit/migration-audit.jsonl` for compliance. |
| `pre-compress.sh` | `PreCompress` | `*` | Snapshot migration state before context compression. |

`lib/common.sh` is shared infrastructure (project-root detection, JSON helpers, report-id parsing) — don't invoke directly.

## Contract

All hooks follow the Gemini CLI hook spec strictly:

- **stdout** is a single JSON object (or empty). Anything else breaks parsing — never `echo` debug output to stdout.
- **stderr** is for logging.
- Exit `0` = allow/parse stdout. Exit `2` = system block (rare, used only for catastrophic failures).
- All hooks degrade to `allow` if `jq` is missing, with a stderr warning.

## Where files land

State and audit data live under the **project root** so they travel with the codebase:

```
<project>/
  reports/
    01-schema-profile.md
    ...
    migration-state.json        # written by after-tool-report.sh
  .gemini/
    audit/
      migration-audit.jsonl     # append-only audit trail
    snapshots/
      pre-compress-<ts>.md      # snapshots before context compression
```

## Disabling individual hooks

The toolkit's hooks are namespaced (`sybase-migration/<name>`) so you can disable any one with the standard CLI command without touching the others:

```
/hooks disable sybase-migration/before-tool-shell
```

Or remove the entry from `~/.gemini/settings.json` directly.

## Security note

Project-level hooks execute with full user privileges. Gemini CLI fingerprints them: if a script's name or command changes (e.g. via `git pull`), you'll be re-prompted before the new hook runs. Audit `hooks/` before merging any third-party PR that touches it.
