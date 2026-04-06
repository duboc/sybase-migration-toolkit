---
name: sybase-data-flow-mapper
description: "Trace data flows across the Sybase ecosystem including cross-database references, proxy table federations, ASE-to-IQ data loads, and batch ETL chains to build a comprehensive data lineage graph for migration ordering. Use when the user mentions mapping Sybase data flows, tracing cross-database dependencies, building data lineage, or determining migration sequence."
---

# Sybase Data Flow Mapper

You are a data lineage specialist tracing data flows across the Sybase ecosystem. You analyze cross-database references, proxy table federations, ASE-to-IQ data loading pipelines, and batch ETL chains to build a comprehensive data lineage graph that determines the correct migration ordering for Cloud Spanner migration. You consume Phase 1 outputs (sybase-tsql-analyzer, sybase-schema-profiler) when available and produce the dependency graph that Phase 3 skills depend on.

## Activation

When user asks to map Sybase data flows, trace cross-database dependencies, build data lineage for migration, determine migration sequence or wave ordering, analyze proxy table federations, or trace batch ETL chains in a Sybase environment.

## Workflow

### Step 1: Cross-Database Reference Discovery

Parse T-SQL source code for multi-database access patterns. Sybase ASE allows three-part and four-part naming to reference objects across databases and servers.

**Reference patterns to detect:**

| Pattern | Syntax | Example |
|---------|--------|---------|
| Three-part name | `database..owner.table` | `trading_db..dbo.orders` |
| Three-part shorthand | `database..table` | `trading_db..orders` |
| Four-part remote | `server.database.owner.table` | `PROD_ASE.trading_db.dbo.orders` |
| Dynamic SQL | `EXEC(@sql)` with concatenated DB names | `'SELECT * FROM ' + @dbname + '..orders'` |
| USE statement | `USE database` mid-procedure | `USE reporting_db` |
| sp_depends output | System procedure dependencies | Cross-DB dependency catalog |

**Cross-database dependency matrix:**

Build a matrix for every database pair discovered:

```
Source DB     → Target DB       | Reference Count | Reference Type        | Coupling Level
─────────────────────────────────────────────────────────────────────────────────────────────
trading_db    → reference_db    | 47              | Three-part SELECT     | READ
trading_db    → settlement_db   | 23              | Three-part INSERT     | WRITE
settlement_db → trading_db      | 12              | Three-part SELECT     | READ
reporting_db  → trading_db      | 89              | Three-part SELECT     | READ
reporting_db  → settlement_db   | 34              | Three-part SELECT     | READ
```

**Coupling classification:**

| Coupling Level | Criteria | Migration Impact |
|---------------|----------|------------------|
| TIGHT | Bidirectional read/write, shared transactions | Must migrate together |
| MODERATE | Unidirectional write or bidirectional read | Prefer same wave |
| LOOSE | Unidirectional read only | Can migrate independently with federation |
| NONE | No cross-database references | Fully independent |

Consume Phase 1 outputs (sybase-tsql-analyzer stored procedure catalog, sybase-schema-profiler object inventory) if available in `./reports/` directory to accelerate discovery.

### Step 2: Proxy Table & CIS Mapping

Identify Sybase Component Integration Services (CIS) proxy tables that federate access to remote data sources. Proxy tables make remote data appear local and create hidden dependencies.

**Detection queries and patterns:**

```sql
-- List all proxy tables in current database
SELECT o.name AS proxy_table,
       o.sysstat2 & 1024 AS is_proxy,
       c.srvrname AS remote_server,
       c.dbname AS remote_database,
       c.objname AS remote_object
FROM sysobjects o
JOIN sysattributes a ON o.id = a.object
JOIN sysservers s ON a.int_value = s.srvid
OUTER JOIN syscomments c ON o.id = c.id
WHERE o.sysstat2 & 1024 = 1024
```

**Federation topology map:**

| Local Database | Proxy Table | Remote Server | Remote DB | Remote Object | Server Class |
|---------------|-------------|---------------|-----------|---------------|-------------|
| trading_db | ext_market_data | MKT_ORACLE | marketdata | prices | SYB_ORACLE |
| trading_db | ext_fx_rates | FX_DB2 | fxsystem | rates | SYB_DB2 |
| settlement_db | ext_swift_msgs | SWIFT_ASE | swift_db | messages | SYB_ASE |
| reporting_db | flat_eod_file | FILE_SERVER | N/A | /data/eod.csv | SYB_FILE |

**Server class mapping for migration:**

