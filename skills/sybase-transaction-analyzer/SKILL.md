---
name: sybase-transaction-analyzer
description: "Analyze Sybase transaction patterns, isolation levels, locking behavior, and distributed transaction usage to design Spanner-compatible transaction strategies that maintain financial data consistency guarantees. Use when the user mentions analyzing Sybase transactions, mapping transaction patterns to Spanner, assessing lock contention, or designing Spanner transaction strategies."
---

# Sybase Transaction Analyzer

You are a transaction architecture specialist analyzing Sybase transaction semantics for Cloud Spanner migration. You catalog transaction patterns, isolation levels, locking hints, and distributed transaction usage across stored procedures and application code. You map each pattern to its Spanner equivalent, flagging behavioral differences that could impact financial data consistency. You consume sybase-tsql-analyzer output when available and produce transaction strategy recommendations for Phase 3 schema design.

## Activation

When user asks to analyze Sybase transaction patterns, map transaction semantics to Spanner, assess locking behavior for migration, design Spanner transaction strategies, evaluate distributed transaction usage, or review isolation level compatibility.

## Workflow

### Step 1: Transaction Pattern Discovery

Parse stored procedures and T-SQL scripts for transaction management patterns. Sybase ASE supports both chained and unchained transaction modes, named transactions, savepoints, and nested transaction tracking.

**Transaction pattern detection:**

| Pattern | T-SQL Syntax | Detection Regex |
|---------|-------------|-----------------|
| Explicit begin | `BEGIN TRAN [name]` | `BEGIN\s+TRAN(SACTION)?\s*(\w+)?` |
| Commit | `COMMIT TRAN [name]` | `COMMIT\s+(TRAN(SACTION)?\s*(\w+)?)?` |
| Rollback | `ROLLBACK TRAN [name]` | `ROLLBACK\s+(TRAN(SACTION)?\s*(\w+)?)?` |
| Savepoint | `SAVE TRAN name` | `SAVE\s+TRAN(SACTION)?\s+(\w+)` |
| Nesting check | `@@trancount` | `@@trancount` |
| Chained mode | `SET CHAINED ON/OFF` | `SET\s+CHAINED\s+(ON|OFF)` |
| Proc mode | `sp_procxmode proc_name, 'chained'` | `sp_procxmode\s+` |

**Transaction catalog entry:**

For each stored procedure, record:

```
Procedure: sp_book_trade
Database: trading_db
Transaction Mode: unchained (explicit BEGIN TRAN)
Transaction Name: trade_booking
Nesting Level: 1 (no nested transactions)
Savepoints: save_after_order, save_after_position
Tables Modified:
  - trading_db..orders (INSERT)
  - trading_db..fills (INSERT)
  - position_db..positions (UPDATE)
  - audit_db..audit_trail (INSERT)
Cross-Database: YES (3 databases in single transaction)
Error Handling: @@error check after each DML, ROLLBACK on error
Estimated Duration: < 100ms (OLTP)
```

**Chained vs unchained mode analysis:**

| Mode | Behavior | Sybase Setting | Spanner Equivalent |
|------|----------|---------------|-------------------|
| Unchained (default ASE) | Explicit BEGIN TRAN required | `SET CHAINED OFF` | Explicit `ReadWriteTransaction` |
| Chained (ANSI) | Auto-begin on first DML | `SET CHAINED ON` | Spanner default (auto-commit per statement) |
| Mixed | Different modes per procedure | `sp_procxmode` per proc | Must standardize |

**Procedure mode inventory:**

```sql
-- Discover procedure transaction modes
SELECT o.name AS proc_name,
       CASE WHEN o.sysstat2 & 4096 = 4096 THEN 'chained'
            WHEN o.sysstat2 & 8192 = 8192 THEN 'unchained'
            ELSE 'anymode'
       END AS txn_mode
FROM sysobjects o
WHERE o.type = 'P'
ORDER BY o.name
```

Consume sybase-tsql-analyzer output from `./reports/` if available to accelerate procedure catalog building.

### Step 2: Isolation Level Analysis

Map Sybase ASE isolation levels to Spanner's external consistency model. Spanner always provides serializable isolation, which is stronger than most Sybase configurations.

**Sybase isolation level inventory:**

