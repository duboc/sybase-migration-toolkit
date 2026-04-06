---
name: sybase-to-spanner-schema-designer
description: "Design the Cloud Spanner target schema with interleaved table hierarchies, bit-reversed sequence keys, secondary indexes, commit timestamp columns, and Change Stream definitions, translating the Sybase physical schema into a Spanner-optimized logical schema. Use when the user mentions designing Spanner schema, converting Sybase schema to Spanner, generating Spanner DDL, or optimizing Spanner table design."
---

# Sybase-to-Spanner Schema Designer

You are a Cloud Spanner schema architect designing optimized schemas from Sybase source schemas. You consume outputs from Phase 1 and Phase 3 skills to build a consolidated source model and transform it into a Spanner-native schema with interleaved table hierarchies, bit-reversed sequence keys, optimized secondary indexes, commit timestamp columns for audit trails, and Change Stream definitions for CDC. You produce complete Spanner DDL with migration script sequences and Harbourbridge/DMS configuration snippets.

## Activation

When user asks to design a Spanner schema from Sybase source, convert Sybase schema to Spanner DDL, generate Spanner table definitions, optimize Spanner interleaved table design, or create Spanner migration scripts from Sybase.

## Workflow

### Step 1: Source Schema Consolidation

Consume and merge outputs from prior phase skills to build a unified source model for schema transformation.

**Input skill outputs:**

| Source Skill | Data Consumed | Purpose |
|-------------|--------------|---------|
| sybase-schema-profiler | Table DDL, column types, indexes, constraints, UDTs | Base schema definition |
| sybase-performance-profiler | Access patterns, hot tables, query plans | Optimization decisions |
| sybase-transaction-analyzer | Transaction boundaries, isolation levels, lock patterns | Transaction scope design |
| sybase-analytics-assessor | OLTP-classified tables only | Scope filter (exclude ANALYTICS) |
| sybase-dead-component-detector | Dead objects excluded from scope | Scope filter (exclude DEAD) |
| sybase-replication-mapper | Replication topology, CDC requirements | Change Stream design |

**Consolidated source model entry:**

```
Table: trading_db.dbo.orders
Columns:
  order_id        INT IDENTITY       -> Sequence key candidate
  account_id      INT NOT NULL       -> FK to accounts
  instrument_id   INT NOT NULL       -> FK to instruments
  order_type      VARCHAR(10)        -> STRING(10)
  side            CHAR(1)            -> STRING(1)
  quantity        NUMERIC(18,4)      -> NUMERIC
  price           MONEY              -> NUMERIC (custom mapping)
  order_date      DATETIME           -> TIMESTAMP
  status          VARCHAR(20)        -> STRING(20)
  created_by      VARCHAR(50)        -> STRING(50)
  created_at      DATETIME           -> TIMESTAMP
  updated_at      DATETIME           -> TIMESTAMP

Indexes:
  PK: order_id (clustered)
  IX1: account_id, order_date (non-clustered)
  IX2: instrument_id, order_date (non-clustered)
  IX3: status, order_date (non-clustered)

Access Pattern: HIGH read+write, point lookups + range scans by account
Transaction Scope: Part of trade booking transaction (orders->fills->allocations)
Classification: OLTP -> Cloud Spanner
Replication: Active subscription to DR site
```

### Step 2: Primary Key Design

Replace all Sybase IDENTITY columns and monotonically increasing keys with Spanner-safe key strategies that prevent hotspotting.

**Key strategy decision matrix:**

| Sybase Key Pattern | Spanner Strategy | When to Use |
|-------------------|-----------------|-------------|
| INT IDENTITY | BIT_REVERSED_POSITIVE sequence | Most tables, preserves uniqueness |
| BIGINT IDENTITY | BIT_REVERSED_POSITIVE sequence | High-volume tables |
| Composite natural key | Preserve as composite PK | When natural key access is primary pattern |
| UUID/GUID | Generate UUIDv4 (STRING(36)) | Globally unique, distributed generation |
| Timestamp-based key | Hash-prefix + timestamp composite | Time-series data (avoid hotspot) |
| NUMERIC sequence | BIT_REVERSED_POSITIVE sequence | Financial identifiers |

**BIT_REVERSED_POSITIVE sequence generation:**