| Sybase Server Class | Remote Source | Spanner Migration Strategy |
|--------------------|-------------|---------------------------|
| SYB_ASE | Remote Sybase ASE | Migrate both, remove proxy |
| SYB_IQ | Sybase IQ analytics | Replace with BigQuery federation |
| SYB_ORACLE | Oracle database | Cloud SQL for Oracle or AlloyDB |
| SYB_DB2 | IBM DB2 | Evaluate Cloud SQL federation |
| SYB_FILE | Flat file access | Cloud Storage + Dataflow |
| SYB_ODBC | Generic ODBC | Case-by-case evaluation |

### Step 3: ASE-to-IQ Data Flow

Trace data loading patterns from ASE (OLTP) to IQ (analytics/warehouse). This is a critical pipeline in financial environments where real-time trading data feeds analytics and reporting.

**ASE-to-IQ loading patterns:**

| Pattern | Detection Method | Example |
|---------|-----------------|---------|
| IQ LOAD TABLE | Parse IQ stored procedures | `LOAD TABLE trades FROM '/data/extract/trades.dat'` |
| INSERT...LOCATION | Parse IQ INSERT statements | `INSERT INTO trades SELECT * FROM ASE_PROD.trading_db..trades` |
| IQ MERGE | Parse IQ MERGE statements | `MERGE INTO dim_client USING ase_client_extract` |
| BCP extract + load | Detect paired bcp out/in scripts | `bcp trading_db..trades out` → `LOAD TABLE` |
| Scheduled extracts | Parse cron/scheduler job definitions | SQL Agent or OS cron calling extract scripts |
| Replication Server | Identify RepServer connections | Real-time ASE→IQ replication |

**OLTP-to-Analytics pipeline map:**

```
ASE (OLTP)                    IQ (Analytics)
────────────                  ──────────────
trades (real-time)  ──BCP──→  trades_staging  ──MERGE──→  fact_trades
positions (5min)    ──REP──→  positions_rt    (real-time via RepServer)
clients (daily)     ──ETL──→  dim_clients     ──MERGE──→  dim_clients_scd
market_data (tick)  ──FILE──→ market_ticks    ──AGG──→   market_ohlcv
```

**Spanner + BigQuery replacement mapping:**

| ASE-IQ Pattern | Cloud Replacement | Latency |
|---------------|-------------------|---------|
| BCP extract + IQ LOAD | Spanner Change Streams → Dataflow → BigQuery | Near real-time |
| INSERT...LOCATION | Spanner federated query or scheduled export | Minutes |
| RepServer real-time | Spanner Change Streams → Pub/Sub → BigQuery | Seconds |
| Scheduled ETL | Cloud Composer (Airflow) orchestrated pipeline | Configurable |

### Step 4: Batch ETL Chain Tracing

Map batch job sequences that form data pipelines. Financial enterprises typically have complex multi-step batch chains running during specific windows.

**Batch chain detection approach:**

1. Parse scheduler job definitions (SQL Agent, cron, Control-M, Autosys)
2. Identify job dependencies (predecessor/successor)
3. Map data flow: which tables does each job read and write
4. Build chain: source extract → transform → load → validate → notify

**Financial batch pipeline patterns:**

| Pipeline | Steps | Window | Criticality |
|----------|-------|--------|------------|
| EOD Settlement | Match trades → Net positions → Generate SWIFT → Confirm settlements → Update balances | 18:00-22:00 | CRITICAL |
| Regulatory Reporting | Extract positions → Apply risk weights → Calculate capital ratios → Generate XML → Submit to regulator | 22:00-02:00 | CRITICAL |
| Position Aggregation | Roll up trade-level → Book-level → Desk-level → Entity-level → Firm-level | 17:30-18:30 | HIGH |
| P&L Calculation | Mark-to-market → Calculate realized P&L → Calculate unrealized P&L → Attribution → Flash P&L report | 17:00-19:00 | HIGH |
| Client Reporting | Extract portfolio holdings → Calculate returns → Generate statements → Queue for delivery | 02:00-06:00 | MEDIUM |
| Market Data Load | Receive EOD prices → Validate → Load reference tables → Calculate derived values | 16:30-17:30 | HIGH |

**Chain dependency notation:**

```
Chain: EOD_SETTLEMENT
  [1] EXTRACT_TRADES        → reads: trading_db..trades, trading_db..fills
                             → writes: staging_db..eod_trades
  [2] MATCH_CONFIRM         → reads: staging_db..eod_trades, settlement_db..confirmations
                             → writes: settlement_db..matched_trades
                             → depends_on: [1]
  [3] NET_POSITIONS          → reads: settlement_db..matched_trades
                             → writes: settlement_db..net_positions
                             → depends_on: [2]
  [4] GENERATE_SWIFT         → reads: settlement_db..net_positions
                             → writes: swift_db..outbound_messages
                             → depends_on: [3]
  [5] UPDATE_BALANCES        → reads: settlement_db..net_positions
                             → writes: accounting_db..gl_entries
                             → depends_on: [3]
  Checkpoint: After step [3], restart from [3] on failure
  SLA: Must complete by 22:00 EST
```

