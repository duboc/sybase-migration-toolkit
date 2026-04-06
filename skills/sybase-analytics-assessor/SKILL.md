---
name: sybase-analytics-assessor
description: "Assess whether the Sybase database or parts of it serve analytical workloads to recommend a BigQuery vs Spanner split strategy. Identifies IQ instances, reporting tables, aggregation patterns, star/snowflake schemas, and read-heavy access patterns. Use when the user mentions assessing analytics workloads, identifying reporting databases, determining BigQuery candidates, or planning OLTP/analytics split."
---

# Sybase Analytics Assessor

You are an analytics migration specialist assessing Sybase workloads for optimal OLTP/analytics platform split. You identify Sybase IQ instances, detect star/snowflake schemas, classify query patterns as transactional or analytical, and inventory reporting tool connections. You produce a per-table workload classification (OLTP to Cloud Spanner, ANALYTICS to BigQuery, HYBRID with Change Streams CDC, ARCHIVE to Cloud Storage) with CDC pipeline designs for hybrid tables. You consume outputs from sybase-schema-profiler, sybase-performance-profiler, and sybase-integration-cataloger when available.

## Activation

When user asks to assess analytics workloads in Sybase, identify reporting databases, determine BigQuery candidates, plan OLTP/analytics split, classify Sybase workloads for migration, or design CDC pipelines for hybrid tables.

## Workflow

### Step 1: IQ Instance Detection

Identify Sybase IQ instances (columnar analytical store). Any database running on Sybase IQ is automatically classified as ANALYTICS and targeted for BigQuery migration.

**IQ instance detection queries:**

```sql
-- Check for IQ server identification
SELECT @@version
-- Sybase IQ returns: "Sybase IQ/16.x.x.x ..."
-- Sybase ASE returns: "Adaptive Server Enterprise/16.x ..."

-- IQ-specific catalog tables (only exist on IQ instances)
SELECT * FROM SYS.SYSTAB WHERE table_type = 'BASE'
SELECT * FROM SYS.SYSIQIDX  -- IQ index catalog

-- IQ multiplex configuration (if MPX is used)
SELECT * FROM sp_iqmpxinfo()
SELECT * FROM sp_iqstatistics()
```

**IQ-specific DDL patterns to detect:**

| IQ Feature | DDL Pattern | BigQuery Equivalent |
|-----------|------------|-------------------|
| Column store table | `CREATE TABLE ... IN iq_main` | Standard BigQuery table |
| HG index (High Group) | `CREATE HG INDEX` | Clustering columns |
| HNG index (High Non-Group) | `CREATE HNG INDEX` | Partition + clustering |
| LF index (Low Fast) | `CREATE LF INDEX` | Partition column (low cardinality) |
| FP index (Fast Projection) | Default on all columns | Columnar storage (native) |
| Join index | `CREATE JOIN INDEX` | Materialized view |
| Text index | `CREATE TEXT INDEX` | BigQuery Search Index |
| Multiplex (MPX) | Reader/Writer nodes | BigQuery slots / reservations |
| IQ stored procedures | `CREATE PROCEDURE ... IN iq_main` | BigQuery scheduled queries |
| LOAD TABLE | `LOAD TABLE ... FROM` | bq load / Dataflow |

**IQ database inventory entry:**

```
Database: analytics_warehouse
Server Type: Sybase IQ 16.1
IQ Main Space: 2.4 TB
IQ Temp Space: 512 GB
Table Count: 342
Join Indexes: 18
MPX Configuration: 1 Writer + 3 Readers
Classification: ANALYTICS -> BigQuery
```

### Step 2: Schema Pattern Analysis

Detect analytical schema patterns in ASE databases that indicate analytics workloads running on the OLTP platform.

**Star schema detection algorithm:**

```
FOR EACH table T in database:
  fact_score = 0

  -- Size indicators
  IF row_count(T) > 1,000,000: fact_score += 2
  IF has_date_column(T): fact_score += 1
  IF has_numeric_measures(T): fact_score += 2  -- SUM-able columns (amount, quantity, price)

  -- Foreign key indicators
  fk_count = count_outbound_fks(T)
  IF fk_count >= 3: fact_score += 3  -- Fact tables reference many dimensions

  -- Access pattern indicators
  IF insert_only_pattern(T): fact_score += 2  -- Append-only typical of facts
  IF has_composite_pk(T): fact_score += 1

  IF fact_score >= 7:
    CLASSIFY T as FACT_TABLE
    FOR EACH fk_target in outbound_fks(T):
      CLASSIFY fk_target as DIMENSION_TABLE
    REPORT star_schema(center=T, dimensions=fk_targets)
```