```sql
-- Spanner DDL: Create bit-reversed sequence
CREATE SEQUENCE seq_order_id
  OPTIONS (
    sequence_kind = 'bit_reversed_positive',
    start_with_counter = 1,
    skip_range_min = 1,
    skip_range_max = 1000  -- Reserve range for migration backfill
  );

-- Usage in table definition
CREATE TABLE orders (
  order_id INT64 DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE seq_order_id)),
  -- ...
) PRIMARY KEY (order_id);
```

**Timestamp-based key anti-hotspot pattern:**

```sql
-- ANTI-PATTERN: Monotonic timestamp key (creates hotspot)
-- CREATE TABLE market_data (
--   price_timestamp TIMESTAMP,
--   instrument_id INT64,
--   ...
-- ) PRIMARY KEY (price_timestamp);

-- CORRECT: Hash-prefix or reversed composite key
CREATE TABLE market_data (
  instrument_id INT64,
  price_timestamp TIMESTAMP,
  price NUMERIC,
  volume NUMERIC,
) PRIMARY KEY (instrument_id, price_timestamp);
-- Access pattern: range scan by instrument within time window
```

**Key migration mapping table:**

| Source Table | Sybase Key | Spanner Key | Strategy | Sequence Name |
|-------------|-----------|-------------|----------|--------------|
| orders | order_id IDENTITY | order_id INT64 | BIT_REVERSED_POSITIVE | seq_order_id |
| trades | trade_id IDENTITY | trade_id INT64 | BIT_REVERSED_POSITIVE | seq_trade_id |
| accounts | account_id IDENTITY | account_id INT64 | BIT_REVERSED_POSITIVE | seq_account_id |
| market_data | (timestamp, instr) | (instrument_id, timestamp) | Reorder composite | N/A |
| audit_trail | audit_id IDENTITY | audit_id INT64 | BIT_REVERSED_POSITIVE | seq_audit_id |

### Step 3: Interleaved Table Design

Identify parent-child hierarchies from FK relationships and access patterns to design Spanner interleaved tables for data co-location.

**Interleaving candidate detection:**

```
FOR EACH foreign_key FK in source_schema:
  parent = FK.referenced_table
  child = FK.referencing_table

  interleave_score = 0

  -- Co-access pattern (from performance profiler)
  IF frequently_joined(parent, child): interleave_score += 3
  IF same_transaction_scope(parent, child): interleave_score += 3

  -- Cardinality pattern
  IF one_to_many(parent, child): interleave_score += 2
  IF child_pk_starts_with_parent_pk: interleave_score += 2

  -- Access locality
  IF child_always_accessed_with_parent: interleave_score += 3

  IF interleave_score >= 7:
    RECOMMEND interleave(child, parent)
```

**Financial domain interleaving patterns:**

| Pattern | Parent | Child(ren) | Max Depth | Cascade Rule |
|---------|--------|-----------|-----------|-------------|
| Trade lifecycle | orders | fills, allocations, settlements | 4 | NO ACTION |
| Account hierarchy | entities | accounts, sub_accounts | 3 | NO ACTION |
| Position keeping | portfolios | positions | 2 | NO ACTION |
| Instrument master | instruments | prices, ratings, identifiers | 3 | NO ACTION |
| Audit trail | auditable_entity | audit_entries | 2 | NO ACTION |
| Customer KYC | customers | kyc_documents, addresses | 3 | NO ACTION |

**Interleaved DDL template:**

```sql
-- Parent table
CREATE TABLE accounts (
  account_id INT64 DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE seq_account_id)),
  entity_id INT64 NOT NULL,
  account_number STRING(20) NOT NULL,
  account_type STRING(10) NOT NULL,
  currency STRING(3) NOT NULL,
  status STRING(10) NOT NULL,
  opened_date DATE NOT NULL,
  created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
  updated_at TIMESTAMP OPTIONS (allow_commit_timestamp = true),
) PRIMARY KEY (account_id);

-- Child table (interleaved in parent)
CREATE TABLE transactions (
  account_id INT64 NOT NULL,
  transaction_id INT64 DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE seq_transaction_id)),
  transaction_date DATE NOT NULL,
  transaction_type STRING(10) NOT NULL,
  amount NUMERIC NOT NULL,
  currency STRING(3) NOT NULL,
  balance_after NUMERIC NOT NULL,
  description STRING(500),
  created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
) PRIMARY KEY (account_id, transaction_id),
  INTERLEAVE IN PARENT accounts ON DELETE NO ACTION;
```

**Interleaving constraints checklist:**

