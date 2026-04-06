# Data Lineage Patterns Reference

Comprehensive reference for cross-database reference resolution, proxy table tracing, ASE/IQ data flow patterns, batch chain detection heuristics, and financial data pipeline patterns.

## Cross-Database Reference Resolution

### Three-Part Naming Patterns

Sybase ASE uses `database.owner.object` naming to reference objects across databases within the same server.

**Standard patterns:**

```sql
-- Full three-part name
SELECT * FROM trading_db.dbo.orders

-- Shorthand (default owner)
SELECT * FROM trading_db..orders

-- In JOIN context
SELECT t.order_id, r.client_name
FROM trading_db..orders t
JOIN reference_db..clients r ON t.client_id = r.client_id

-- In INSERT...SELECT
INSERT INTO reporting_db..daily_trades
SELECT * FROM trading_db..trades WHERE trade_date = @today

-- In stored procedure parameters
EXEC trading_db..sp_get_positions @book_id = 'FX_SPOT'
```

**Four-part naming (remote servers):**

```sql
-- Remote server reference
SELECT * FROM REMOTE_ASE.trading_db.dbo.orders

-- Remote procedure call
EXEC REMOTE_ASE.trading_db.dbo.sp_get_positions @book_id = 'FX_SPOT'
```

### Dynamic SQL Reference Detection

Dynamic SQL hides cross-database references from static analysis. Common patterns:

```sql
-- Concatenated database name
DECLARE @sql VARCHAR(2000)
SELECT @sql = 'SELECT * FROM ' + @target_db + '..orders WHERE status = ''OPEN'''
EXEC(@sql)

-- sp_executesql with database prefix
EXEC sp_executesql @stmt = N'SELECT * FROM trading_db..orders WHERE order_id = @id',
     @params = N'@id INT', @id = @order_id

-- USE statement switching
USE trading_db
SELECT * FROM orders  -- now references trading_db..orders
USE settlement_db
INSERT INTO settlements SELECT ...  -- now references settlement_db..settlements
```

**Detection heuristics for dynamic SQL:**

1. Search for string concatenation involving `..` (double dot) patterns
2. Search for variables named `@db`, `@database`, `@dbname`, `@target_db`
3. Search for `USE ` statements inside stored procedures (context switch)
4. Search for `sp_executesql` calls with hardcoded database prefixes

### Dependency Direction Classification

| Reference Pattern | Direction | Coupling |
|------------------|-----------|----------|
| `SELECT FROM remote_db..table` | Source → reads from remote | READ dependency |
| `INSERT INTO remote_db..table` | Source → writes to remote | WRITE dependency |
| `UPDATE remote_db..table` | Source → modifies remote | WRITE dependency |
| `DELETE FROM remote_db..table` | Source → modifies remote | WRITE dependency |
| `EXEC remote_db..sp_name` | Source → calls remote proc | EXECUTE dependency |
| `SELECT INTO remote_db..table` | Source → creates in remote | WRITE dependency |
| `TRUNCATE TABLE remote_db..table` | Source → clears remote | WRITE dependency |

---

## Proxy Table Tracing Methodology

### Identifying Proxy Tables

Proxy tables are created via CIS (Component Integration Services) and make remote data appear local.

**Creation syntax:**

```sql
-- Create proxy table pointing to Oracle
CREATE EXISTING TABLE ext_market_data (
    symbol VARCHAR(10),
    price DECIMAL(18,6),
    last_update DATETIME
) EXTERNAL TABLE AT 'MKT_ORACLE.marketdata.dbo.prices'

-- Create proxy table pointing to flat file
CREATE EXISTING TABLE ext_eod_file (
    record_type CHAR(2),
    data VARCHAR(500)
) EXTERNAL TABLE AT 'FILE_SERVER..."/data/feeds/eod_prices.csv"'
```

**System table queries for proxy detection:**

```sql
-- Method 1: sysattributes check
SELECT o.name, o.id
FROM sysobjects o
WHERE o.sysstat2 & 1024 = 1024  -- proxy table bit

-- Method 2: sp_help output
-- Look for "Object is a proxy table" in sp_help output

-- Method 3: Check external location
SELECT object_name(object), char_value
FROM sysattributes
WHERE class = 9  -- CIS external location class
AND attribute = 1
```

### Server Class Reference

