#!/usr/bin/env bash
# BeforeTool hook (matcher: write_file|replace):
# Validate writes that look like migration report output:
#   1. Files written under reports/ must follow the NN-name.md naming convention.
#   2. Block obvious secrets/credentials patterns from being persisted.
#   3. Warn (allow with systemMessage) when writing outside the canonical layout.
#
# Output contract:
#   exit 0 + {"decision":"deny","reason":"..."}  -> blocks
#   exit 0 + {"decision":"allow", ...}            -> proceeds

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
CONTENT="$(event_field "$EVENT" '.tool_input.content')"
[[ -z "$CONTENT" ]] && CONTENT="$(event_field "$EVENT" '.tool_input.new_string')"

ROOT="$(project_root)"
REPORTS="$(reports_dir)"

# 1. Naming convention: anything written into reports/ that ends in .md must
#    match the NN-name.md numbered convention. Allow other extensions
#    (e.g., diagrams, schemas) without comment.
abs_path="$PATH_ARG"
case "$PATH_ARG" in
  /*) abs_path="$PATH_ARG" ;;
  *)  abs_path="$ROOT/$PATH_ARG" ;;
esac

if [[ "$abs_path" == "$REPORTS"/* && "$abs_path" == *.md ]]; then
  base="$(basename "$abs_path")"
  if ! [[ "$base" =~ ^[0-9]{2}-[a-z0-9-]+\.md$ ]]; then
    emit_deny "Report filename '$base' does not match the migration toolkit convention 'NN-kebab-name.md' (e.g. 18-spanner-schema-design.md). Rename before writing."
    exit 0
  fi
fi

# 2. Secret scanning. Crude but useful: block writes whose content includes
#    high-confidence credential patterns. False positives can be overridden by
#    the user editing the file directly.
if [[ -n "$CONTENT" ]]; then
  # Limit to first ~64KB to keep regex cheap on huge writes.
  sample="${CONTENT:0:65536}"
  secret_patterns=(
    'AKIA[0-9A-Z]{16}'                                        # AWS access key
    'AIza[0-9A-Za-z_\-]{35}'                                  # Google API key
    'ghp_[0-9A-Za-z]{36,}'                                    # GitHub PAT
    'xox[baprs]-[0-9A-Za-z\-]{10,}'                           # Slack token
    '-----BEGIN[[:space:]]+(RSA|OPENSSH|EC|PGP|DSA|ENCRYPTED)?[[:space:]]*PRIVATE[[:space:]]+KEY-----'
  )
  for pat in "${secret_patterns[@]}"; do
    if echo "$sample" | grep -qE -- "$pat"; then
      emit_deny "Refusing to write content containing what appears to be a credential (pattern: $pat). Migration reports must never contain secrets — use placeholders such as <REDACTED> instead."
      exit 0
    fi
  done

  # Sybase / database connection strings with embedded passwords.
  if echo "$sample" | grep -qiE '(password|pwd|passwd)[[:space:]]*[:=][[:space:]]*[^[:space:]<>"]{4,}'; then
    # Allow if value is clearly a placeholder.
    if ! echo "$sample" | grep -qiE '(password|pwd|passwd)[[:space:]]*[:=][[:space:]]*(<[^>]+>|\$\{[^}]+\}|REDACTED|\*+|xxx+)'; then
      emit_deny "Refusing to write content with an embedded password. Replace the value with <REDACTED> or an environment variable reference."
      exit 0
    fi
  fi
fi

emit_allow ""
