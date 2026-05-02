#!/usr/bin/env bash
# BeforeAgent hook:
# Enforce phase-gate prerequisites before a downstream migration agent runs.
# For example, @spanner-schema needs the Phase 1-3 reports to exist; running it
# without those reports produces low-quality output that wastes a context budget.
#
# Output contract:
#   exit 0 + {"decision":"deny","reason":"..."}  -> blocks turn, surfaces reason
#   exit 0 + {"decision":"allow", systemMessage} -> proceeds, message shown

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOK_DIR/lib/common.sh"

EVENT="$(read_event)"
AGENT="$(event_field "$EVENT" '.agent')"
[[ -z "$AGENT" ]] && AGENT="$(event_field "$EVENT" '.agent_name')"
[[ -z "$AGENT" ]] && AGENT="$(event_field "$EVENT" '.tool_input.agent')"

# Only enforce gates for our migration agents. Pass through everything else.
case "$AGENT" in
  spanner-schema|service-extraction|modernization|risk-assessment|migration-orchestrator) ;;
  *) emit_allow ""; exit 0 ;;
esac

REPORTS="$(reports_dir)"

# Required reports per agent (numeric IDs).
declare -a required=()
case "$AGENT" in
  risk-assessment)
    # Needs Phase 1 schema/T-SQL + Phase 2 data flow to score business risk.
    required=(01 02 03 07 08)
    ;;
  spanner-schema)
    # Per agents/spanner-schema.md "Prerequisites": needs schema (01),
    # dead-component exclusions (04), replication topology (12), perf (14),
    # transactions (15), analytics OLTP/analytics split (16).
    required=(01 04 12 14 15 16)
    ;;
  service-extraction)
    # Per agents/service-extraction.md "Prerequisites": needs T-SQL analysis
    # (02), stored proc inventory (03), transactions (15), analytics (16),
    # and the target Spanner schema (18).
    required=(02 03 15 16 18)
    ;;
  modernization)
    # Needs the integration catalog set (09-11) to redesign ESB flows, plus
    # performance/transactions to size event/serverless replacements.
    required=(09 10 11 14 15)
    ;;
  migration-orchestrator)
    # Orchestrator can always run; it produces the prerequisites.
    emit_allow ""
    exit 0
    ;;
esac

missing=()
for id in "${required[@]}"; do
  if ! compgen -G "$REPORTS/${id}-*.md" >/dev/null 2>&1; then
    missing+=("${id}")
  fi
done
# IDs above mirror the canonical numbering documented in
# agents/migration-orchestrator.md (Phase / Report Files table) — keep in sync
# with each agent's "Prerequisites" section.

if (( ${#missing[@]} > 0 )); then
  reason="Phase gate not met for @${AGENT}: missing reports for IDs ${missing[*]}. Run upstream agents first (see README execution order) or invoke @migration-orchestrator to coordinate."
  emit_deny "$reason"
  exit 0
fi

if have_jq; then
  jq -nc --arg msg "Phase gate passed for @${AGENT}: all prerequisite reports present." \
    '{decision:"allow", systemMessage:$msg}'
else
  printf '{"decision":"allow"}'
fi
