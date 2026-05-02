#!/usr/bin/env bash
# BeforeAgent hook:
# Adaptive phase-gate validator. Two checks per agent:
#
#   1. Required upstream reports present? If not, deny with the missing IDs.
#   2. Required data sources available? Read `intake_answers.data_sources`
#      from migration-state.json. If a data source is missing the agent can
#      either:
#         - run anyway in "static-only mode" (allow + systemMessage), or
#         - skip a specific report it would otherwise produce.
#      The agent body is responsible for adapting; this hook tells it which
#      mode to use.
#
# Output contract:
#   exit 0 + {"decision":"deny","reason":"..."}  -> blocks turn
#   exit 0 + {"decision":"allow", systemMessage} -> proceeds with note
#   exit 0 + {"decision":"allow"}                 -> proceeds silently

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOK_DIR/lib/common.sh"

EVENT="$(read_event)"
AGENT="$(event_field "$EVENT" '.agent')"
[[ -z "$AGENT" ]] && AGENT="$(event_field "$EVENT" '.agent_name')"
[[ -z "$AGENT" ]] && AGENT="$(event_field "$EVENT" '.tool_input.agent')"

# Only enforce gates for our migration agents. Pass through everything else.
case "$AGENT" in
  sybase-inventory|dead-component|data-flow|integration-catalog|risk-assessment|spanner-schema|service-extraction|modernization|migration-orchestrator) ;;
  *) emit_allow ""; exit 0 ;;
esac

REPORTS="$(reports_dir)"
STATE="$(state_file)"

# --- Phase 1: required reports ---
declare -a required=()
case "$AGENT" in
  sybase-inventory)        required=() ;;          # Phase 1 entry — no prereqs
  dead-component)          required=(01 02 03) ;;  # Needs Phase 1 inventory
  data-flow)               required=(01 02 03) ;;
  integration-catalog)     required=(01) ;;
  risk-assessment)         required=(01 02 03 07 08) ;;
  spanner-schema)          required=(01 04 12 14 15 16) ;;
  service-extraction)      required=(02 03 15 16 18) ;;
  modernization)           required=(09 10 11 14 15) ;;
  migration-orchestrator)  required=() ;;          # Coordinator, never gated
esac

missing=()
for id in "${required[@]}"; do
  if ! compgen -G "$REPORTS/${id}-*.md" >/dev/null 2>&1; then
    missing+=("${id}")
  fi
done

if (( ${#missing[@]} > 0 )); then
  next_action=""
  case "$AGENT" in
    risk-assessment)    next_action=" Run @sybase-inventory + @data-flow first." ;;
    spanner-schema)     next_action=" Run @sybase-inventory, @dead-component, @data-flow, and @risk-assessment first." ;;
    service-extraction) next_action=" Run @sybase-inventory, @risk-assessment, and @spanner-schema first." ;;
    modernization)      next_action=" Run @integration-catalog and @risk-assessment first." ;;
    dead-component)     next_action=" Run @sybase-inventory first." ;;
    data-flow)          next_action=" Run @sybase-inventory first." ;;
    integration-catalog) next_action=" Run @sybase-inventory first." ;;
  esac
  reason="Phase gate not met for @${AGENT}: missing reports for IDs ${missing[*]}.${next_action}"
  emit_deny "$reason"
  exit 0
fi

# --- Phase 2: data-source aware mode selection ---
mode_notes=()

if have_jq && [[ -f "$STATE" ]]; then
  if ! jq -e '.intake_answers.data_sources' "$STATE" >/dev/null 2>&1; then
    mode_notes+=("Data-source intake not yet captured in migration-state.json. Ask the user the 5 questions listed in the SessionStart context and persist answers under intake_answers.data_sources before proceeding.")
  else
    telemetry="$(jq -r '.intake_answers.data_sources.production_telemetry // false' "$STATE")"
    app_logs="$(jq -r '.intake_answers.data_sources.application_logs // false' "$STATE")"
    repl="$(jq -r '.intake_answers.data_sources.replication_config // false' "$STATE")"
    iq="$(jq -r '.intake_answers.data_sources.iq_exports // false' "$STATE")"
    git_h="$(jq -r '.intake_answers.data_sources.git_history // false' "$STATE")"

    case "$AGENT" in
      risk-assessment)
        if [[ "$telemetry" != "true" ]]; then
          mode_notes+=("Run reports 14 (performance) and 15 (transactions) in STATIC-ONLY mode — no MDA / sp_sysmon data was reported. Mark confidence as REDUCED in §1 Executive Summary and §4 Impact Analysis.")
        fi
        if [[ "$git_h" != "true" ]]; then
          mode_notes+=("Skip churn-based scoring in report 13 — no git history reported. Use complexity tags only.")
        fi
        if [[ "$iq" != "true" ]]; then
          mode_notes+=("If Sybase IQ is in scope, report 16 will be incomplete — no IQ exports reported. Note as a gap and recommend the user produce IQ DDL exports.")
        fi
        ;;
      dead-component)
        if [[ "$telemetry" != "true" && "$app_logs" != "true" ]]; then
          mode_notes+=("Run in PURE STATIC mode — no production telemetry and no application logs reported. Detect zero-reference objects only; do NOT claim execution-frequency-based dead status. Mark every finding's confidence as 'static-only' in the report.")
        elif [[ "$telemetry" != "true" ]]; then
          mode_notes+=("Run report 04 (Sybase) in static mode (no MDA data). Report 17 (Java) can use application logs.")
        elif [[ "$app_logs" != "true" ]]; then
          mode_notes+=("Run report 17 (Java) in static mode (no app logs / APM). Report 04 (Sybase) can use MDA data.")
        fi
        ;;
      data-flow)
        if [[ "$repl" != "true" ]]; then
          mode_notes+=("Skip report 12 (replication topology) — no Replication Server configs reported. Note in §1 of report 07 that report 12 is omitted by user input.")
        fi
        ;;
      modernization)
        if [[ "$git_h" != "true" ]]; then
          mode_notes+=("Spring Boot upgrade plan (report 23) cannot use commit-history evidence; rely on dependency manifests only.")
        fi
        ;;
    esac
  fi
fi

if (( ${#mode_notes[@]} == 0 )); then
  if have_jq; then
    jq -nc --arg msg "Phase gate passed for @${AGENT}: all prerequisite reports present, all data sources sufficient for full mode." \
      '{decision:"allow", systemMessage:$msg}'
  else
    printf '{"decision":"allow"}'
  fi
  exit 0
fi

# Combine the mode notes into a single systemMessage. Each note is one bullet.
joined="$(printf -- '- %s\n' "${mode_notes[@]}")"
if have_jq; then
  jq -nc \
    --arg agent "$AGENT" \
    --arg notes "$joined" \
    '{decision:"allow", systemMessage:("Phase gate passed for @" + $agent + " — adaptive mode active:\n" + $notes)}'
else
  printf '{"decision":"allow"}'
fi
