#!/usr/bin/env bash
# Notification + AfterTool hook:
# Append every relevant event to a JSONL audit log under
# .gemini/audit/migration-audit.jsonl. The log is designed so that a separate
# review agent can read it after the fact and answer questions like:
#   - which reports were produced, in what order, and at what time?
#   - which tool calls touched which file?
#   - did any agent fail or get gated by before-agent.sh?
#   - what was the migration phase when each event happened?
#
# This hook is advisory: it never blocks. Failures degrade silently.
#
# Record shape (one JSON object per line):
#   {
#     "ts":           ISO-8601 UTC timestamp,
#     "session":      $GEMINI_SESSION_ID,
#     "event":        "AfterTool" | "Notification" | ...,
#     "tool":         tool name (or null),
#     "agent":        active agent name (or null),
#     "file":         tool_input.file_path / .path (or null),
#     "report_id":    "NN" if file matches NN-name.md under reports/ (or null),
#     "phase":        "1" | "2" | "3" | "4" | "synthesis" (derived from report_id),
#     "outcome":      "success" | "error" (best effort, from the event payload),
#     "command_preview": first 240 chars of tool_input.command (or ""),
#     "input_preview":   first 240 chars of any other relevant input,
#     "size":         length of tool_input.content (for writes), if known
#   }

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOK_DIR/lib/common.sh"

EVENT="$(read_event)"
LOG="$(audit_log_file)"

if ! have_jq; then
  # Minimal fallback record without parsing.
  printf '{"ts":"%s","session":"%s","event":"raw"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${GEMINI_SESSION_ID:-unknown}" >> "$LOG" 2>/dev/null || true
  emit_allow ""
  exit 0
fi

REPORTS="$(reports_dir)"

# Build the enriched record. report_id and phase are derived from any file path
# the event touches, so a reviewer can group rows by phase trivially.
jq -c \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg session "${GEMINI_SESSION_ID:-unknown}" \
  --arg reports_dir "$REPORTS" \
  '
  def phase_for(id):
    if   id == null then null
    elif (id | tonumber) <= 6  then "1"
    elif (id | tonumber) <= 12 then "2"
    elif (id | tonumber) <= 17 then "3"
    elif (id | tonumber) <= 23 then "4"
    elif (id | tonumber) == 24 then "synthesis"
    else null
    end;

  def report_id_of(path):
    if path == null then null
    else
      ( path | capture("(?<id>[0-9]{2})-[a-z0-9-]+\\.md$") | .id ) // null
    end;

  ((.tool_input.file_path // .tool_input.path // null)) as $file
  | ((.tool_input.content // .tool_input.new_string // "") | tostring) as $content
  | report_id_of($file) as $rid
  | {
      ts:              $ts,
      session:         $session,
      event:           (.event_name // .hook_event_name // "unknown"),
      tool:            (.tool_name // null),
      agent:           (.agent // .agent_name // .tool_input.agent // null),
      file:            $file,
      report_id:       $rid,
      phase:           phase_for($rid),
      outcome:         (.outcome // .status // (if .error then "error" else "success" end)),
      command_preview: ((.tool_input.command // "") | tostring | .[0:240]),
      input_preview:   ($content[0:240]),
      size:            (if $content == "" then null else ($content | length) end)
    }
  ' \
  <<< "$EVENT" >> "$LOG" 2>/dev/null || warn "audit log write failed"

emit_allow ""