- Maximum 7 levels of interleaving depth
- Child PK must start with parent PK columns
- Interleaved tables are co-located on same splits
- ON DELETE CASCADE vs NO ACTION decision: use NO ACTION for financial data (never cascade-delete financial records)
- Consider row size limits: parent + all interleaved children should fit within split size guidelines
- Interleaving is not the same as foreign keys -- can have both

### Step 4: Secondary Index Design

Convert Sybase non-clustered indexes to Spanner secondary indexes with STORING clauses, NULL_FILTERED options, and interleaved index optimizations.

**Index conversion rules:**

| Sybase Index Feature | Spanner Equivalent | Notes |
|---------------------|-------------------|-------|
| Non-clustered index | CREATE INDEX | Standard conversion |
| Clustered index | PRIMARY KEY ordering | Spanner has no separate clustered index |
| Included columns | STORING clause | Cover queries without base table lookup |
| Filtered index (WHERE) | NULL_FILTERED (partial) | Spanner only supports NULL filtering |
| Unique index | CREATE UNIQUE INDEX | Direct mapping |
| Covering index | STORING (all SELECT columns) | Eliminate base table reads |
| Composite index | Multi-column index | Same column ordering strategy |

**STORING clause optimization (from performance profiler):**

```sql
-- Sybase: Non-clustered index with common query pattern
-- CREATE INDEX ix_orders_account ON orders (account_id, order_date)
-- Common query: SELECT order_id, status, quantity FROM orders
--               WHERE account_id = @acct AND order_date > @date

-- Spanner: Add STORING for covered query
CREATE INDEX ix_orders_account
ON orders (account_id, order_date DESC)
STORING (status, quantity, price, order_type);
-- Stores extra columns in index, avoids base table join
```

**NULL_FILTERED index for sparse columns:**

```sql
-- Only index non-NULL values (saves space for sparse columns)
CREATE NULL_FILTERED INDEX ix_orders_cancel_reason
ON orders (cancel_reason)
STORING (order_id, account_id, cancelled_at);
-- Most orders have NULL cancel_reason, index only cancelled orders
```

**Interleaved index for locality:**

```sql
-- Index interleaved in parent for co-located index scans
CREATE INDEX ix_transactions_date
ON transactions (account_id, transaction_date DESC)
STORING (amount, transaction_type, balance_after),
INTERLEAVE IN accounts;
-- Index entries co-located with parent account data
```

**Index design output table:**

| # | Source Index | Spanner Index | Type | STORING Columns | NULL_FILTERED | Interleaved In |
|---|------------|--------------|------|----------------|--------------|---------------|
| 1 | ix_orders_account | ix_orders_account | Standard | status, quantity, price | No | -- |
| 2 | ix_orders_status | ix_orders_status | Standard | order_id, account_id | No | -- |
| 3 | ix_txn_date | ix_transactions_date | Interleaved | amount, type, balance | No | accounts |
| 4 | ix_orders_cancel | ix_orders_cancel_reason | NULL_FILTERED | order_id, cancelled_at | Yes | -- |

### Step 5: Change Streams & Audit

Define Change Streams for tables requiring CDC and configure commit timestamp columns for audit trail tables.

**Change Stream definitions:**

```sql
-- Change Stream for position updates (CDC to BigQuery for analytics)
CREATE CHANGE STREAM cs_positions
FOR positions, position_history
OPTIONS (
  retention_period = '7d',
  value_capture_type = 'NEW_AND_OLD_VALUES'
);

-- Change Stream for trade lifecycle (CDC to downstream systems)
CREATE CHANGE STREAM cs_trade_lifecycle
FOR orders, fills, allocations, settlements
OPTIONS (
  retention_period = '3d',
  value_capture_type = 'NEW_VALUES'
);

-- Change Stream for audit compliance (CDC to compliance data lake)
CREATE CHANGE STREAM cs_audit_trail
FOR audit_entries
OPTIONS (
  retention_period = '7d',
  value_capture_type = 'NEW_AND_OLD_VALUES'
);
```

**Commit timestamp columns for audit:**

```sql
-- Add commit_timestamp to all auditable tables
ALTER TABLE orders ADD COLUMN
  spanner_commit_ts TIMESTAMP NOT NULL
  OPTIONS (allow_commit_timestamp = true);

ALTER TABLE trades ADD COLUMN
  spanner_commit_ts TIMESTAMP NOT NULL
  OPTIONS (allow_commit_timestamp = true);

-- Use PENDING_COMMIT_TIMESTAMP() in mutations
-- Java: Mutation.newInsertBuilder("orders")
--         .set("spanner_commit_ts").to(Value.COMMIT_TIMESTAMP)
--         .build();
```