| Server Class | Description | Connection Method |
|-------------|-------------|-------------------|
| SYB_ASE | Sybase ASE (same version) | Native TDS |
| SYB_ASE_OLDER | Sybase ASE (older version) | Native TDS with compatibility |
| SYB_IQ | Sybase IQ | Native TDS |
| SYB_ORACLE | Oracle Database | ODBC or Oracle OCI |
| SYB_DB2 | IBM DB2 | ODBC or DB2 CLI |
| SYB_MS | Microsoft SQL Server | Native TDS |
| SYB_FILE | Flat file access | DirectConnect File |
| SYB_ODBC | Generic ODBC source | ODBC driver |
| SYB_OMNI | Omni Server (deprecated) | DirectConnect |

### Federation Topology Mapping

For each proxy table, record:

1. **Local context**: database, schema, table name, column definitions
2. **Remote context**: server name, server class, remote database, remote schema, remote table
3. **Access pattern**: read-only, read-write, frequency of access
4. **Data volume**: estimated rows flowing through proxy
5. **Latency sensitivity**: real-time lookup vs batch access

---

## ASE/IQ Data Flow Patterns

### Pattern 1: BCP Extract + IQ LOAD

The most common pattern for bulk data movement from ASE to IQ.

```bash
# Step 1: BCP extract from ASE
bcp trading_db..trades out /data/extract/trades_${DATE}.dat \
    -S ASE_PROD -U sa -P*** -c -t"|" -r"\n"

# Step 2: IQ LOAD TABLE
LOAD TABLE fact_trades (
    trade_id, trade_date, symbol, quantity, price, counterparty
)
FROM '/data/extract/trades_${DATE}.dat'
DELIMITED BY '|'
ROW DELIMITED BY '\n'
WITH CHECKPOINT ON
```

### Pattern 2: INSERT...LOCATION (Direct ASE-to-IQ)

IQ can directly query ASE using the LOCATION syntax:

```sql
-- Direct insert from ASE to IQ
INSERT INTO iq_db..fact_trades
SELECT trade_id, trade_date, symbol, quantity, price
FROM ASE_PROD.trading_db.dbo.trades AT 'ASE_PROD'
WHERE trade_date = CURRENT DATE

-- Using LOCATION clause
INSERT INTO fact_trades
LOCATION 'ASE_PROD.trading_db' {
    SELECT * FROM trades WHERE trade_date = CURRENT DATE
}
```

### Pattern 3: Replication Server Pipeline

Sybase Replication Server provides near-real-time data movement:

```
ASE Primary DB (trading_db)
    ↓ Transaction log
Replication Server
    ↓ Replicated transactions
IQ Multiplex Writer (analytics_iq)
    ↓ Applied as INSERT/UPDATE/DELETE
IQ fact tables (queryable by readers)
```

**Detection indicators:**
- `rs_config` system tables
- Replication definitions (`create replication definition`)
- Subscription definitions (`create subscription`)
- `rs_lastcommit` table in replicated databases

### Pattern 4: Scheduled Extract Jobs

```sql
-- Stored procedure called by scheduler
CREATE PROCEDURE sp_extract_trades_to_iq
AS
BEGIN
    -- Extract delta since last run
    SELECT * INTO #delta_trades
    FROM trades
    WHERE modified_date > (SELECT last_extract FROM etl_control WHERE job_name = 'TRADE_EXTRACT')

    -- BCP out
    EXEC xp_cmdshell 'bcp "SELECT * FROM tempdb..#delta_trades" queryout /data/iq_load/trades_delta.dat -c -t"|"'

    -- Update control table
    UPDATE etl_control SET last_extract = GETDATE() WHERE job_name = 'TRADE_EXTRACT'
END
```

---

## Batch Chain Detection Heuristics

### Job Dependency Detection

**SQL Agent job chains:**

```sql
-- Detect job step dependencies
SELECT j.name AS job_name,
       js.step_id,
       js.step_name,
       js.database_name,
       js.command,
       js.on_success_action,  -- 3 = Go to step, 4 = Go to next step
       js.on_success_step_id
FROM msdb..sysjobs j
JOIN msdb..sysjobsteps js ON j.job_id = js.job_id
ORDER BY j.name, js.step_id
```

**Crontab chain detection heuristics:**

1. Jobs writing a flag file that another job checks for
2. Jobs with sequential timestamps (Job A at 18:00, Job B at 18:30)
3. Jobs using `touch /tmp/job_a_complete` + `while [ ! -f /tmp/job_a_complete ]`
4. Jobs calling `sendevent` (Autosys) or setting conditions (Control-M)

### Table-Level Data Flow Tracing

For each stored procedure or batch script:

1. Parse all `SELECT FROM` references → mark as READ
2. Parse all `INSERT INTO`, `UPDATE`, `DELETE FROM` references → mark as WRITE
3. Parse all `SELECT INTO` and `CREATE TABLE` → mark as CREATE
4. Parse all `TRUNCATE TABLE` and `DROP TABLE` → mark as DESTROY
5. Build read-set and write-set for each job step
6. Chain: Job B reads what Job A writes → Job B depends on Job A

