#!/usr/bin/env bash
# AfterTool hook (matcher: write_file|replace):
# When an agent finishes writing a numbered report file (NN-name.md under reports/),
# update reports/migration-state.json so the orchestrator can resume work
# without re-reading every report on each turn.
#
# This hook is advisory: it never blocks. On any failure it allows the action
# to continue and emits a stderr warning.
#
# State file shape:
#   {
#     "current_phase": "1" | "2" | "3" | "4" | "synthesis",
#     "last_completed_report": "18-spanner-schema-design.md",
#     "reports": ["01-...", "02-...", ...],
#     "updated_at": "2026-05-02T17:13:00Z"
#   }

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOK_DIR/lib/common.sh"

EVENT="$(read_event)"
TOOL="$(event_field "$EVENT" '.tool_name')"

case "$TOOL" in
  write_file|replace|edit|create_file) ;;
  *) emit_allow ""; exit 0 ;;
esac

PATH_ARG="$(event_field "$EVENT" '.tool_input.file_path')"
[[ -z "$PATH_ARG" ]] && PATH_ARG="$(event_field "$EVENT" '.tool_input.path')"

if [[ -z "$PATH_ARG" ]]; then
  emit_allow ""
  exit 0
fi

ROOT="$(project_root)"
REPORTS="$(reports_dir)"
STATE="$(state_file)"

abs_path="$PATH_ARG"
case "$PATH_ARG" in
  /*) abs_path="$PATH_ARG" ;;
  *)  abs_path="$ROOT/$PATH_ARG" ;;
esac

# Only act on numbered reports inside reports/.
if [[ "$abs_path" != "$REPORTS"/* ]]; then
  emit_allow ""
  exit 0
fi

base="$(basename "$abs_path")"
report_id="$(report_id_for "$abs_path")"
if [[ -z "$report_id" ]]; then
  emit_allow ""
  exit 0
fi

if ! have_jq; then
  warn "jq not available; skipping migration-state.json update for $base"
  emit_allow ""
  exit 0
fi

# Map report ID to phase. Mirrors the architecture in README.md.
case "$report_id" in
  01|02|03|04|05|06) phase="1" ;;
  07|08|09|10|11|12) phase="2" ;;
  13|14|15|16|17)    phase="3" ;;
  18|19|20|21|22|23) phase="4" ;;
  24)                phase="synthesis" ;;
  *)                 phase="unknown" ;;
esac

mkdir -p "$REPORTS"

# Build the new state. Preserve any existing fields the orchestrator owns.
existing="{}"
[[ -f "$STATE" ]] && existing="$(cat "$STATE" 2>/dev/null || echo '{}')"

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Refresh `reports` from disk so manual deletions are reflected.
reports_json="[]"
if compgen -G "$REPORTS"/[0-9][0-9]-*.md >/dev/null 2>&1; then
  reports_json="$(cd "$REPORTS" && ls [0-9][0-9]-*.md 2>/dev/null | jq -R . | jq -s .)"
fi

updated="$(jq -n \
  --argjson existing "$existing" \
  --arg phase "$phase" \
  --arg last "$base" \
  --arg now "$now" \
  --argjson reports "$reports_json" \
  '$existing + {current_phase:$phase, last_completed_report:$last, updated_at:$now, reports:$reports}'
)"

if [[ -n "$updated" ]]; then
  printf '%s\n' "$updated" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
  log "migration-state.json updated: phase=$phase last=$base"
fi

emit_allow ""
