#!/usr/bin/env bash
# BeforeTool hook (matcher: run_shell_command):
# Block destructive operations that could damage source data, target Spanner
# instances, or already-generated migration reports. Financial workloads
# require a hard stop on these patterns regardless of model intent.
#
# Output contract:
#   exit 0 + {"decision":"deny","reason":"..."}  -> blocks the call
#   exit 0 + {"decision":"allow"}                 -> proceeds

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOK_DIR/lib/common.sh"

EVENT="$(read_event)"
TOOL="$(event_field "$EVENT" '.tool_name')"
CMD="$(event_field "$EVENT" '.tool_input.command')"

# Only act on shell tools. Pass through otherwise.
case "$TOOL" in
  run_shell_command|shell|bash) ;;
  *) emit_allow ""; exit 0 ;;
esac

if [[ -z "$CMD" ]]; then
  emit_allow ""
  exit 0
fi

# Patterns that should never be auto-executed during a migration assessment.
# We err on the side of blocking; the user can override by running manually.
deny_patterns=(
  # Database destruction
  '(^|[^a-zA-Z_])DROP[[:space:]]+(DATABASE|SCHEMA|TABLE|INDEX|PROCEDURE|TRIGGER|VIEW)'
  '(^|[^a-zA-Z_])TRUNCATE[[:space:]]+TABLE'
  '(^|[^a-zA-Z_])DELETE[[:space:]]+FROM[[:space:]]+[^[:space:]]+[[:space:]]*(;|$)'
  # Spanner CLI mutations
  'gcloud[[:space:]]+spanner[[:space:]]+(databases|instances)[[:space:]]+delete'
  # Wipe of the reports directory or migration state
  'rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f?|-rf|-fr)[[:space:]]+.*reports'
  'rm[[:space:]]+(-[a-zA-Z]*f[a-zA-Z]*|-rf|-fr)[[:space:]]+.*migration-state\.json'
  # General catastrophe
  'rm[[:space:]]+-rf[[:space:]]+/([[:space:]]|$)'
  ':\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:'
  # Force pushes / rewrites of git history
  'git[[:space:]]+push[[:space:]]+.*--force'
  'git[[:space:]]+reset[[:space:]]+--hard'
)

for pat in "${deny_patterns[@]}"; do
  if echo "$CMD" | grep -qiE "$pat"; then
    reason="Blocked by sybase-migration toolkit: command matches destructive pattern '${pat}'. Run manually if you have explicit authorization; the migration agents must not execute this automatically."
    emit_deny "$reason"
    exit 0
  fi
done

# Heuristic: writes to actual Sybase/Spanner instances via isql/sqlcmd/spanner CLI.
# Allow read-only invocations; block obvious DDL/DML execution.
if echo "$CMD" | grep -qiE '(^|[[:space:]])(isql|sqlcmd|spanner-cli)([[:space:]]|$)'; then
  if echo "$CMD" | grep -qiE '(INSERT|UPDATE|DELETE|DROP|TRUNCATE|CREATE|ALTER)[[:space:]]'; then
    emit_deny "Blocked: direct DDL/DML against a Sybase/Spanner instance is not permitted from migration agents. Generate the DDL into a report file instead."
    exit 0
  fi
fi

emit_allow ""