---

## Financial Data Pipeline Patterns

### Trade Lifecycle Flow

```
[Order Entry]
    ↓ INSERT trading_db..orders
[Order Matching/Fill]
    ↓ UPDATE trading_db..orders SET status='FILLED'
    ↓ INSERT trading_db..fills
[Position Update]
    ↓ UPDATE position_db..positions (read-modify-write)
[P&L Calculation]
    ↓ INSERT pnl_db..realized_pnl
    ↓ UPDATE pnl_db..unrealized_pnl
[Settlement Instruction]
    ↓ INSERT settlement_db..instructions
[Confirmation]
    ↓ INSERT settlement_db..confirmations
[Accounting Entry]
    ↓ INSERT accounting_db..gl_entries
[Regulatory Reporting]
    ↓ INSERT regulatory_db..trade_reports
```

**Databases in trade lifecycle (typical):**

| Database | Role | Access Pattern | Migration Priority |
|----------|------|---------------|-------------------|
| trading_db | Order management | Write-heavy, low latency | Wave 2 (after reference data) |
| position_db | Position keeping | Read-modify-write | Wave 2 (co-migrate with trading) |
| pnl_db | Profit & Loss | Write on trade, read on demand | Wave 3 |
| settlement_db | Settlement processing | Batch-heavy, EOD critical | Wave 3 |
| accounting_db | General ledger | Write-heavy during EOD | Wave 3 |
| regulatory_db | Regulatory reports | Read-heavy, batch generation | Wave 4 |
| reference_db | Static/reference data | Read-heavy, rarely written | Wave 1 (foundation) |

### Settlement Flow

```
[Trade Matching]  ← trading_db..fills
    ↓
[Netting]         ← settlement_db..matched_trades
    ↓               Aggregate by counterparty, currency, value date
[SWIFT Generation] ← settlement_db..net_positions → swift_db..mt5xx_messages
    ↓
[Nostro Reconciliation] ← accounting_db..nostro_balances
    ↓
[Fails Management]  ← settlement_db..failed_settlements
    ↓                  Retry logic, partial settlement
[Balance Update]    ← accounting_db..gl_entries
```

### Regulatory Reporting Flow

```
[Position Snapshot]  ← position_db..positions (point-in-time)
    ↓
[Risk Calculation]   ← Apply risk weights from reference_db..risk_params
    ↓
[Capital Ratio]      ← regulatory_db..capital_calculations
    ↓
[Report Generation]  ← regulatory_db..report_templates → XML/XBRL
    ↓
[Submission]         ← External: regulator portal / SFTP
    ↓
[Audit Trail]        ← audit_db..submission_log
```

**Critical timing constraints:**

| Report | Regulator | Deadline | Data Source Databases |
|--------|-----------|----------|---------------------|
| CCAR/DFAST | Federal Reserve | T+14 business days | trading, position, risk, reference |
| LCR/NSFR | OCC/Fed | Daily by 07:00 | treasury, funding, position |
| Trade Reporting | DTCC/EMIR | T+1 by 18:00 | trading, reference |
| Large Exposure | Fed/PRA | Daily by 09:00 | position, reference, client |
| MiFID II (RTS 25) | ESMA/FCA | T+1 by end of day | trading, reference, client |

---

## Migration Ordering Algorithm

### Step 1: Build Adjacency List

For each database, collect all dependencies:

```
trading_db:
  reads_from: [reference_db, market_data_db]
  writes_to: [position_db, audit_db]
  proxy_to: [MKT_ORACLE.marketdata]
  batch_chain: [EOD_SETTLEMENT(step 1)]

settlement_db:
  reads_from: [trading_db, reference_db]
  writes_to: [accounting_db, swift_db]
  batch_chain: [EOD_SETTLEMENT(steps 2-5)]
```

### Step 2: Detect Cycles

If database A depends on B and B depends on A, they form a cycle and must co-migrate. Use Tarjan's algorithm to find strongly connected components.

### Step 3: Topological Sort

Sort the DAG (with cycles collapsed into single nodes) to determine migration wave ordering. Databases with no inbound edges go first (Wave 1).

### Step 4: Wave Assignment

Apply constraints:
- Co-migration groups stay in the same wave
- SLA-critical batch chains prefer the same wave or consecutive waves
- Data volume constraints limit wave size
- Team capacity constrains parallel migrations

### Step 5: Validation

- Every database is assigned to exactly one wave
- No wave depends on a later wave
- Batch chain SLAs are achievable with the wave plan
- Proxy table replacement strategies are defined for each wave boundary