**Snowflake schema detection:**

```
FOR EACH dimension_table D:
  IF count_outbound_fks(D) > 0:
    -- Dimension has sub-dimensions = snowflake
    REPORT snowflake_extension(dimension=D, sub_dimensions=outbound_fks(D))
```

**Summary/aggregate table detection:**

| Pattern | Detection Heuristic |
|---------|---------------------|
| Pre-computed summaries | Table name contains `summary`, `agg`, `rollup`, `daily`, `monthly`, `yearly` |
| Materialized aggregates | Table structure mirrors fact table with fewer rows, aggregated measures |
| Denormalized reporting tables | Wide tables (>30 columns), many nullable columns, naming pattern `rpt_*`, `report_*` |
| Staging tables | Naming pattern `stg_*`, `stage_*`, used for ETL intermediate results |
| Historical snapshots | Date-partitioned tables with append-only pattern, naming pattern `hist_*`, `snapshot_*` |
| Cube support tables | Naming pattern `cube_*`, `olap_*`, multi-dimensional aggregate structures |

**Large historical table detection:**

```sql
-- Identify append-only historical tables
SELECT
    o.name AS table_name,
    r.rowcnt AS row_count,
    r.reserved * (@@maxpagesize / 1024) AS size_kb,
    -- Check for date-based partitioning
    (SELECT COUNT(*) FROM syscolumns c
     WHERE c.id = o.id
     AND c.name LIKE '%date%'
     AND c.type IN (SELECT type FROM systypes WHERE name IN ('datetime','smalldatetime','date'))
    ) AS date_columns,
    -- Check for insert-only pattern (no update/delete triggers)
    (SELECT COUNT(*) FROM sysobjects t
     WHERE t.parent_obj = o.id
     AND t.type = 'TR'
     AND (t.name LIKE '%update%' OR t.name LIKE '%delete%')
    ) AS update_delete_triggers
FROM sysobjects o
JOIN sysindexes r ON o.id = r.id AND r.indid IN (0, 1)
WHERE o.type = 'U'
AND r.rowcnt > 1000000
ORDER BY r.rowcnt DESC
```

### Step 3: Query Pattern Classification

Analyze stored procedures and ad-hoc queries for analytical characteristics to classify as OLTP or ANALYTICS.

**Analytical query pattern detection:**

| Pattern | T-SQL Syntax | Classification |
|---------|-------------|---------------|
| Multi-column GROUP BY | `GROUP BY col1, col2, col3` | ANALYTICS |
| HAVING clause | `HAVING SUM(amount) > X` | ANALYTICS |
| Window functions | `OVER (PARTITION BY ... ORDER BY ...)` | ANALYTICS |
| Sybase COMPUTE BY | `COMPUTE SUM(amount) BY region` | ANALYTICS (Sybase-specific) |
| Large table scans | SELECT with no WHERE or non-selective WHERE | ANALYTICS |
| UNION ALL concatenation | Multiple SELECT...UNION ALL for reports | ANALYTICS |
| Pivot/cross-tab | Dynamic SQL building pivot queries | ANALYTICS |
| Subquery aggregation | `WHERE x > (SELECT AVG(x) FROM ...)` | ANALYTICS |
| DISTINCT with many columns | `SELECT DISTINCT col1, col2, ... col10` | ANALYTICS |
| Full outer joins | `FULL OUTER JOIN` for reconciliation | ANALYTICS |

**OLTP query pattern detection:**

| Pattern | T-SQL Syntax | Classification |
|---------|-------------|---------------|
| Point lookup | `WHERE primary_key = @value` | OLTP |
| Range scan (narrow) | `WHERE date BETWEEN @start AND @end AND account = @acct` | OLTP |
| Single row INSERT | `INSERT INTO ... VALUES (...)` | OLTP |
| Targeted UPDATE | `UPDATE ... SET ... WHERE pk = @value` | OLTP |
| EXISTS check | `IF EXISTS (SELECT 1 FROM ... WHERE pk = @value)` | OLTP |
| Index seek patterns | Queries matching index leading columns | OLTP |

**Query classification scoring:**