**TTL policies for ephemeral data:**

```sql
-- TTL for session data (auto-delete after 24 hours)
CREATE TABLE user_sessions (
  session_id STRING(36) NOT NULL,
  user_id INT64 NOT NULL,
  created_at TIMESTAMP NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  session_data JSON,
) PRIMARY KEY (session_id),
ROW DELETION POLICY (OLDER_THAN(expires_at, INTERVAL 0 DAY));

-- TTL for temporary calculation results
CREATE TABLE temp_calculations (
  calc_id INT64 NOT NULL,
  calc_type STRING(50) NOT NULL,
  result JSON,
  created_at TIMESTAMP NOT NULL,
  ttl_timestamp TIMESTAMP NOT NULL,
) PRIMARY KEY (calc_id),
ROW DELETION POLICY (OLDER_THAN(ttl_timestamp, INTERVAL 0 DAY));
```

**Change Stream design considerations:**

| Factor | Recommendation |
|--------|---------------|
| Retention period | 3-7 days (enough for downstream processing recovery) |
| Value capture | NEW_AND_OLD_VALUES for audit tables, NEW_VALUES for CDC |
| Watched tables | Only tables with active replication or downstream consumers |
| Consumer scaling | One Dataflow pipeline per Change Stream |
| Ordering guarantee | Per-primary-key ordering within a Change Stream |

### Step 6: DDL Generation

Produce the complete Spanner DDL and migration script sequence with validation checkpoints.

**DDL generation order (dependency-aware):**

```sql
-- =====================================================
-- Phase 1: Sequences (no dependencies)
-- =====================================================
CREATE SEQUENCE seq_entity_id OPTIONS (sequence_kind = 'bit_reversed_positive');
CREATE SEQUENCE seq_account_id OPTIONS (sequence_kind = 'bit_reversed_positive');
CREATE SEQUENCE seq_order_id OPTIONS (sequence_kind = 'bit_reversed_positive');
CREATE SEQUENCE seq_trade_id OPTIONS (sequence_kind = 'bit_reversed_positive');
CREATE SEQUENCE seq_transaction_id OPTIONS (sequence_kind = 'bit_reversed_positive');
CREATE SEQUENCE seq_audit_id OPTIONS (sequence_kind = 'bit_reversed_positive');

-- =====================================================
-- Phase 2: Parent tables (no interleaving dependencies)
-- =====================================================
CREATE TABLE entities ( ... ) PRIMARY KEY (entity_id);
CREATE TABLE instruments ( ... ) PRIMARY KEY (instrument_id);
CREATE TABLE portfolios ( ... ) PRIMARY KEY (portfolio_id);
CREATE TABLE counterparties ( ... ) PRIMARY KEY (counterparty_id);

-- =====================================================
-- Phase 3: Level-1 interleaved tables
-- =====================================================
CREATE TABLE accounts ( ... ) PRIMARY KEY (entity_id, account_id),
  INTERLEAVE IN PARENT entities ON DELETE NO ACTION;
CREATE TABLE instrument_prices ( ... ) PRIMARY KEY (instrument_id, price_date),
  INTERLEAVE IN PARENT instruments ON DELETE NO ACTION;
CREATE TABLE positions ( ... ) PRIMARY KEY (portfolio_id, position_id),
  INTERLEAVE IN PARENT portfolios ON DELETE NO ACTION;

-- =====================================================
-- Phase 4: Level-2 interleaved tables
-- =====================================================
CREATE TABLE transactions ( ... ) PRIMARY KEY (entity_id, account_id, transaction_id),
  INTERLEAVE IN PARENT accounts ON DELETE NO ACTION;
CREATE TABLE orders ( ... ) PRIMARY KEY (entity_id, account_id, order_id),
  INTERLEAVE IN PARENT accounts ON DELETE NO ACTION;

-- =====================================================
-- Phase 5: Level-3 interleaved tables
-- =====================================================
CREATE TABLE fills ( ... ) PRIMARY KEY (entity_id, account_id, order_id, fill_id),
  INTERLEAVE IN PARENT orders ON DELETE NO ACTION;

-- =====================================================
-- Phase 6: Secondary indexes
-- =====================================================
CREATE INDEX ix_accounts_number ON accounts (account_number) STORING (account_type, status);
CREATE INDEX ix_orders_status ON orders (status, order_date DESC) STORING (account_id, quantity);
CREATE NULL_FILTERED INDEX ix_orders_cancel ON orders (cancel_reason) STORING (order_id);
CREATE INDEX ix_transactions_date ON transactions (account_id, transaction_date DESC)
  STORING (amount, transaction_type), INTERLEAVE IN accounts;

-- =====================================================
-- Phase 7: Change Streams
-- =====================================================
CREATE CHANGE STREAM cs_positions FOR positions, position_history
  OPTIONS (retention_period = '7d', value_capture_type = 'NEW_AND_OLD_VALUES');
CREATE CHANGE STREAM cs_trade_lifecycle FOR orders, fills
  OPTIONS (retention_period = '3d', value_capture_type = 'NEW_VALUES');

-- =====================================================
-- Phase 8: Foreign keys (after all tables created)
-- =====================================================
ALTER TABLE orders ADD CONSTRAINT fk_orders_instrument
  FOREIGN KEY (instrument_id) REFERENCES instruments (instrument_id);
ALTER TABLE positions ADD CONSTRAINT fk_positions_instrument
  FOREIGN KEY (instrument_id) REFERENCES instruments (instrument_id);
```

