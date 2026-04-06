# Sybase-to-Spanner Migration Orchestrator

A Gemini CLI skill that acts as the master orchestrator for the complete Sybase-to-Cloud Spanner database migration lifecycle in financial enterprise environments. It guides teams through all 4 phases — Sybase inventory, data flow mapping, risk and scope reduction, and Spanner target architecture design — by invoking 11 specialized skills in the correct order, managing state between phases, enforcing financial compliance gates, and producing a unified migration plan with executive dashboards.

## What It Does

This skill coordinates the full assessment-to-architecture pipeline for migrating Sybase ASE and IQ databases to Google Cloud Spanner and BigQuery:

1. **Intake & scoping** — Gathers Sybase landscape context, financial domain classification, compliance requirements, and market hours constraints. Selects which specialized skills to invoke based on the database landscape.
2. **Phase 1: Sybase Inventory** — Runs inventory skills in parallel to catalog T-SQL stored procedures, profile schemas for Spanner conversion, map Replication Server topology, and catalog external integration points.
3. **Phase 2: Data Flow & Dependency Mapping** — Traces cross-database data flows, analyzes transaction patterns for Spanner mapping, and profiles workloads for Spanner optimization and sizing.
4. **Phase 3: Risk & Scope Reduction** — Identifies dead components for scope reduction, classifies OLTP vs analytics workloads for the Spanner/BigQuery split decision, and enforces financial compliance gates.
5. **Phase 4: Spanner Target Architecture** — Generates optimized Spanner DDL with interleaved tables and extracts T-SQL business logic to Cloud Run microservices with Spanner client libraries.
6. **Unified plan & dashboard** — Synthesizes all phase outputs into an executive-ready migration plan and interactive HTML dashboard with compliance status tracking.

## When Does It Activate?

The skill activates when you ask Gemini to orchestrate a full Sybase-to-Spanner migration effort.

| Trigger | Example |
|---------|---------|
| Sybase to Spanner migration | "Migrate our Sybase databases to Cloud Spanner end-to-end" |
| Full database migration assessment | "Run a full migration assessment on our Sybase ASE environment" |
| Orchestrate Sybase migration | "Orchestrate the migration of our Sybase trading platform to GCP" |
| Database transformation | "Start a Sybase-to-cloud database transformation for our settlement system" |
| Financial system migration | "Plan the migration of our financial Sybase databases to Spanner" |
| Sybase decommissioning | "We need to decommission Sybase and move to Spanner. Where do we start?" |

## Topics Covered

| Area | Details |
|------|---------|
| **Orchestration** | Coordinating 11 specialized skills across 4 sequential phases with dependency management |
| **Phase Management** | Phase gates with financial compliance checks, verification checklists, synthesis between phases |
| **Sybase Analysis** | T-SQL parsing, schema profiling, Replication Server mapping, integration cataloging |
| **Spanner Design** | Interleaved table design, key strategy, data type mapping (money types), transaction pattern mapping |
| **Financial Compliance** | SOX audit trail continuity, PCI-DSS encryption migration, MiFID II reporting, Basel III/IV |
| **Parallel Run** | Financial calculation validation with zero tolerance for monetary discrepancies |
| **Executive Dashboards** | Self-contained HTML dashboard with KPI cards, architecture diagrams, compliance status, cost comparison |
| **State Management** | Resumable orchestration via `migration-state.json`, tracking completed and pending skills |

## Coordinated Skills

This orchestrator delegates work to 11 specialized skills:

| Phase | Skill | Purpose |
|-------|-------|---------|
| 1 - Inventory | `sybase-tsql-analyzer` | Parse and classify Sybase T-SQL stored procedures, triggers, and functions |
| 1 - Inventory | `sybase-schema-profiler` | Profile schemas, data types, indexes, and constraints for Spanner conversion |
| 1 - Inventory | `sybase-replication-mapper` | Catalog Replication Server topology for CDC replacement design |
| 1 - Inventory | `sybase-integration-cataloger` | Catalog all external integration points, Open Server gateways, CTLIB connections |
| 2 - Mapping | `sybase-data-flow-mapper` | Trace cross-database data flows, lineage, and inter-ASE dependencies |
| 2 - Mapping | `sybase-transaction-analyzer` | Analyze transaction patterns, isolation levels, and lock contention for Spanner mapping |
| 2 - Mapping | `sybase-performance-profiler` | Profile workloads, query plans, and resource utilization for Spanner optimization |
| 3 - Risk | `sybase-dead-component-detector` | Identify dead stored procedures, unused tables, and dormant triggers for scope reduction |
| 3 - Risk | `sybase-analytics-assessor` | Classify OLTP vs analytics workloads for Spanner/BigQuery split decision |
| 4 - Target | `sybase-to-spanner-schema-designer` | Generate optimized Spanner DDL with interleaved tables and secondary indexes |
| 4 - Target | `tsql-to-application-extractor` | Extract T-SQL business logic to Cloud Run microservices with Spanner client libraries |

## Phase Workflow