| Sybase Level | Sybase Name | Behavior | Spanner Mapping | Migration Risk |
|-------------|-------------|----------|----------------|----------------|
| 0 | Read uncommitted | Dirty reads allowed | No equivalent (Spanner is always serializable) | HIGH - behavior change |
| 1 | Read committed (default) | No dirty reads, non-repeatable reads possible | Spanner default provides stronger guarantee | LOW - Spanner is stricter |
| 2 | Repeatable read | Phantom reads possible | Spanner default provides stronger guarantee | LOW - Spanner is stricter |
| 3 | Serializable | Full isolation | Spanner default | NONE - exact match |

**Detection patterns:**

```sql
-- Session-level setting
SET TRANSACTION ISOLATION LEVEL 0
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

-- Query-level hint
SELECT * FROM trades (ISOLATION READ UNCOMMITTED)
SELECT * FROM trades AT ISOLATION 0

-- Check current level
SELECT @@isolation
```

**Level 0 (dirty reads) risk assessment:**

Procedures using isolation level 0 intentionally accept dirty reads for performance. On Spanner, these will get serializable reads, which means:
- **Read latency may increase** (Spanner waits for committed data)
- **Contention may increase** (readers now conflict with writers)
- **Application behavior may change** (previously saw in-flight data)

| Level 0 Usage Pattern | Financial Context | Migration Strategy |
|----------------------|-------------------|-------------------|
| Dashboard/monitoring queries | Real-time position display | Use Spanner stale reads (10-15s staleness) |
| Approximate counts | "How many orders today?" | Use Spanner stale reads |
| Lock-free reporting | Intraday P&L approximation | Use Spanner read-only transactions |
| Queue polling | Check for new messages | Use Spanner stale reads with short staleness |

**Isolation level upgrade impact scoring:**

| Current Level | Spanner Level | Performance Impact | Correctness Impact | Score |
|--------------|---------------|-------------------|-------------------|-------|
| 0 → Serializable | HIGH | Possible latency increase | Improved (no dirty reads) | 8/10 |
| 1 → Serializable | LOW | Minimal | Improved (repeatable reads) | 3/10 |
| 2 → Serializable | NONE | None | Improved (no phantoms) | 1/10 |
| 3 → Serializable | NONE | None | Identical | 0/10 |

### Step 3: Locking Behavior Analysis

Catalog explicit locking directives in T-SQL code. Sybase uses pessimistic locking; Spanner uses optimistic concurrency with automatic retry.

**Lock hint inventory:**

| Sybase Lock Hint | Behavior | Spanner Alternative | Conversion Complexity |
|-----------------|----------|--------------------|-----------------------|
| `HOLDLOCK` | Hold shared lock until COMMIT | Spanner read-write transaction (implicit) | LOW |
| `NOHOLDLOCK` | Release lock after read | Spanner stale read or read-only transaction | LOW |
| `READPAST` | Skip locked rows | No direct equivalent; use application-level queue | HIGH |
| `UPDLOCK` | Upgrade to update lock | Not needed (Spanner handles internally) | REMOVE |
| `EXCLUSIVE LOCK` | Full exclusive lock | Not needed (Spanner serializable) | REMOVE |
| `SHARED LOCK` | Explicit shared lock | Not needed | REMOVE |
| `DATAROWS` | Row-level locking | Spanner default (row-level) | REMOVE |
| `DATAPAGES` | Page-level locking | No equivalent, not needed | REMOVE |
| `ALLPAGES` | All-pages locking (legacy) | No equivalent, not needed | REMOVE |

**LOCK TABLE detection:**

```sql
-- Explicit table lock
LOCK TABLE trading_db..orders IN EXCLUSIVE MODE

-- Lock with wait
LOCK TABLE orders IN SHARE MODE WAIT 30
```

**Deadlock retry logic detection:**

Search for patterns indicating application-managed deadlock handling:

```sql
-- Common Sybase deadlock retry pattern
DECLARE @retry INT = 0
WHILE @retry < 3
BEGIN
    BEGIN TRAN
    BEGIN TRY
        -- DML operations
        UPDATE positions SET quantity = quantity + @delta WHERE book_id = @book
        COMMIT TRAN
        BREAK  -- success, exit retry loop
    END TRY
    BEGIN CATCH
        ROLLBACK TRAN
        IF @@error = 1205  -- deadlock victim
        BEGIN
            SET @retry = @retry + 1
            WAITFOR DELAY '00:00:01'  -- backoff
            CONTINUE
        END
        ELSE
            RAISERROR('Non-deadlock error', 16, 1)
    END CATCH
END
```

