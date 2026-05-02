#!/usr/bin/env bash
set -euo pipefail

REPO="duboc/sybase-migration-toolkit"
BRANCH="main"
TARBALL_URL="https://api.github.com/repos/${REPO}/tarball/${BRANCH}"
AGENTS_DIR="agents"
HOOKS_DIR="hooks"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install Gemini CLI migration subagents from the gemini-cli-skills repository.

These subagents provide a complete Sybase-to-Cloud Spanner migration pipeline
using 9 specialized agents that coordinate through report files. Hooks enforce
phase gates, audit logging, and destructive-command guards across the pipeline.

Options:
  --scope user        Install to ~/.gemini/{agents,hooks}/ (user scope, default)
  --scope project     Install to .gemini/{agents,hooks}/ in current directory
  --agents-only       Install only the agent .md files (skip settings + hooks)
  --settings-only     Merge only the settings.json overrides (skip agents/hooks)
  --hooks-only        Install only the hook scripts (skip agents + settings)
  --no-hooks          Install agents + settings without hooks
  --list              List available agents and exit
  -h, --help          Show this help message

Examples:
  # Install everything to user scope (recommended)
  $(basename "$0")

  # Install to current project only
  $(basename "$0") --scope project

  # Reinstall hooks after editing them locally
  $(basename "$0") --hooks-only

Available agents:
  sybase-inventory       Schema profiling, T-SQL analysis, SBOM, batch scanning
  dead-component         Dead code detection and migration scope reduction
  data-flow              Data flow mapping, dependency tracing, replication analysis
  integration-catalog    Integration cataloging, ESB analysis, routing extraction
  risk-assessment        Business risk, performance, transactions, analytics
  spanner-schema         Cloud Spanner schema design with interleaved tables
  service-extraction     T-SQL to Cloud Run microservice extraction
  modernization          ESB-to-event-driven, batch-to-serverless, Spring Boot upgrade
  migration-orchestrator Master orchestrator coordinating all phases

Installed hooks (see hooks/README.md):
  session-start          SessionStart  - inject phase/state + data-source intake
  before-agent           BeforeAgent   - phase gate + adaptive mode (static-only / skip)
  after-tool-report      AfterTool     - update migration-state.json on report writes
  audit-log              AfterTool/Notification - rich JSONL trail for review agents
  pre-compress           PreCompress   - snapshot state before compression

Installed utilities (not hooks):
  audit-summary.sh       - digest the audit log as JSON or markdown for inspection
EOF
}

list_agents() {
  cat <<EOF
Sybase-to-Cloud Spanner Migration Agents
=========================================

Phase 1 (parallel):
  @sybase-inventory     Reports 01-03, 05-06  |  Schema, T-SQL, procs, SBOM, batch
  @dead-component       Reports 04, 17        |  Dead code detection, scope reduction

Phase 2 (parallel):
  @data-flow            Reports 07, 08, 12    |  Data flows, dependencies, replication
  @integration-catalog  Reports 09-11         |  Integrations, ESB catalog, routing

Phase 3:
  @risk-assessment      Reports 13-16         |  Business risk, perf, txn, analytics
  @dead-component       Report 17 (pass 2)    |  Application-level dead code

Phase 4 (parallel):
  @spanner-schema       Report 18             |  Spanner DDL with interleaved tables
  @service-extraction   Reports 19-20         |  T-SQL to Cloud Run services
  @modernization        Reports 21-23         |  Event-driven, serverless, Spring Boot

Synthesis:
  @migration-orchestrator  Report 24          |  Full migration plan and orchestration
EOF
}

# --- Parse arguments ---
SCOPE="user"
INSTALL_AGENTS=true
INSTALL_SETTINGS=true
INSTALL_HOOKS=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --list)
      list_agents
      exit 0
      ;;
    --scope)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --scope requires a value (user or project)" >&2
        exit 1
      fi
      SCOPE="$2"
      shift 2
      ;;
    --agents-only)
      INSTALL_SETTINGS=false
      INSTALL_HOOKS=false
      shift
      ;;
    --settings-only)
      INSTALL_AGENTS=false
      INSTALL_HOOKS=false
      shift
      ;;
    --hooks-only)
      INSTALL_AGENTS=false
      INSTALL_SETTINGS=false
      shift
      ;;
    --no-hooks)
      INSTALL_HOOKS=false
      shift
      ;;
    -*)
      echo "Error: Unknown option '$1'" >&2
      usage
      exit 1
      ;;
    *)
      echo "Error: Unexpected argument '$1'" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$SCOPE" != "user" && "$SCOPE" != "project" ]]; then
  echo "Error: --scope must be 'user' or 'project'" >&2
  exit 1