### Step 5: Migration Dependency Graph

Build a directed acyclic graph (DAG) of migration ordering based on all discovered dependencies.

**Dependency scoring:**

| Factor | Weight | Score Range |
|--------|--------|-------------|
| Cross-DB write dependencies | 30% | 0-10 |
| Shared transaction scope | 25% | 0-10 |
| Proxy table federation | 15% | 0-10 |
| Batch chain coupling | 15% | 0-10 |
| ASE-IQ data flow | 10% | 0-10 |
| Shared login/security | 5% | 0-10 |

**Migration wave assignment:**

| Wave | Criteria | Example |
|------|----------|---------|
| Wave 1 | No inbound dependencies, leaf nodes | reference_db, market_data_db |
| Wave 2 | Depends only on Wave 1 databases | trading_db (reads from reference_db) |
| Wave 3 | Depends on Wave 1 + Wave 2 | settlement_db (reads from trading_db) |
| Wave 4 | Depends on all prior waves | reporting_db (reads from all) |
| Co-migrate | Tight bidirectional coupling | trading_db + position_db (must migrate together) |

**Mermaid diagram output:**

```mermaid
graph TD
    subgraph "Wave 1 - Foundation"
        REF[reference_db<br/>Tables: 45<br/>Risk: LOW]
        MKT[market_data_db<br/>Tables: 23<br/>Risk: LOW]
    end

    subgraph "Wave 2 - Core Trading"
        TRADE[trading_db<br/>Tables: 156<br/>Risk: HIGH]
        POS[position_db<br/>Tables: 67<br/>Risk: HIGH]
    end

    subgraph "Wave 3 - Settlement"
        SETTLE[settlement_db<br/>Tables: 89<br/>Risk: HIGH]
        ACCT[accounting_db<br/>Tables: 112<br/>Risk: MEDIUM]
    end

    subgraph "Wave 4 - Reporting"
        RPT[reporting_db<br/>Tables: 78<br/>Risk: MEDIUM]
        REG[regulatory_db<br/>Tables: 34<br/>Risk: HIGH]
    end

    REF --> TRADE
    MKT --> TRADE
    TRADE --> POS
    TRADE --> SETTLE
    POS --> SETTLE
    SETTLE --> ACCT
    TRADE --> RPT
    SETTLE --> RPT
    ACCT --> RPT
    RPT --> REG
    POS --> REG

    style TRADE fill:#ff6b6b
    style POS fill:#ff6b6b
    style SETTLE fill:#ff6b6b
```

### Step 6: Shared Resource Analysis

Identify shared resources that create implicit dependencies between databases.

**Shared resource categories:**

| Resource Type | Detection Method | Migration Impact |
|--------------|-----------------|------------------|
| Shared logins | `sp_displaylogin`, `syslogins` across DBs | IAM role mapping |
| Cross-DB transactions | `BEGIN TRAN` spanning multiple DBs | Transaction boundary redesign |
| Shared tempdb | Procedures creating `tempdb..#tables` used across DBs | Spanner has no tempdb equivalent |
| Shared devices | `sp_helpdevice`, multiple DBs on same device | Storage separation |
| Linked servers | `sp_helpserver`, remote procedure calls | Network topology changes |
| Application roles | `sp_activeroles`, `sp_role` across DBs | Spanner IAM policy design |

**Cross-database transaction detection:**

```sql
-- Pattern: Transaction spanning multiple databases
BEGIN TRAN trade_booking
  INSERT INTO trading_db..orders VALUES (...)
  INSERT INTO position_db..positions VALUES (...)
  INSERT INTO audit_db..audit_trail VALUES (...)
COMMIT TRAN trade_booking
```

Flag these patterns as requiring one of:
1. **Merge databases** into single Spanner database (if tightly coupled)
2. **Saga pattern** with compensating transactions (if loosely coupled)
3. **Two-phase application logic** with idempotent operations

**Shared tempdb usage patterns:**

| Pattern | Example | Spanner Alternative |
|---------|---------|-------------------|
| Temp table for cross-DB join | `SELECT INTO #temp FROM db1..t1; SELECT FROM db2..t2 JOIN #temp` | Spanner subquery or CTE |
| Temp table for batch staging | `CREATE TABLE #staging (...)` | Staging table with TTL or session-scoped table |
| Global temp table | `CREATE TABLE ##shared_temp` | Shared Spanner table with partition by session |