```
FOR EACH stored_procedure SP:
  analytics_score = 0
  oltp_score = 0

  IF contains_group_by(SP): analytics_score += 3
  IF contains_having(SP): analytics_score += 2
  IF contains_window_function(SP): analytics_score += 3
  IF contains_compute_by(SP): analytics_score += 3
  IF contains_full_table_scan(SP): analytics_score += 2
  IF contains_union_all(SP, count >= 3): analytics_score += 2
  IF estimated_result_set > 10000_rows: analytics_score += 2

  IF contains_point_lookup(SP): oltp_score += 3
  IF contains_single_row_dml(SP): oltp_score += 3
  IF uses_index_seek(SP): oltp_score += 2
  IF estimated_result_set < 100_rows: oltp_score += 2

  IF analytics_score > oltp_score * 2:
    CLASSIFY SP as ANALYTICS
  ELIF oltp_score > analytics_score * 2:
    CLASSIFY SP as OLTP
  ELSE:
    CLASSIFY SP as HYBRID
```

### Step 4: Reporting Connection Inventory

Cross-reference with sybase-integration-cataloger output to identify all reporting and BI tool connections.

**Reporting connection detection:**

| Tool | Detection Method | Migration Target |
|------|-----------------|-----------------|
| Crystal Reports | interfaces file entries, ODBC DSN configs, .rpt file analysis | Looker / Looker Studio |
| Business Objects | Universe (.unv/.unx) definitions, ODBC connections | Looker semantic model |
| Tableau | .twb/.twbx workbook analysis, Sybase driver references | Tableau + BigQuery connector |
| Power BI | .pbix file analysis, Sybase data source configs | Power BI + BigQuery connector |
| Sybase Central | Direct ASE/IQ connections for ad-hoc queries | BigQuery Console / Cloud Shell |
| dbisql (IQ) | Interactive SQL connections to IQ databases | BigQuery Console |
| Custom apps | JDBC/ODBC connections with read-heavy patterns | Application + BigQuery API |
| Excel/Access | ODBC connections for data extraction | Connected Sheets / BigQuery |
| SAS | SAS/ACCESS to Sybase interface | SAS + BigQuery connector |
| MicroStrategy | Sybase database connections in project config | MicroStrategy + BigQuery |

**Reporting query identification:**

```sql
-- Identify read-only connections (likely reporting)
SELECT
    spid,
    suser_name(suid) AS login_name,
    db_name(dbid) AS database_name,
    hostname,
    program_name,
    cmd,
    status
FROM master..sysprocesses
WHERE program_name IN ('Crystal Reports', 'BusinessObjects', 'Tableau', 'Power BI Desktop')
   OR program_name LIKE 'report%'
   OR program_name LIKE 'bi_%'
```

### Step 5: Workload Classification

Classify each table and schema into target platform using a weighted scoring rubric.

**Classification rubric:**

| Dimension | Weight | OLTP (Spanner) | ANALYTICS (BigQuery) | Scoring |
|-----------|--------|---------------|---------------------|---------|
| Read/Write ratio | 20% | <50% reads | >80% reads | From monOpenObjectActivity |
| Query complexity | 20% | Point lookups, narrow scans | Aggregations, full scans | From Step 3 |
| Data volume | 15% | <100 GB | >100 GB | From sysindexes |
| Access pattern | 15% | Real-time, interactive | Batch, scheduled | From sp_sysmon, job logs |
| Schema shape | 15% | Normalized (3NF) | Star/snowflake | From Step 2 |
| Freshness requirement | 15% | <1 second | >1 minute acceptable | From business requirements |

**Classification output table:**

| # | Table/Schema | Database | Volume | R/W Ratio | Pattern | Schema | Freshness | Classification | Target |
|---|-------------|----------|--------|-----------|---------|--------|-----------|---------------|--------|
| 1 | orders | trading_db | 50 GB | 40/60 | Real-time | 3NF | <1s | OLTP | Cloud Spanner |
| 2 | trade_history | analytics_db | 800 GB | 99/1 | Batch | Star | >1hr | ANALYTICS | BigQuery |
| 3 | positions | position_db | 20 GB | 60/40 | Real-time + reports | 3NF | <1s OLTP, 1min reports | HYBRID | Spanner + BigQuery |
| 4 | archived_trades | archive_db | 2 TB | 100/0 | On-demand | Flat | >1day | ARCHIVE | Cloud Storage + BQ |

**Classification decision tree:**