fi

# --- Determine install directories ---
if [[ "$SCOPE" == "user" ]]; then
  AGENT_INSTALL_DIR="${HOME}/.gemini/agents"
  HOOK_INSTALL_DIR="${HOME}/.gemini/hooks/sybase-migration"
  SETTINGS_FILE="${HOME}/.gemini/settings.json"
  # Absolute path so hooks resolve regardless of working directory.
  HOOKS_PATH_FOR_SETTINGS="${HOME}/.gemini/hooks/sybase-migration"
else
  AGENT_INSTALL_DIR=".gemini/agents"
  HOOK_INSTALL_DIR=".gemini/hooks/sybase-migration"
  SETTINGS_FILE=".gemini/settings.json"
  # Use Gemini's project-dir variable so the hook command resolves at runtime
  # even when the CLI is launched from a subdirectory.
  HOOKS_PATH_FOR_SETTINGS='$GEMINI_PROJECT_DIR/.gemini/hooks/sybase-migration'
fi

# --- Download repository ---
TMPDIR_PATH=$(mktemp -d)
trap 'rm -rf "$TMPDIR_PATH"' EXIT

echo "Downloading agents from GitHub ..."
HTTP_CODE=$(curl -fsSL -w "%{http_code}" -o "${TMPDIR_PATH}/repo.tar.gz" "$TARBALL_URL")

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "Error: Failed to download tarball (HTTP ${HTTP_CODE})" >&2
  exit 1
fi

EXTRACT_DIR="${TMPDIR_PATH}/extracted"
mkdir -p "$EXTRACT_DIR"
tar -xzf "${TMPDIR_PATH}/repo.tar.gz" -C "$EXTRACT_DIR" --strip-components=1 2>/dev/null

AGENT_SOURCE="${EXTRACT_DIR}/${AGENTS_DIR}"
HOOK_SOURCE="${EXTRACT_DIR}/${HOOKS_DIR}"

if [[ ! -d "$AGENT_SOURCE" ]]; then
  echo "Error: Agents directory not found in the repository." >&2
  exit 1
fi

