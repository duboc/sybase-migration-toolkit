#!/usr/bin/env bash
# audit-summary.sh — utility for review agents.
#
# Reads .gemini/audit/migration-audit.jsonl and emits a structured JSON
# summary that an inspecting agent can reason about without re-parsing every
# line itself. This is NOT a Gemini CLI hook — it is a stand-alone helper
# meant to be invoked as a tool call by a reviewer agent.
#
# Usage:
#   ./audit-summary.sh                       # summary as JSON on stdout
#   ./audit-summary.sh --pretty              # indented JSON
#   ./audit-summary.sh --markdown            # human-readable markdown
#   ./audit-summary.sh --since 2026-05-02    # only events on/after a date
#   ./audit-summary.sh --report 18           # only events touching report 18
#   ./audit-summary.sh --raw                 # dump the raw matching JSONL lines
#
# Output JSON (default mode):
#   {
#     "log_path":           "...migration-audit.jsonl",
#     "events":             total count,
#     "earliest":           first timestamp,
#     "latest":             last timestamp,
#     "by_phase":           {"1": N, "2": N, "3": N, "4": N, "synthesis": N, "null": N},
#     "by_event":           {"AfterTool": N, "Notification": N, ...},
#     "by_tool":            {"write_file": N, "replace": N, ...},
#     "reports_written":    [{"id": "01", "file": "01-...", "ts": "...", "size": N}, ...],
#     "reports_missing":    [list of canonical IDs 01..24 not yet seen],
#     "errors":             count of events with outcome != "success",
#     "agent_runs":         {"sybase-inventory": N, ...},
#     "files_touched":      sorted unique list of file paths
#   }

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOK_DIR/lib/common.sh"

LOG="$(audit_log_file)"
mode="json"
since=""
report_filter=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pretty)   mode="pretty"; shift ;;
    --markdown) mode="markdown"; shift ;;
    --raw)      mode="raw"; shift ;;
    --since)    since="$2"; shift 2 ;;
    --report)   report_filter="$2"; shift 2 ;;
    -h|--help)
      sed -n '3,30p' "$0" | sed 's/^# //;s/^#//'
      exit 0 ;;
    *)
      echo "unknown arg: $1" >&2
      exit 2 ;;
  esac
done

if [[ ! -f "$LOG" ]]; then
  echo '{"events": 0, "log_path": "'"$LOG"'", "note": "audit log does not exist yet"}'
  exit 0
fi

if ! have_jq; then
  echo "audit-summary.sh requires jq" >&2
  exit 2
fi

# Apply --since and --report filters into a temp working file.
WORK="$(mktemp)"
trap 'rm -f "$WORK"' EXIT
cp "$LOG" "$WORK"

if [[ -n "$since" ]]; then
  jq -c --arg since "$since" 'select(.ts >= $since)' "$WORK" > "$WORK.f" && mv "$WORK.f" "$WORK"
fi
if [[ -n "$report_filter" ]]; then
  jq -c --arg id "$report_filter" 'select(.report_id == $id)' "$WORK" > "$WORK.f" && mv "$WORK.f" "$WORK"
fi

if [[ "$mode" == "raw" ]]; then
  cat "$WORK"
  exit 0
fi

# Build the summary.
SUMMARY="$(jq -s --arg log "$LOG" '
  def canonical_ids: ["01","02","03","04","05","06","07","08","09","10","11","12","13","14","15","16","17","18","19","20","21","22","23","24"];

  . as $events
  | ($events | map(select(.report_id != null and .event == "AfterTool" and (.tool == "write_file" or .tool == "replace" or .tool == "edit" or .tool == "create_file"))) ) as $writes
  | ($writes | map(.report_id) | unique) as $seen_ids
  | (canonical_ids - $seen_ids) as $missing
  | {
      log_path:        $log,
      events:          ($events | length),
      earliest:        ($events | map(.ts) | min),
      latest:          ($events | map(.ts) | max),
      by_phase:        ($events | group_by(.phase // "null") | map({key: (.[0].phase // "null"), value: length}) | from_entries),
      by_event:        ($events | group_by(.event)            | map({key: .[0].event, value: length}) | from_entries),
      by_tool:         ($events | group_by(.tool // "null")   | map({key: (.[0].tool // "null"), value: length}) | from_entries),
      agent_runs:      ($events | map(select(.agent != null)) | group_by(.agent) | map({key: .[0].agent, value: length}) | from_entries),
      reports_written: (
        $writes
        | group_by(.report_id)
        | map({
            id:   .[0].report_id,
            file: (.[-1].file // null),
            ts:   .[-1].ts,
            size: .[-1].size,
            writes: length
          })
        | sort_by(.id)
      ),
      reports_missing: $missing,
      errors:          ($events | map(select(.outcome != "success" and .outcome != null)) | length),
      files_touched:   ($events | map(.file) | map(select(. != null)) | unique)
    }
  ' "$WORK")"

case "$mode" in
  pretty)
    printf '%s\n' "$SUMMARY" | jq .
    ;;
  json)
    printf '%s\n' "$SUMMARY"
    ;;
  markdown)
    # Render the summary as concise markdown for human or LLM consumption.
    printf '%s' "$SUMMARY" | jq -r '
      "# Migration Audit Summary",
      "",
      "**Log:** `\(.log_path)`",
      "**Events:** \(.events)",
      "**Window:** \(.earliest // "—") → \(.latest // "—")",
      "**Errors:** \(.errors)",
      "",
      "## Reports written",
      (if (.reports_written | length) == 0 then "_none_"
       else (["| ID | File | Last write | Size | Writes |", "|---|---|---|---|---|"] +
             (.reports_written | map("| \(.id) | `\(.file // "?")` | \(.ts) | \(.size // "—") | \(.writes) |")))
            | join("\n")
       end),
      "",
      "## Reports missing",
      (if (.reports_missing | length) == 0 then "_all 24 canonical reports present_"
       else "Canonical IDs not yet seen: " + (.reports_missing | join(", "))
       end),
      "",
      "## Activity by phase",
      (.by_phase | to_entries | map("- Phase \(.key): \(.value) events") | join("\n")),
      "",
      "## Activity by tool",
      (.by_tool | to_entries | sort_by(-.value) | map("- `\(.key)`: \(.value)") | join("\n")),
      "",
      "## Agent runs",
      (if (.agent_runs | length) == 0 then "_no agent attribution captured_"
       else (.agent_runs | to_entries | map("- `@\(.key)`: \(.value)") | join("\n"))
       end)
    '
    ;;
esac