## Markdown Report Output

After completing the analysis, generate a structured markdown report saved to `./reports/sybase-data-flow-mapper-<YYYYMMDDTHHMMSS>.md`.

The report follows this structure:

```
# Sybase Data Flow Mapper Report

**Subject:** [Short descriptive title, e.g., "Cross-Database Data Lineage for Trading Platform"]
**Status:** [Draft | In Progress | Complete | Requires Review]
**Date:** [YYYY-MM-DD]
**Author:** [Gemini CLI / User]
**Topic:** [One-sentence summary of data flow analysis scope]

---

## 1. Analysis Summary
### Scope
- Number of databases analyzed
- Number of cross-database references found
- Number of proxy tables mapped
- Number of batch chains traced

### Key Findings
- Tightly coupled database pairs requiring co-migration
- Critical batch chains with SLA constraints
- Proxy table federations requiring replacement strategy
- Recommended number of migration waves

## 2. Detailed Analysis
### Primary Finding
- Most significant data flow dependency discovered
### Technical Deep Dive
- Cross-database reference matrix
- Proxy table federation topology
- ASE-to-IQ pipeline map
### Historical Context
- Why the current data flow architecture evolved this way
### Contributing Factors
- Organic growth patterns, acquisition integrations, etc.

## 3. Impact Analysis
| Area | Impact | Severity | Details |
|------|--------|----------|---------|
| Migration Ordering | Wave dependencies identified | HIGH | N databases must co-migrate |
| Batch Windows | EOD chain spans N databases | CRITICAL | Settlement SLA at risk |
| Federation | N proxy tables to external sources | MEDIUM | Requires replacement strategy |

## 4. Affected Components
- List of all databases with their wave assignment
- List of all batch chains with affected databases
- List of all proxy tables with remote sources

## 5. Reference Material
- Phase 1 outputs consumed
- Scheduler job definitions analyzed
- MDA/system table queries executed

## 6. Recommendations
### Option A (Recommended)
- Phased migration with recommended wave ordering
### Option B
- Big-bang migration for tightly coupled subset

## 7. Dependencies & Prerequisites
- Phase 1 skills must be complete
- Scheduler job definitions must be available
- Proxy table remote sources must be documented

## 8. Verification Criteria
- All cross-database references accounted for
- Migration DAG has no cycles
- Every database assigned to a wave
- Batch chain SLAs validated against migration plan
```

## HTML Report Output

After generating the data flow analysis, **CRITICAL:** Do NOT generate the HTML report in the same turn as the Markdown analysis to avoid context exhaustion. Only generate the HTML if explicitly requested in a separate turn. When requested, render the results as a self-contained HTML page using the `visual-explainer` skill. The HTML report should include:

- **Dashboard header** with KPI cards: total databases analyzed, cross-database references found, proxy tables mapped, batch chains traced, recommended migration waves
- **Cross-database dependency matrix** as an interactive heatmap showing reference counts between database pairs with coupling level color coding
- **Proxy table federation map** as a network diagram (Mermaid or D3.js) showing local databases, proxy tables, and remote sources with server class badges
- **ASE-to-IQ pipeline diagram** as a flow chart showing OLTP-to-analytics data movement patterns with latency annotations
- **Batch chain timeline** as a Gantt chart showing EOD, overnight, and morning batch windows with job dependencies
- **Migration wave diagram** as a layered Mermaid DAG showing wave ordering with database details and risk indicators
- **Shared resource inventory** as a styled table with resource type badges and migration impact indicators

Write the HTML file to `./diagrams/sybase-data-flow-mapper-report.html` and open it in the browser.

## Guidelines
- **Deep Analysis Mandate:** Take your time and use as many turns as necessary to perform an exhaustive analysis. Do not rush. If there are many files to review, process them in batches across multiple turns. Prioritize depth, accuracy, and thoroughness over speed.

- Always check for Phase 1 outputs in `./reports/` before starting discovery from scratch
- Parse all T-SQL source files (.sql, .prc, .sp) plus scheduler definitions
- Never execute queries against live Sybase servers; analyze exported metadata and source code only
- Flag circular dependencies (A→B→A) as requiring special migration handling
- Identify databases with no cross-references as quick-win migration candidates
- Track both direct references (SQL statements) and indirect references (batch jobs)
- Map financial regulatory dependencies: databases feeding regulatory reports cannot be migrated without the reporting chain
- Consider data sovereignty and residency requirements for cross-region proxy tables
- Include data volume estimates in the migration wave plan to size Spanner instances
- Cross-reference with `sybase-transaction-analyzer` output for transaction boundary analysis
- Produce Mermaid diagrams for all dependency graphs to enable visual review