# --- Install agents ---
if [[ "$INSTALL_AGENTS" == true ]]; then
  echo "Installing agents to ${AGENT_INSTALL_DIR} ..."
  mkdir -p "$AGENT_INSTALL_DIR"

  AGENT_COUNT=0
  for agent_file in "${AGENT_SOURCE}"/*.md; do
    if [[ -f "$agent_file" ]]; then
      cp "$agent_file" "$AGENT_INSTALL_DIR"/
      AGENT_COUNT=$((AGENT_COUNT + 1))
      echo "  Installed: $(basename "$agent_file" .md)"
    fi
  done

  # Install shared agent references (canonical report template, etc.).
  if [[ -d "${AGENT_SOURCE}/references" ]]; then
    mkdir -p "${AGENT_INSTALL_DIR}/references"
    cp "${AGENT_SOURCE}/references"/*.md "${AGENT_INSTALL_DIR}/references"/ 2>/dev/null || true
    REF_COUNT=$(find "${AGENT_INSTALL_DIR}/references" -maxdepth 1 -name '*.md' | wc -l)
    echo "  Installed: ${REF_COUNT} reference file(s) under references/"
  fi

  echo ""
  echo "${AGENT_COUNT} agents installed to ${AGENT_INSTALL_DIR}"
fi

# --- Install hooks ---
if [[ "$INSTALL_HOOKS" == true ]]; then
  if [[ ! -d "$HOOK_SOURCE" ]]; then
    echo "Warning: hooks directory not found in the repository, skipping hook install." >&2
  else
    echo ""
    echo "Installing hooks to ${HOOK_INSTALL_DIR} ..."
    mkdir -p "$HOOK_INSTALL_DIR/lib"

    HOOK_COUNT=0
    for hook_file in "${HOOK_SOURCE}"/*.sh; do
      [[ -f "$hook_file" ]] || continue
      cp "$hook_file" "$HOOK_INSTALL_DIR"/
      chmod +x "$HOOK_INSTALL_DIR/$(basename "$hook_file")"
      HOOK_COUNT=$((HOOK_COUNT + 1))
      echo "  Installed: $(basename "$hook_file" .sh)"
    done

    if [[ -d "${HOOK_SOURCE}/lib" ]]; then
      cp "${HOOK_SOURCE}/lib"/*.sh "$HOOK_INSTALL_DIR/lib/" 2>/dev/null || true
    fi
    if [[ -f "${HOOK_SOURCE}/README.md" ]]; then
      cp "${HOOK_SOURCE}/README.md" "$HOOK_INSTALL_DIR"/
    fi

    echo ""
    echo "${HOOK_COUNT} hooks installed to ${HOOK_INSTALL_DIR}"
  fi
fi

# --- Merge settings ---
if [[ "$INSTALL_SETTINGS" == true ]]; then
  SETTINGS_SOURCE="${AGENT_SOURCE}/settings.json"

  if [[ ! -f "$SETTINGS_SOURCE" ]]; then
    echo "Warning: settings.json not found in agents directory, skipping settings merge." >&2
  else
    echo ""
    echo "Merging settings into ${SETTINGS_FILE} ..."

    mkdir -p "$(dirname "$SETTINGS_FILE")"

    # Render hook command paths from the __HOOKS_DIR__ placeholder.
    # We use a literal-safe sed replacement because HOOKS_PATH_FOR_SETTINGS may
    # contain '$GEMINI_PROJECT_DIR' which must survive into the final JSON.
    RENDERED_SETTINGS="${TMPDIR_PATH}/settings.rendered.json"
    awk -v repl="$HOOKS_PATH_FOR_SETTINGS" '{
      gsub(/__HOOKS_DIR__/, repl)
      print
    }' "$SETTINGS_SOURCE" > "$RENDERED_SETTINGS"

    if [[ "$INSTALL_HOOKS" != true ]]; then
      # Strip the hooks block when the user opted out so we do not point at
      # commands that were not installed.
      if command -v jq &>/dev/null; then
        jq 'del(.hooks)' "$RENDERED_SETTINGS" > "${TMPDIR_PATH}/settings.nohooks.json"
        mv "${TMPDIR_PATH}/settings.nohooks.json" "$RENDERED_SETTINGS"
      fi
    fi

    if command -v jq &>/dev/null; then
      if [[ -f "$SETTINGS_FILE" ]]; then
        jq -s '.[0] * .[1]' "$SETTINGS_FILE" "$RENDERED_SETTINGS" > "${TMPDIR_PATH}/merged.json"
        cp "${TMPDIR_PATH}/merged.json" "$SETTINGS_FILE"
        echo "  Merged settings into existing ${SETTINGS_FILE}."
      else
        cp "$RENDERED_SETTINGS" "$SETTINGS_FILE"
        echo "  Created new settings file at ${SETTINGS_FILE}."
      fi
    else
      echo "  Warning: jq not found. Cannot merge settings automatically."
      echo "  Please manually merge the following into ${SETTINGS_FILE}:"
      echo ""
      cat "$RENDERED_SETTINGS"
      echo ""
      echo "  Install jq for automatic merging: sudo apt install jq"
    fi
  fi
fi

echo ""
echo "Installation complete!"
echo ""
echo "Usage: In any Gemini CLI session, invoke an agent with @agent-name."
echo "Start with: @migration-orchestrator to run the full pipeline."
if [[ "$INSTALL_HOOKS" == true ]]; then
  echo ""
  echo "Hooks are active. View them with:  /hooks panel"
  echo "Disable a single hook with:       /hooks disable sybase-migration/<name>"
fi
echo ""
echo "For agent list and execution order: $(basename "$0") --list"
