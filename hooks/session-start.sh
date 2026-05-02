#!/usr/bin/env bash
# SessionStart hook: when a Gemini CLI session begins (startup, resume, or clear),
# detect whether this looks like a Sybase migration project and inject context
# the orchestrator can use to pick up where the previous session left off.
#
# Output contract (Gemini CLI SessionStart):
#   { "decision": "allow", "context": "<markdown injected into session>" }

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOK_DIR/lib/common.sh"

EVENT="$(read_event)"
TRIGGER="$(event_field "$EVENT" '.trigger')"

if ! is_sybase_project; then
  # Not a migration target — stay silent and let the session proceed.
  emit_allow ""
  exit 0
fi

ROOT="$(project_root)"
REPORTS="$(reports_dir)"
STATE="$(state_file)"

# Build a compact status block.
present_reports=()
if [[ -d "$REPORTS" ]]; then
  while IFS= read -r f; do
    present_reports+=("$(basename "$f")")
  done < <(find "$REPORTS" -maxdepth 1 -type f -name '[0-9][0-9]-*.md' 2>/dev/null | sort)
fi

phase="unknown"
last_completed="none"
if [[ -f "$STATE" ]] && have_jq; then
  phase="$(jq -r '.current_phase // "unknown"' "$STATE" 2>/dev/null || echo unknown)"
  last_completed="$(jq -r '.last_completed_report // "none"' "$STATE" 2>/dev/null || echo none)"
fi

context_md=$(cat <<EOF
## Sybase Migration Toolkit — Session Context

**Project root:** \`$ROOT\`
**Trigger:** \`$TRIGGER\`
**Current phase:** \`$phase\`
**Last completed report:** \`$last_completed\`
**Reports present (${#present_reports[@]}):** ${present_reports[*]:-none}

The migration toolkit hooks are active. They will:
- Validate report filenames before writes (must match \`NN-name.md\` under \`reports/\`).
- Block destructive shell commands targeting Sybase, Spanner, or the reports directory.
- Auto-update \`reports/migration-state.json\` whenever a numbered report is written.
- Append every tool call to \`.gemini/audit/migration-audit.jsonl\` for compliance.

Recommended next step: invoke \`@migration-orchestrator\` to pick the next phase.
EOF
)

if have_jq; then
  jq -nc --arg ctx "$context_md" '{decision:"allow", context:$ctx}'
else
  # Without jq we cannot safely encode the multiline context. Allow silently.
  printf '{"decision":"allow"}'
fi
