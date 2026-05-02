#!/usr/bin/env bash
# PreCompress hook:
# Before Gemini CLI compresses session context, snapshot the migration state
# and a list of present reports so the post-compression agent can re-orient
# without re-reading every report from scratch.
#
# Advisory only — never blocks.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOK_DIR/lib/common.sh"

EVENT="$(read_event)"

ROOT="$(project_root)"
REPORTS="$(reports_dir)"
SNAP_DIR="$ROOT/.gemini/snapshots"
mkdir -p "$SNAP_DIR" 2>/dev/null || true

ts="$(date -u +%Y%m%dT%H%M%SZ)"
SNAP="$SNAP_DIR/pre-compress-$ts.md"

{
  echo "# Migration State Snapshot ($ts)"
  echo
  echo "## migration-state.json"
  if [[ -f "$(state_file)" ]]; then
    echo '```json'
    cat "$(state_file)"
    echo '```'
  else
    echo "_(no state file)_"
  fi
  echo
  echo "## Reports present"
  if [[ -d "$REPORTS" ]]; then
    find "$REPORTS" -maxdepth 1 -type f -name '[0-9][0-9]-*.md' 2>/dev/null \
      | sort | sed "s|$REPORTS/|- |"
  fi
} > "$SNAP" 2>/dev/null || warn "snapshot write failed"

if have_jq; then
  jq -nc --arg path "$SNAP" \
    '{decision:"allow", systemMessage:("Pre-compress snapshot saved: " + $path)}'
else
  printf '{"decision":"allow"}'
fi