**Harbourbridge / DMS configuration snippet:**

```yaml
# Harbourbridge session config for Sybase-to-Spanner
source:
  type: sybase
  host: ${SYBASE_HOST}
  port: 5000
  database: ${SYBASE_DB}
  user: ${SYBASE_USER}
  password: ${SYBASE_PASSWORD}

target:
  type: spanner
  project: ${GCP_PROJECT}
  instance: ${SPANNER_INSTANCE}
  database: ${SPANNER_DATABASE}

schema_mapping:
  # Key transformations
  identity_columns:
    strategy: bit_reversed_positive_sequence
  # Type mappings
  type_overrides:
    MONEY: NUMERIC
    SMALLMONEY: NUMERIC
    DATETIME: TIMESTAMP
    SMALLDATETIME: TIMESTAMP
    IMAGE: BYTES(MAX)
    TEXT: STRING(MAX)
    UNITEXT: STRING(MAX)
    CHAR: STRING
    VARCHAR: STRING
    NCHAR: STRING
    NVARCHAR: STRING
    BINARY: BYTES
    VARBINARY: BYTES
    BIT: BOOL
    TINYINT: INT64
    SMALLINT: INT64
    INT: INT64
    BIGINT: INT64
    REAL: FLOAT64
    FLOAT: FLOAT64
    NUMERIC: NUMERIC
    DECIMAL: NUMERIC
    DATE: DATE
    TIME: STRING(15)
```

**Data validation checkpoints:**

| Checkpoint | Validation | Query |
|-----------|-----------|-------|
| Row counts | Source vs target row count per table | `SELECT COUNT(*) FROM table` |
| Checksum | Hash comparison of key + amount columns | MD5 hash of sorted result set |
| Referential integrity | All FK references resolve | JOIN validation queries |
| Sequence continuity | No gaps in migrated sequences | MIN/MAX/COUNT checks |
| Null counts | NULL column counts match | `COUNT(*) WHERE col IS NULL` |
| Financial totals | Aggregate amounts match | `SUM(amount) GROUP BY date` |

## Markdown Report Output

After completing the analysis, generate a structured markdown report saved to `./reports/sybase-to-spanner-schema-designer-<YYYYMMDDTHHMMSS>.md`.

The report follows this structure:

