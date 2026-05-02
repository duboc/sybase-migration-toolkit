#!/usr/bin/env bash
# Notification + AfterTool hook:
# Append every relevant event to a JSONL audit log under
# .gemini/audit/migration-audit.jsonl. Financial migrations must produce a
# defensible record of what the agent did, when, and against which input.
#
# This hook is advisory: it never blocks.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOK_DIR/lib/common.sh"

EVENT="$(read_event)"
LOG="$(audit_log_file)"

# Build a reduced record. We never log raw tool input that may contain secrets
# beyond a small, truncated snippet for forensic context.
if have_jq; then
  jq -c \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg session "${GEMINI_SESSION_ID:-unknown}" \
    '{ts: $ts, session: $session,
      event: (.event_name // .hook_event_name // "unknown"),
      tool: (.tool_name // null),
      agent: (.agent // .agent_name // null),
      file: (.tool_input.file_path // .tool_input.path // null),
      command_preview: ((.tool_input.command // "") | tostring | .[0:240])}' \
    <<< "$EVENT" >> "$LOG" 2>/dev/null || warn "audit log write failed"
else
  # Minimal fallback record without parsing.
  printf '{"ts":"%s","session":"%s","event":"raw"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${GEMINI_SESSION_ID:-unknown}" >> "$LOG" 2>/dev/null || true
fi

emit_allow ""
