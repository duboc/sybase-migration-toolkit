#!/usr/bin/env bash
set -euo pipefail

REPO="duboc/sybase-migration-toolkit"
BRANCH="main"
TARBALL_URL="https://api.github.com/repos/${REPO}/tarball/${BRANCH}"

usage() {
  cat <<EOF
Usage: $(basename "$0") <skill-name> [--scope user|workspace]

Install a Gemini CLI skill from the gemini-cli-skills repository.

Arguments:
  skill-name          Name of the skill to install (e.g., software-troubleshooter)

Options:
  --scope user        Install to ~/.gemini/skills/<name>/ (user scope)
  --scope workspace   Install to .gemini/skills/<name>/ in current directory (default)
  -h, --help          Show this help message

Examples:
  $(basename "$0") software-troubleshooter
  $(basename "$0") software-troubleshooter --scope user

Available skills:
  # Phase 1: Sybase Inventory & Discovery
  sybase-tsql-analyzer           Parse Sybase T-SQL, classify complexity, flag Spanner issues
  sybase-schema-profiler         Profile schemas, data types, indexes for Spanner conversion
  sybase-replication-mapper      Catalog Replication Server configs for Change Streams design
  sybase-integration-cataloger   Catalog JDBC, SOAP, MQ, FIX/SWIFT connections

  # Phase 2: Data Flow & Dependency Mapping
  sybase-data-flow-mapper        Trace cross-DB references, proxy tables, batch ETL chains
  sybase-transaction-analyzer    Analyze transaction patterns and locking for Spanner strategy
  sybase-performance-profiler    Profile query performance from MDA tables

  # Phase 3: Risk & Scope Reduction
  sybase-dead-component-detector Identify unused Sybase objects for migration exclusion
  sybase-analytics-assessor      Assess OLTP vs analytics for Spanner/BigQuery split

  # Phase 4: Spanner Target Architecture
  sybase-to-spanner-schema-designer  Design Spanner schema with interleaved tables
  tsql-to-application-extractor      Extract T-SQL logic to Cloud Run microservices

  # Orchestration
  sybase-spanner-migration-orchestrator  Orchestrate full migration lifecycle
EOF
}

# --- Parse arguments ---
SKILL_NAME=""
SCOPE="workspace"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --scope)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --scope requires a value (user or workspace)" >&2
        exit 1
      fi
      SCOPE="$2"
      shift 2
      ;;
    -*)
      echo "Error: Unknown option '$1'" >&2
      usage
      exit 1
      ;;
    *)
      if [[ -z "$SKILL_NAME" ]]; then
        SKILL_NAME="$1"
      else
        echo "Error: Unexpected argument '$1'" >&2
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$SKILL_NAME" ]]; then
  echo "Error: skill name is required" >&2
  echo ""
  usage
  exit 1
fi

if [[ "$SCOPE" != "user" && "$SCOPE" != "workspace" ]]; then
  echo "Error: --scope must be 'user' or 'workspace'" >&2
  exit 1
fi

# --- Determine install directory ---
if [[ "$SCOPE" == "user" ]]; then
  INSTALL_DIR="${HOME}/.gemini/skills/${SKILL_NAME}"
else
  INSTALL_DIR=".gemini/skills/${SKILL_NAME}"
fi

echo "Installing skill '${SKILL_NAME}' to ${INSTALL_DIR} ..."

# --- Download and extract ---
TMPDIR_PATH=$(mktemp -d)
trap 'rm -rf "$TMPDIR_PATH"' EXIT

echo "Downloading from GitHub ..."
HTTP_CODE=$(curl -fsSL -w "%{http_code}" -o "${TMPDIR_PATH}/repo.tar.gz" "$TARBALL_URL")

if [[ "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ]]; then
  echo "Error: Failed to download tarball (HTTP ${HTTP_CODE})" >&2
  exit 1
fi

# Extract only the skill directory.
# GitHub tarballs have a top-level directory like "duboc-gemini-cli-skills-<sha>/".
# We use --strip-components=1 and filter to skills/<name>/ to get just the skill files.
EXTRACT_DIR="${TMPDIR_PATH}/extracted"
mkdir -p "$EXTRACT_DIR"

tar -xzf "${TMPDIR_PATH}/repo.tar.gz" -C "$EXTRACT_DIR" --strip-components=1 2>/dev/null

SKILL_SOURCE="${EXTRACT_DIR}/skills/${SKILL_NAME}"

if [[ ! -d "$SKILL_SOURCE" ]]; then
  echo "Error: Skill '${SKILL_NAME}' not found in the repository." >&2
  echo ""
  echo "Available skills:"
  if [[ -d "${EXTRACT_DIR}/skills" ]]; then
    for dir in "${EXTRACT_DIR}/skills"/*/; do
      if [[ -d "$dir" ]]; then
        basename "$dir"
      fi
    done | sed 's/^/  /'
  else
    echo "  (none found)"
  fi
  exit 1
fi

# --- Install ---
mkdir -p "$INSTALL_DIR"
cp -r "$SKILL_SOURCE"/* "$INSTALL_DIR"/

# Make scripts executable
if [[ -d "${INSTALL_DIR}/scripts" ]]; then
  chmod +x "${INSTALL_DIR}/scripts"/*.sh 2>/dev/null || true
  chmod +x "${INSTALL_DIR}/scripts"/*.js 2>/dev/null || true
  chmod +x "${INSTALL_DIR}/scripts"/*.py 2>/dev/null || true
fi

echo ""
echo "Skill '${SKILL_NAME}' installed successfully to ${INSTALL_DIR}"
echo ""
echo "The skill will be available the next time you start Gemini CLI."