```
Step 0: Intake & Scoping
    |  Sybase landscape, financial domain, compliance requirements, market hours
    v
Step 1: Phase 1 — Sybase Inventory (parallel)
    |  sybase-tsql-analyzer | sybase-schema-profiler | sybase-replication-mapper | sybase-integration-cataloger
    |  [Phase Gate: inventories complete, data types flagged, compliance data identified]
    v
Step 2: Phase 2 — Data Flow & Dependency Mapping (sequential from Phase 1)
    |  sybase-data-flow-mapper | sybase-transaction-analyzer | sybase-performance-profiler
    |  [Phase Gate: flows mapped, transactions cataloged, performance baselined]
    v
Step 3: Phase 3 — Risk & Scope Reduction (sequential from Phase 1+2)
    |  sybase-dead-component-detector | sybase-analytics-assessor
    |  [Phase Gate: dead code flagged, OLTP/analytics split, compliance gates passed]
    v
Step 4: Phase 4 — Spanner Target Architecture (parallel, from Phase 1-3)
    |  sybase-to-spanner-schema-designer | tsql-to-application-extractor
    |  [Phase Gate: Spanner DDL complete, parallel run plan approved]
    v
Step 5: Unified Migration Plan
    |  Executive summary, roadmap, ADRs, parallel run strategy, risk register
    v
Step 6: Executive Dashboard (HTML)
    |  KPI cards, architecture diagram, compliance status, cost comparison
```

## Output Artifacts

| Artifact | Description |
|----------|-------------|
| `sybase-migration-scope.md` | Intake scoping document defining Sybase landscape, compliance requirements, and skill selection |
| `phase-1-summary.md` | Consolidated Sybase inventory: objects, data types, replication topology, integration points |
| `phase-2-summary.md` | Data flow topology, transaction patterns, performance baselines, dependency graph |
| `phase-3-summary.md` | Dead code removal plan, OLTP/analytics split, compliance risk register, priority ranking |
| `phase-4-summary.md` | Spanner DDL design, Cloud Run microservice scaffolding, Change Streams config, parallel run plan |
| `sybase-migration-plan.md` | Unified executive-ready migration plan with roadmap, ADRs, parallel run strategy, risk register |
| `sybase-migration-dashboard.html` | Interactive HTML dashboard with KPI cards, architecture diagrams, compliance status, cost comparison |
| `migration-state.json` | Orchestration state file for resuming interrupted sessions |

## Installation

### Option A: Gemini CLI native

```bash
gemini skills install https://github.com/duboc/gemini-cli-skills.git --path skills/sybase-spanner-migration-orchestrator
```

### Option B: One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/duboc/gemini-cli-skills/main/scripts/install.sh | bash -s -- sybase-spanner-migration-orchestrator
```

For user-scope installation (available across all projects):

```bash
curl -fsSL https://raw.githubusercontent.com/duboc/gemini-cli-skills/main/scripts/install.sh | bash -s -- sybase-spanner-migration-orchestrator --scope user
```

### Option C: Manual

```bash
cp -r skills/sybase-spanner-migration-orchestrator ~/.gemini/skills/sybase-spanner-migration-orchestrator
```

## Usage Examples

Once installed, the skill activates when you ask Gemini to orchestrate a Sybase-to-Spanner migration.

### Full migration assessment

```
Migrate our Sybase ASE environment to Cloud Spanner end-to-end. We have
12 databases supporting trading, settlement, and regulatory reporting.
Run all four phases and produce a unified migration plan.
```

### Scoped assessment

```
Assess our Sybase settlement database for Spanner migration. It has
heavy stored procedure usage and Replication Server for DR. No IQ.
```

### Resume interrupted session

```
Resume the Sybase-to-Spanner migration assessment for our trading platform.
Pick up from where we left off.
```

### Compliance-focused assessment

```
We need to migrate our SOX-controlled Sybase databases to Spanner.
Focus on audit trail continuity and financial calculation validation.
```

### Quick wins identification

```
Scan our Sybase environment and identify quick wins — dead stored procedures
to remove, simple driver swaps, and reference data we can migrate first.
```

## Included References

| File | Description |
|------|-------------|
| **sybase-migration-checklist.md** | Pre-assessment intake questionnaire for Sybase environments, phase gate criteria with financial compliance checks, skill selection decision matrix, timeline estimation guidelines for database migrations, and risk escalation criteria. |
| **financial-migration-patterns.md** | Migration strategies for financial systems including parallel run validation, market-hours-aware cutover planning, strangler fig for databases, data type precision handling, and transaction pattern decomposition. |
| **spanner-financial-architecture.md** | Reference architectures for financial systems on Cloud Spanner including interleaved table design for trading, settlement data models, regulatory reporting patterns, multi-region configuration, and BigQuery federation. |
| **regulatory-compliance-guide.md** | Comprehensive compliance mapping for SOX, PCI-DSS, MiFID II, Dodd-Frank, and Basel III/IV controls from Sybase to Spanner, with audit trail migration strategies and encryption requirements. |
