#!/usr/bin/env bash
# SessionStart hook: when a Gemini CLI session begins (startup, resume, or clear),
# detect whether this looks like a Sybase migration project and inject context
# the orchestrator can use to pick up where the previous session left off.
#
# Two responsibilities:
#   1. Surface migration phase/state so the agent does not re-derive from disk.
#   2. If the data-source intake (which inputs the user actually has) is not
#      yet captured in migration-state.json, instruct the orchestrator agent
#      to ask the user before launching Phase 1+ agents. Several downstream
#      agents adapt their mode based on these answers — the gate cannot make
#      good decisions until they exist.
#
# Output contract (Gemini CLI SessionStart):
#   { "decision": "allow", "context": "<markdown injected into session>" }

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOK_DIR/lib/common.sh"

EVENT="$(read_event)"
TRIGGER="$(event_field "$EVENT" '.trigger')"

if ! is_sybase_project; then
  emit_allow ""
  exit 0
fi

ROOT="$(project_root)"
REPORTS="$(reports_dir)"
STATE="$(state_file)"

# Collected report list
present_reports=()
if [[ -d "$REPORTS" ]]; then
  while IFS= read -r f; do
    present_reports+=("$(basename "$f")")
  done < <(find "$REPORTS" -maxdepth 1 -type f -name '[0-9][0-9]-*.md' 2>/dev/null | sort)
fi

phase="unknown"
last_completed="none"
intake_complete="false"
data_sources_summary="not yet captured"

if [[ -f "$STATE" ]] && have_jq; then
  phase="$(jq -r '.current_phase // "unknown"' "$STATE" 2>/dev/null || echo unknown)"
  last_completed="$(jq -r '.last_completed_report // "none"' "$STATE" 2>/dev/null || echo none)"
  if jq -e '.intake_answers.data_sources' "$STATE" >/dev/null 2>&1; then
    intake_complete="true"
    # Render a one-line summary like: "telemetry: yes, logs: no, replication: yes, iq: no, git: yes"
    data_sources_summary="$(jq -r '
      .intake_answers.data_sources
      | "telemetry: " + (.production_telemetry|tostring)
        + ", logs: " + (.application_logs|tostring)
        + ", replication: " + (.replication_config|tostring)
        + ", iq: " + (.iq_exports|tostring)
        + ", git: " + (.git_history|tostring)
    ' "$STATE" 2>/dev/null || echo "(parse error)")"
  fi
fi

# Build the intake-prompt block conditionally.
if [[ "$intake_complete" == "true" ]]; then
  intake_block="**Data-source intake:** captured (\`$data_sources_summary\`)."
else
  intake_block=$(cat <<'EOF'
**Data-source intake (REQUIRED before Phase 1+ agents).** This project's `migration-state.json` does not yet record which inputs are available. Several agents adapt their mode based on these answers — `before-agent.sh` cannot give good signal until they exist.

When `@migration-orchestrator` (or the user directly) is next active, ask the user these 5 yes/no questions and persist answers to `migration-state.json` under `intake_answers.data_sources`:

| Key | Question | Affects |
|---|---|---|
| `production_telemetry` | Do you have Sybase MDA-table dumps, `sp_sysmon` output, or other monitoring exports? | `@risk-assessment` (reports 14, 15) and `@dead-component` (execution frequency) — without it, both run in static-only mode with reduced confidence. |
| `application_logs` | Do you have application logs, APM data, or audit trails for the Java/middle tier? | `@dead-component` Java-side (report 17). Without it, only static reachability. |
| `replication_config` | Do you have Sybase Replication Server config files (`rs_*.cfg`, subscription dumps)? | `@data-flow` report 12. Without it, the report is skipped. |
| `iq_exports` | Do you have Sybase IQ schema or data exports (only relevant if IQ is in scope)? | `@risk-assessment` report 16 IQ→BigQuery analysis. |
| `git_history` | Do you have full git history for the source repos (not just snapshot)? | `@risk-assessment` report 13 churn-based scoring (optional). |

Persist the answers like this:

```json
{
  "intake_answers": {
    "data_sources": {
      "source_code": true,
      "production_telemetry": false,
      "application_logs": false,
      "replication_config": true,
      "iq_exports": false,
      "git_history": true
    }
  }
}
```

`source_code` is always assumed `true` (otherwise nothing to migrate). Once persisted, `before-agent.sh` will read these fields and either allow downstream agents in their full mode, allow them in static-only mode with a clear systemMessage, or skip a specific report.
EOF
)
fi

context_md=$(cat <<EOF
## Sybase Migration Toolkit — Session Context

**Project root:** \`$ROOT\`
**Trigger:** \`$TRIGGER\`
**Current phase:** \`$phase\`
**Last completed report:** \`$last_completed\`
**Reports present (${#present_reports[@]}):** ${present_reports[*]:-none}

$intake_block

The migration toolkit hooks are active and observation-only:
- Every tool call and notification is appended to \`.gemini/audit/migration-audit.jsonl\` for after-the-fact review.
- Use \`hooks/audit-summary.sh --markdown\` (or \`--json\`) to get a structured digest of what the pipeline did, what reports were produced, and what is still missing.
- \`reports/migration-state.json\` is updated automatically by the AfterTool hook whenever a numbered report is written.
- \`before-agent.sh\` adaptively gates downstream agents based on which prerequisite reports exist AND which data sources the user reported.
- Pre-compression snapshots land at \`.gemini/snapshots/pre-compress-*.md\`.

Recommended next step: invoke \`@migration-orchestrator\` to pick the next phase.
EOF
)

if have_jq; then
  jq -nc --arg ctx "$context_md" '{decision:"allow", context:$ctx}'
else
  printf '{"decision":"allow"}'
fi