**Spanner retry mapping:**

| Sybase Pattern | Spanner Equivalent |
|---------------|-------------------|
| `@@error = 1205` deadlock retry | Client library automatic retry (ABORTED status) |
| `WAITFOR DELAY` backoff | Exponential backoff built into client libraries |
| Application retry loop | `RunInTransaction` / `runInTransaction` handles retry |
| `LOCK TABLE ... WAIT n` | Spanner lock timeout via deadline/context |

**Long-running transaction detection:**

Flag transactions that hold locks for extended periods. These are problematic for Spanner's 10-second recommendation and 4-hour hard limit.

| Pattern | Duration Risk | Spanner Strategy |
|---------|-------------|-----------------|
| Batch UPDATE within single TRAN | HIGH (minutes) | Partitioned DML |
| Cursor-based processing in TRAN | HIGH (minutes) | Batch processing with checkpoints |
| Interactive transaction (user input) | CRITICAL (unbounded) | Redesign to separate read and write phases |
| Report generation in TRAN | MEDIUM (seconds) | Read-only transaction |

### Step 4: Distributed Transaction Assessment

Identify cross-database and cross-server transactions that require special handling for Spanner migration.

**Cross-database transaction patterns:**

```sql
-- Pattern 1: Multi-database atomic operation
BEGIN TRAN trade_booking
    INSERT INTO trading_db..orders (order_id, ...) VALUES (@order_id, ...)
    INSERT INTO position_db..positions (book_id, ...) VALUES (@book_id, ...)
    INSERT INTO audit_db..audit_trail (event, ...) VALUES ('TRADE_BOOKED', ...)
COMMIT TRAN trade_booking
-- All three databases participate in same transaction
```

```sql
-- Pattern 2: Remote procedure call within transaction
BEGIN TRAN
    EXEC trading_db..sp_insert_order @params
    EXEC position_db..sp_update_position @params
    EXEC settlement_db..sp_create_instruction @params
COMMIT TRAN
```

**XA/DTC distributed transaction detection:**

| Indicator | Detection Method |
|-----------|-----------------|
| XA transactions | `xa_start`, `xa_end`, `xa_prepare`, `xa_commit` calls |
| DTC enrollment | Application server config (WebSphere, WebLogic) |
| Two-phase commit | `sp_start_xact`, `sp_commit_xact` system procedures |
| Transaction coordinator | `sysattributes` with DTM service entries |
| CIS remote transactions | Proxy table updates within local transactions |

**Financial distributed transaction catalog:**

| Transaction Type | Databases Involved | Atomicity Requirement | Spanner Strategy |
|-----------------|-------------------|----------------------|-----------------|
| Trade booking | trading, position, audit | MUST be atomic | Single Spanner DB (merge schemas) |
| Settlement | settlement, accounting, swift | MUST be atomic | Single Spanner DB or saga |
| EOD batch | All databases | Checkpoint/restart OK | Partitioned DML with control table |
| Regulatory snapshot | position, reference, regulatory | Read consistency only | Read-only transaction at timestamp |
| Client onboarding | client, compliance, reference | Saga acceptable | Cloud Workflows saga |
| Margin call | margin, position, treasury | MUST be atomic | Single Spanner DB |

**Spanner database consolidation analysis:**

If multiple Sybase databases participate in atomic transactions, they may need to be consolidated into a single Spanner database (Spanner transactions cannot span databases).

```
Consolidation candidates (shared atomic transactions):
  Group 1: trading_db + position_db + audit_db → spanner-trading
  Group 2: settlement_db + accounting_db → spanner-settlement
  Group 3: reference_db (standalone) → spanner-reference
  Group 4: regulatory_db + reporting_db → spanner-reporting (saga OK)
```

### Step 5: Spanner Transaction Strategy

For each discovered transaction pattern, recommend the appropriate Spanner transaction type with code examples.

**Transaction type recommendation matrix:**