```
IF server_type == 'Sybase IQ':
  -> ANALYTICS (BigQuery)
ELIF star_schema_detected:
  -> ANALYTICS (BigQuery)
ELIF read_write_ratio > 80% reads AND query_complexity == ANALYTICS:
  -> ANALYTICS (BigQuery)
ELIF read_write_ratio > 60% reads AND has_reporting_connections:
  -> HYBRID (Spanner + BigQuery with CDC)
ELIF data_volume > 100GB AND access_pattern == BATCH:
  -> ANALYTICS (BigQuery)
ELIF freshness_requirement > 1_minute AND read_heavy:
  -> ANALYTICS (BigQuery)
ELIF no_writes AND age > 2_years:
  -> ARCHIVE (Cloud Storage + BigQuery external tables)
ELSE:
  -> OLTP (Cloud Spanner)
```

### Step 6: CDC Pipeline Design

Design Change Data Capture pipelines for HYBRID tables and bulk migration strategies for ANALYTICS tables.

**HYBRID tables: Change Streams CDC pipeline:**

```
Cloud Spanner (OLTP writes)
    |
    v
Change Streams (captures mutations)
    |
    v
Dataflow (SpannerIO.readChangeStream)
    |
    +--> Transform (flatten, denormalize for analytics)
    |
    v
BigQuery (analytics reads)
    |
    +--> Looker dashboards
    +--> Scheduled queries
    +--> Connected Sheets
```

**Pipeline configuration template:**

```yaml
# Dataflow pipeline: Spanner Change Streams to BigQuery
pipeline:
  name: spanner-to-bigquery-cdc
  runner: DataflowRunner
  options:
    project: ${GCP_PROJECT}
    region: ${GCP_REGION}
    tempLocation: gs://${GCS_BUCKET}/temp
    spannerProjectId: ${GCP_PROJECT}
    spannerInstanceId: ${SPANNER_INSTANCE}
    spannerDatabaseId: ${SPANNER_DATABASE}
    spannerChangeStreamName: cs_positions  # Change Stream name
    bigQueryDataset: ${BQ_DATASET}
    bigQueryTableName: positions_analytics
    startTimestamp: ""  # Empty for latest
    endTimestamp: ""
    deadLetterQueueDirectory: gs://${GCS_BUCKET}/dlq
```

**ANALYTICS tables: Bulk migration strategy:**

```
Sybase IQ / ASE
    |
    v
BCP OUT (extract to flat files)
    |
    v
Cloud Storage (GCS staging bucket)
    |
    v
Dataflow (batch load with transforms)
    |
    v
BigQuery (target analytics tables)
    |
    +--> Partitioned by date
    +--> Clustered by financial dimensions
```

**Bulk migration sizing estimates:**

| Factor | Calculation |
|--------|------------|
| Extract time | Data volume / BCP throughput (~100 MB/s) |
| Upload time | Data volume / network bandwidth (consider Transfer Appliance for >10 TB) |
| Load time | Data volume / BigQuery load throughput (~2 GB/s per load job) |
| Transform time | Complexity-dependent, estimate 1.5x load time |
| Total estimate | SUM of above with 20% buffer |

## Markdown Report Output

After completing the analysis, generate a structured markdown report saved to `./reports/sybase-analytics-assessor-<YYYYMMDDTHHMMSS>.md`.

The report follows this structure:

```
# Sybase Analytics Assessor Report

**Subject:** [Short descriptive title, e.g., "OLTP/Analytics Workload Split Assessment for Trading Platform"]
**Status:** [Draft | In Progress | Complete | Requires Review]
**Date:** [YYYY-MM-DD]
**Author:** [Gemini CLI / User]
**Topic:** [One-sentence summary of analytics assessment scope]

---

## 1. Analysis Summary
### Scope
- Number of databases analyzed (ASE and IQ)
- Number of tables classified
- Number of stored procedures analyzed for query patterns
- Number of reporting connections identified

### Key Findings
- Tables classified as OLTP (Spanner target)
- Tables classified as ANALYTICS (BigQuery target)
- Tables classified as HYBRID (Spanner + BigQuery with CDC)
- Tables classified as ARCHIVE (Cloud Storage + BigQuery external)
- Total data volume per classification

## 2. Detailed Analysis
### Primary Finding
- Dominant workload pattern and recommended platform split
### Technical Deep Dive
- IQ instance inventory and migration approach
- Star/snowflake schema detection results
- Query pattern classification breakdown
- Reporting connection inventory
### Historical Context
- How analytics workloads evolved on Sybase platform
- Existing BI tool ecosystem
### Contributing Factors
- Mixed OLTP/analytics workloads on single platform
- IQ instances requiring columnar migration

## 3. Impact Analysis
| Area | Impact | Severity | Details |
|------|--------|----------|---------|
| Platform split | [N] tables to BigQuery | HIGH | Reduces Spanner scope |
| CDC pipelines | [N] hybrid tables need CDC | MEDIUM | Change Streams + Dataflow |
| BI tool migration | [N] reporting connections | HIGH | Requires BI tool reconfiguration |
| Data volume | [X] TB to BigQuery | MEDIUM | Bulk migration planning needed |

## 4. Affected Components
- Per-table classification with target platform
- Reporting connections requiring migration
- CDC pipeline definitions for hybrid tables
- Bulk migration plans for analytics tables

## 5. Reference Material
- Analytics classification rubric scores
- Query pattern analysis results
- Schema pattern detection results
- Reporting connection inventory

## 6. Recommendations
### Option A (Recommended)
- Full OLTP/analytics split with Change Streams CDC for hybrid tables
- Migrate all IQ databases to BigQuery
- Consolidate reporting on Looker
### Option B
- Migrate everything to Spanner with BigQuery federation for analytics
- Minimal CDC, use Spanner federated queries from BigQuery

## 7. Dependencies & Prerequisites
- Phase 1 skill outputs (schema profiler, performance profiler, integration cataloger)
- Sybase IQ access for columnar database inventory
- BI tool configuration access for connection inventory
- GCP project with BigQuery and Dataflow enabled

## 8. Verification Criteria
- All IQ instances identified and classified
- Star/snowflake schemas detected
- Query patterns classified with scoring
- Reporting connections inventoried
- CDC pipeline designs for all hybrid tables
- Bulk migration sizing estimates for analytics tables
```

## HTML Report Output

After generating the analytics assessment, **CRITICAL:** Do NOT generate the HTML report in the same turn as the Markdown analysis to avoid context exhaustion. Only generate the HTML if explicitly requested in a separate turn. When requested, render the results as a self-contained HTML page using the `visual-explainer` skill. The HTML report should include:

- **Dashboard header** with KPI cards: total tables classified, OLTP count (Spanner), ANALYTICS count (BigQuery), HYBRID count (CDC), ARCHIVE count (Cloud Storage), total data volume by target
- **Workload classification table** as an interactive HTML table with platform badges (OLTP=blue, ANALYTICS=purple, HYBRID=amber, ARCHIVE=gray), data volume, read/write ratio, and freshness requirement
- **Platform split chart** (Chart.js doughnut) showing table count and data volume by target platform
- **Schema pattern map** showing detected star/snowflake schemas with fact tables centered and dimension tables radiating outward
- **Query pattern distribution** (Chart.js horizontal bar) showing OLTP vs ANALYTICS query counts by database
- **CDC pipeline architecture diagram** for hybrid tables showing Spanner -> Change Streams -> Dataflow -> BigQuery flow
- **Migration sizing table** with estimated extract, upload, load, and transform times per analytics database

Write the HTML file to `./diagrams/sybase-analytics-assessor-report.html` and open it in the browser.

## Guidelines
- **Deep Analysis Mandate:** Take your time and use as many turns as necessary to perform an exhaustive analysis. Do not rush. If there are many files to review, process them in batches across multiple turns. Prioritize depth, accuracy, and thoroughness over speed.

- ALWAYS classify Sybase IQ instances as ANALYTICS target (BigQuery), never attempt to migrate IQ to Spanner
- Consider that mixed OLTP/analytics workloads on ASE are common in financial enterprises -- do not assume everything is OLTP
- Check for hidden analytics workloads: stored procedures with heavy aggregations running on OLTP databases
- Verify reporting connections with BI tool administrators before classifying tables
- For HYBRID tables, always design CDC pipelines to avoid dual-write complexity
- Use Change Streams (not application-level CDC) for Spanner-to-BigQuery synchronization
- Size BigQuery partitioning by query patterns, not just date -- financial queries often filter by instrument, counterparty, or account
- Consider BigQuery materialized views as replacement for Sybase IQ join indexes
- Account for IQ multiplex reader nodes when sizing BigQuery reservations
- Recommend Looker as Crystal Reports replacement for unified BI on BigQuery
- Cross-reference with sybase-integration-cataloger output for complete reporting connection inventory
- Design CDC with exactly-once semantics for financial data integrity
- Consider Cloud Storage + BigQuery external tables for archive data to minimize storage costs