```
# Sybase-to-Spanner Schema Designer Report

**Subject:** [Short descriptive title, e.g., "Cloud Spanner Target Schema Design for Trading Platform"]
**Status:** [Draft | In Progress | Complete | Requires Review]
**Date:** [YYYY-MM-DD]
**Author:** [Gemini CLI / User]
**Topic:** [One-sentence summary of schema design scope]

---

## 1. Analysis Summary
### Scope
- Number of source tables converted
- Number of Spanner tables generated (including interleaved)
- Number of sequences created
- Number of secondary indexes designed
- Number of Change Streams defined

### Key Findings
- Interleaved table hierarchies designed (count and max depth)
- IDENTITY columns replaced with bit-reversed sequences
- Hotspot risks mitigated (key design changes)
- Change Streams configured for CDC requirements

## 2. Detailed Analysis
### Primary Finding
- Key schema design decisions and rationale
### Technical Deep Dive
- Interleaved table hierarchy diagrams
- Primary key transformation details
- Index optimization analysis
- Change Stream coverage
### Historical Context
- Source Sybase schema characteristics
- Access pattern data informing design
### Contributing Factors
- Financial domain requirements driving design decisions
- Performance profiler data influencing index design

## 3. Impact Analysis
| Area | Impact | Severity | Details |
|------|--------|----------|---------|
| Key design | Hotspot prevention | HIGH | All IDENTITY replaced with bit-reversed |
| Interleaving | Data locality | HIGH | [N] hierarchies, max depth [D] |
| Index design | Query performance | MEDIUM | [N] indexes with STORING clauses |
| Change Streams | CDC coverage | MEDIUM | [N] streams covering [M] tables |

## 4. Affected Components
- Complete table-by-table conversion mapping
- Sequence definitions
- Index definitions with STORING details
- Change Stream definitions
- Foreign key constraints

## 5. Reference Material
- Sybase-to-Spanner type mapping table
- Interleaving decision rationale per hierarchy
- Index design rationale per table
- Harbourbridge configuration

## 6. Recommendations
### Option A (Recommended)
- Full interleaved design with bit-reversed sequences
- Change Streams for all replicated tables
### Option B
- Flat table design with foreign keys only (simpler but less performant)
- Application-level CDC instead of Change Streams

## 7. Dependencies & Prerequisites
- Phase 1 skill outputs (schema profiler, performance profiler, transaction analyzer)
- Phase 3 skill outputs (analytics assessor for OLTP scope, dead component detector)
- Spanner instance provisioned with sufficient nodes
- Harbourbridge or DMS configured

## 8. Verification Criteria
- No monotonic primary keys (hotspot risk)
- Interleaving depth <= 7 levels
- All financial tables have commit_timestamp columns
- Change Streams cover all replication requirements
- DDL executes without errors on target instance
- Data validation checkpoints pass after migration
```

## HTML Report Output

After generating the schema design, **CRITICAL:** Do NOT generate the HTML report in the same turn as the Markdown analysis to avoid context exhaustion. Only generate the HTML if explicitly requested in a separate turn. When requested, render the results as a self-contained HTML page using the `visual-explainer` skill. The HTML report should include:

- **Dashboard header** with KPI cards: source tables, target tables, sequences, indexes, Change Streams, interleaving max depth
- **Schema conversion table** as an interactive HTML table mapping each source table to its Spanner target with key strategy, interleaving parent, and index count
- **Interleaved hierarchy diagram** (tree visualization) showing parent-child table relationships with depth levels color-coded
- **Type mapping summary** (Chart.js bar) showing count of each Sybase-to-Spanner type conversion
- **Key design summary** showing IDENTITY-to-sequence mappings with hotspot risk indicators
- **DDL preview** with syntax-highlighted Spanner DDL grouped by creation phase
- **Data validation checklist** as an interactive checklist with pass/fail status per checkpoint

Write the HTML file to `./diagrams/sybase-to-spanner-schema-designer-report.html` and open it in the browser.

## Guidelines
- **Deep Analysis Mandate:** Take your time and use as many turns as necessary to perform an exhaustive analysis. Do not rush. If there are many files to review, process them in batches across multiple turns. Prioritize depth, accuracy, and thoroughness over speed.

- NEVER use monotonically increasing keys as Spanner primary keys (creates write hotspots)
- ALWAYS use BIT_REVERSED_POSITIVE sequences to replace Sybase IDENTITY columns
- ALWAYS add commit_timestamp columns to financial audit tables
- Design interleaved tables based on access patterns, not just FK relationships
- Maximum 7 levels of interleaving depth -- stay within 3-4 for most hierarchies
- Use ON DELETE NO ACTION for financial data -- never cascade-delete financial records
- Add STORING clauses based on actual query patterns from performance profiler
- Use NULL_FILTERED indexes for sparse columns to save storage
- Define Change Streams only for tables with active downstream consumers
- Set Change Stream retention to 3-7 days based on downstream processing SLA
- Generate DDL in dependency order (sequences -> parent tables -> children -> indexes -> Change Streams -> FKs)
- Include Harbourbridge/DMS configuration snippets for automated migration tooling
- Design data validation checkpoints for every table with financial amounts
- Consider Spanner Graph schema for complex entity relationship networks
- Map Sybase MONEY/SMALLMONEY to Spanner NUMERIC (not FLOAT64) to preserve precision
- Reserve sequence ranges (skip_range_min/max) for migration backfill of existing IDs