| Sybase Pattern | Read/Write Ratio | Duration | Spanner Recommendation | Priority |
|---------------|-----------------|----------|----------------------|----------|
| OLTP read-modify-write | Balanced | < 100ms | `ReadWriteTransaction` | P0 |
| Point read + return | Read-only | < 10ms | `ReadOnlyTransaction` (strong) | P0 |
| Historical query | Read-only | < 1s | `ReadOnlyTransaction` (stale) | P1 |
| Batch update (1000+ rows) | Write-heavy | > 1s | `PartitionedDML` | P1 |
| Dashboard/monitoring | Read-only | < 100ms | Stale read (15s staleness) | P2 |
| Audit trail insert | Write-only | < 10ms | `ReadWriteTransaction` with commit timestamp | P0 |
| Bulk data load | Write-only | Minutes | Batch mutations (max 20K mutations) | P1 |

**Spanner transaction code patterns:**

```python
# Pattern 1: Read-Write Transaction (trade booking)
def book_trade(transaction, order):
    # Read current position
    position = transaction.read('positions',
        columns=['book_id', 'quantity'],
        keyset=spanner.KeySet(keys=[[order['book_id']]]))

    # Modify position
    new_qty = position['quantity'] + order['quantity']

    # Write atomically
    transaction.batch_update([
        spanner.Statement("INSERT INTO orders ...", params=order),
        spanner.Statement("UPDATE positions SET quantity = @qty WHERE book_id = @book",
                         params={'qty': new_qty, 'book': order['book_id']}),
        spanner.Statement("INSERT INTO audit_trail ...", params=audit_entry)
    ])

database.run_in_transaction(book_trade, order=order_data)
```

```python
# Pattern 2: Read-Only Transaction (position query)
with database.snapshot(multi_use=True) as snapshot:
    positions = snapshot.execute_sql(
        "SELECT book_id, SUM(quantity) FROM positions GROUP BY book_id")
    # No locks held, consistent snapshot, can be read from any replica
```

```python
# Pattern 3: Stale Read (dashboard/monitoring)
import datetime
staleness = datetime.timedelta(seconds=15)
with database.snapshot(exact_staleness=staleness) as snapshot:
    count = snapshot.execute_sql("SELECT COUNT(*) FROM orders WHERE status = 'OPEN'")
    # May read from nearest replica, reduced latency
```

```python
# Pattern 4: Partitioned DML (EOD batch update)
row_count = database.execute_partitioned_dml(
    "UPDATE positions SET eod_price = @price WHERE symbol = @symbol",
    params={'price': eod_price, 'symbol': symbol})
# Runs across multiple splits, no single-transaction limit
# NOT atomic - may partially complete
```

**Commit timestamp guidance for audit trails:**

```sql
-- Spanner DDL: Add commit timestamp column
ALTER TABLE audit_trail ADD COLUMN commit_ts TIMESTAMP NOT NULL
    OPTIONS (allow_commit_timestamp = true);

-- Insert with commit timestamp
INSERT INTO audit_trail (event_id, event_type, details, commit_ts)
VALUES (@id, 'TRADE_BOOKED', @details, PENDING_COMMIT_TIMESTAMP());
```

**Transaction timeout mapping:**

| Sybase Setting | Value | Spanner Equivalent |
|---------------|-------|-------------------|
| `SET LOCK WAIT n` | Seconds to wait for lock | Transaction deadline / context timeout |
| `@@lock_timeout` | Session lock timeout | Client library deadline |
| No timeout (wait forever) | Sybase default | Spanner 1-hour default, 4-hour max |

## Markdown Report Output

After completing the analysis, generate a structured markdown report saved to `./reports/sybase-transaction-analyzer-<YYYYMMDDTHHMMSS>.md`.

The report follows this structure:

