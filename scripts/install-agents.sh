#!/usr/bin/env bash
set -euo pipefail

REPO="duboc/sybase-migration-toolkit"
BRANCH="main"
TARBALL_URL="https://api.github.com/repos/${REPO}/tarball/${BRANCH}"
AGENTS_DIR="agents"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install Gemini CLI migration subagents from the gemini-cli-skills repository.

These subagents provide a complete Sybase-to-Cloud Spanner migration pipeline
using 9 specialized agents that coordinate through report files.

Options:
  --scope user        Install to ~/.gemini/agents/ (user scope, default)
  --scope project     Install to .gemini/agents/ in current directory
  --agents-only       Install only the agent .md files (skip settings merge)
  --settings-only     Merge only the settings.json agent overrides
  --list              List available agents and exit
  -h, --help          Show this help message

Examples:
  # Install all agents to user scope (recommended)
  $(basename "$0")

  # Install to current project only
  $(basename "$0") --scope project

  # Only update settings without reinstalling agents
  $(basename "$0") --settings-only

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
      shift
      ;;
    --settings-only)
      INSTALL_AGENTS=false
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

# --- Determine install directory ---
if [[ "$SCOPE" == "user" ]]; then
  AGENT_INSTALL_DIR="${HOME}/.gemini/agents"
  SETTINGS_FILE="${HOME}/.gemini/settings.json"
else
  AGENT_INSTALL_DIR=".gemini/agents"
  SETTINGS_FILE=".gemini/settings.json"
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

  echo ""
  echo "${AGENT_COUNT} agents installed to ${AGENT_INSTALL_DIR}"
fi

# --- Merge settings ---
if [[ "$INSTALL_SETTINGS" == true ]]; then
  SETTINGS_SOURCE="${AGENT_SOURCE}/settings.json"

  if [[ ! -f "$SETTINGS_SOURCE" ]]; then
    echo "Warning: settings.json not found in agents directory, skipping settings merge." >&2
  else
    echo ""
    echo "Merging agent settings into ${SETTINGS_FILE} ..."

    mkdir -p "$(dirname "$SETTINGS_FILE")"

    if command -v jq &>/dev/null; then
      if [[ -f "$SETTINGS_FILE" ]]; then
        # Deep merge: existing settings + agent overrides
        jq -s '.[0] * .[1]' "$SETTINGS_FILE" "$SETTINGS_SOURCE" > "${TMPDIR_PATH}/merged.json"
        cp "${TMPDIR_PATH}/merged.json" "$SETTINGS_FILE"
        echo "  Merged agent overrides into existing settings."
      else
        cp "$SETTINGS_SOURCE" "$SETTINGS_FILE"
        echo "  Created new settings file with agent overrides."
      fi
    else
      echo "  Warning: jq not found. Cannot merge settings automatically."
      echo "  Please manually merge the following into ${SETTINGS_FILE}:"
      echo ""
      cat "$SETTINGS_SOURCE"
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
echo ""
echo "For agent list and execution order: $(basename "$0") --list"
