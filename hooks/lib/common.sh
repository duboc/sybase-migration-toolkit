#!/usr/bin/env bash
# Shared helpers for Sybase migration toolkit hooks.
# Source this file from individual hooks: . "$(dirname "$0")/lib/common.sh"
#
# Conventions (from Gemini CLI hook spec):
#   - stdout MUST be a single JSON object (or empty). Anything else breaks parsing.
#   - stderr is for logging/diagnostics.
#   - Exit 0 = success (stdout parsed as JSON).
#   - Exit 2 = system block (stderr is the rejection reason).
#   - Other exit codes = warning, the action proceeds.

set -uo pipefail

# Logging goes to stderr only. Never write to stdout from these helpers.
log() { echo "[sybase-migration] $*" >&2; }
warn() { echo "[sybase-migration][warn] $*" >&2; }
err()  { echo "[sybase-migration][error] $*" >&2; }

# Project root resolution. Prefer GEMINI_PROJECT_DIR; fall back to GEMINI_CWD or PWD.
project_root() {
  if [[ -n "${GEMINI_PROJECT_DIR:-}" ]]; then
    echo "$GEMINI_PROJECT_DIR"
  elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    echo "$CLAUDE_PROJECT_DIR"
  elif [[ -n "${GEMINI_CWD:-}" ]]; then
    echo "$GEMINI_CWD"
  else
    pwd
  fi
}

# Reports directory used by every migration agent.
reports_dir() {
  echo "$(project_root)/reports"
}

# Migration state file maintained by the orchestrator and by AfterTool hooks.
state_file() {
  echo "$(project_root)/reports/migration-state.json"
}

# Audit log file. Used by audit-log.sh for compliance trails.
audit_log_file() {
  local dir="$(project_root)/.gemini/audit"
  mkdir -p "$dir" 2>/dev/null || true
  echo "$dir/migration-audit.jsonl"
}

# Read raw JSON event from stdin into a variable.
read_event() {
  cat
}

# JSON encoding helpers. Require jq.
have_jq() { command -v jq >/dev/null 2>&1; }

# Emit a final JSON decision on stdout. Use this exactly once per hook.
# Usage: emit_json '{"decision":"allow"}'
emit_json() {
  printf '%s' "$1"
}

# Build an "allow" response with optional systemMessage shown to the user.
emit_allow() {
  local message="${1:-}"
  if [[ -n "$message" ]] && have_jq; then
    jq -nc --arg msg "$message" '{decision:"allow", systemMessage:$msg}'
  else
    printf '{"decision":"allow"}'
  fi
}

# Build a "deny" response. Gemini CLI will block the action and surface `reason`.
emit_deny() {
  local reason="$1"
  if have_jq; then
    jq -nc --arg r "$reason" '{decision:"deny", reason:$r}'
  else
    printf '{"decision":"deny","reason":"%s"}' "${reason//\"/\\\"}"
  fi
}

# Extract a JSON field from the event. Falls back to empty string if missing.
# Usage: event_field "$EVENT" '.tool_input.file_path'
event_field() {
  local event="$1" path="$2"
  if have_jq; then
    printf '%s' "$event" | jq -r "${path} // empty" 2>/dev/null
  else
    # Best-effort fallback when jq is missing. Hooks degrade to allow.
    printf ''
  fi
}

# Detect whether the project looks like a Sybase migration target.
is_sybase_project() {
  local root
  root="$(project_root)"
  # Cheap heuristics: presence of reports/ dir, sybase markers in SQL, or a state file.
  [[ -d "$root/reports" ]] && return 0
  [[ -f "$root/migration-state.json" ]] && return 0
  if compgen -G "$root"/*.sql >/dev/null 2>&1 || compgen -G "$root"/**/*.sql >/dev/null 2>&1; then
    if grep -rIl --include='*.sql' -E 'sp_procxmode|@@identity|SET ROWCOUNT|CREATE PROXY_TABLE|PROXY_TABLE|CREATE EXISTING TABLE' "$root" 2>/dev/null | head -1 | grep -q .; then
      return 0
    fi
  fi
  return 1
}

# Match a numbered report filename like `01-schema-profile.md`. Returns the
# leading two-digit ID on stdout, or nothing if it does not match.
report_id_for() {
  local path="$1"
  local base
  base="$(basename "$path")"
  if [[ "$base" =~ ^([0-9]{2})-[a-z0-9-]+\.md$ ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}