```
# Sybase Transaction Analyzer Report

**Subject:** [Short descriptive title, e.g., "Transaction Pattern Analysis for Trading Platform Migration"]
**Status:** [Draft | In Progress | Complete | Requires Review]
**Date:** [YYYY-MM-DD]
**Author:** [Gemini CLI / User]
**Topic:** [One-sentence summary of transaction analysis scope]

---

## 1. Analysis Summary
### Scope
- Number of stored procedures analyzed
- Number of distinct transaction patterns cataloged
- Number of cross-database transactions identified
- Number of isolation level 0 usages found

### Key Findings
- Transaction patterns requiring redesign for Spanner
- Cross-database transactions requiring database consolidation
- Isolation level 0 usages requiring stale read conversion
- Deadlock retry patterns to replace with Spanner client retry

## 2. Detailed Analysis
### Primary Finding
- Most critical transaction pattern for migration
### Technical Deep Dive
- Transaction mode distribution (chained vs unchained)
- Isolation level usage breakdown
- Lock hint inventory
- Distributed transaction map
### Historical Context
- Why transaction patterns evolved as they did
### Contributing Factors
- Sybase-specific features without direct Spanner equivalents

## 3. Impact Analysis
| Area | Impact | Severity | Details |
|------|--------|----------|---------|
| Isolation Level Changes | Level 0 → Serializable | HIGH | N procedures affected |
| Lock Hint Removal | READPAST has no equivalent | MEDIUM | N procedures affected |
| Cross-DB Transactions | Require DB consolidation | HIGH | N transaction groups |
| Long-Running Transactions | Exceed Spanner limits | CRITICAL | N procedures affected |

## 4. Affected Components
- List of all procedures with transaction patterns
- List of procedures requiring isolation level changes
- List of cross-database transaction groups
- List of long-running transactions requiring redesign

## 5. Reference Material
- Phase 1 outputs consumed
- Sybase isolation level documentation referenced
- Spanner transaction documentation referenced

## 6. Recommendations
### Option A (Recommended)
- Per-pattern Spanner transaction type mapping
### Option B
- Alternative approaches for complex patterns

## 7. Dependencies & Prerequisites
- Phase 1 T-SQL analysis should be complete
- Application transaction boundaries must be understood
- Spanner database consolidation plan needed for cross-DB transactions

## 8. Verification Criteria
- All transaction patterns mapped to Spanner equivalents
- No isolation level 0 usage without documented stale read strategy
- All cross-database transactions assigned to consolidation groups
- Retry logic conversion plan for every deadlock handler
```

## HTML Report Output

After generating the transaction analysis, **CRITICAL:** Do NOT generate the HTML report in the same turn as the Markdown analysis to avoid context exhaustion. Only generate the HTML if explicitly requested in a separate turn. When requested, render the results as a self-contained HTML page using the `visual-explainer` skill. The HTML report should include:

- **Dashboard header** with KPI cards: total procedures analyzed, transaction patterns found, cross-database transactions, isolation level 0 usages, distributed transactions, estimated conversion effort
- **Transaction pattern distribution** as a Chart.js pie/donut chart showing chained vs unchained, read-write vs read-only, and OLTP vs batch patterns
- **Isolation level heatmap** showing which procedures use which levels, with risk coloring (level 0 = red, level 1 = yellow, level 2-3 = green)
- **Lock hint inventory table** as an interactive HTML table with Sybase hint, count of occurrences, Spanner alternative, and conversion complexity badge
- **Cross-database transaction diagram** as a Mermaid flowchart showing which databases participate in shared transactions with consolidation group recommendations
- **Spanner transaction strategy table** mapping each Sybase pattern to its recommended Spanner transaction type with code snippets
- **Long-running transaction risk chart** showing transaction duration estimates vs Spanner limits (10s recommended, 4h max)

Write the HTML file to `./diagrams/sybase-transaction-analyzer-report.html` and open it in the browser.

## Guidelines
- **Deep Analysis Mandate:** Take your time and use as many turns as necessary to perform an exhaustive analysis. Do not rush. If there are many files to review, process them in batches across multiple turns. Prioritize depth, accuracy, and thoroughness over speed.

- Always consume Phase 1 sybase-tsql-analyzer output if available in `./reports/`
- Parse all stored procedure source (.sql, .prc, .sp files) for transaction patterns
- Never execute transactions or connect to live Sybase servers
- Flag any isolation level 0 usage as requiring explicit migration decision
- Flag any cross-database transaction as requiring consolidation analysis
- Flag any transaction lasting more than 10 seconds as requiring Spanner redesign
- Track both explicit transactions (BEGIN TRAN) and implicit (chained mode)
- Consider financial regulatory requirements for transaction atomicity (trade booking must be atomic)
- Map Sybase `@@error` checking to Spanner exception handling patterns
- Cross-reference with sybase-data-flow-mapper for cross-database dependency context
- Include Spanner client library code examples (Python, Java, Go) for each recommended pattern
- Document retry semantics differences: Sybase explicit retry vs Spanner automatic retry
