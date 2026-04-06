# Sybase ASE T-SQL Syntax Detection Patterns

Reference guide for identifying Sybase ASE Transact-SQL and distinguishing it from Microsoft SQL Server T-SQL.

## Dialect Identification Matrix

Sybase ASE and Microsoft SQL Server share a common T-SQL heritage (pre-1994 split), but diverged significantly. Use these markers to positively identify Sybase ASE code.

### Definitive Sybase ASE Markers

These constructs exist **only** in Sybase ASE and confirm the dialect:

| Marker | Context | Example |
|--------|---------|---------|
| `sp_procxmode` | Transaction mode setting | `EXEC sp_procxmode 'sp_settle', 'unchained'` |
| `SET CHAINED ON/OFF` | Session transaction mode | `SET CHAINED OFF` |
| `COMPUTE BY` (still active) | Inline subtotals | `COMPUTE SUM(amount) BY region` |
| `NOHOLDLOCK` | Locking hint | `SELECT * FROM trades (NOHOLDLOCK)` |
| `CREATE PROXY_TABLE` | CIS proxy definition | `CREATE PROXY_TABLE ext_prices AT 'REMOTE.db.dbo.prices'` |
| `CREATE EXISTING TABLE` | CIS remote table | `CREATE EXISTING TABLE remote_accts (...)` |
| `sp_addtype` | User-defined types | `EXEC sp_addtype currency, 'numeric(19,4)'` |
| `@@identity` without `SCOPE_IDENTITY()` | Identity retrieval | `SELECT @@identity` (Sybase has no SCOPE_IDENTITY) |
| Implicit unchained mode | Default behavior | Sybase defaults to unchained; SQL Server defaults to autocommit |
| `READTEXT` / `WRITETEXT` / `UPDATETEXT` | TEXT column manipulation | `READTEXT trades.notes @ptr 0 100` |

### Ambiguous Markers (Present in Both)

These exist in both Sybase and SQL Server but may behave differently:

| Marker | Sybase Behavior | SQL Server Behavior |
|--------|----------------|---------------------|
| `@@identity` | Connection-scoped, last identity value | Same, but SCOPE_IDENTITY() preferred |
| `SET ROWCOUNT n` | Still common, used for pagination | Deprecated in favor of TOP |
| `#temp_tables` | Created in tempdb, connection-scoped | Same syntax, different internal implementation |
| `HOLDLOCK` | Shared lock held to end of transaction | Same semantics |
| `READPAST` | Skip locked rows | Same but Sybase has additional locking modes |
| `BEGIN TRAN` / `COMMIT` / `ROLLBACK` | Depends on chained/unchained mode | Always autocommit unless explicit |
| `RAISERROR` | Different severity model (1-26) | Different severity model (0-25) |
| `PRINT` | Informational messages | Same |

### Microsoft SQL Server-Only Markers (Absence Confirms Sybase)

If these are absent from the codebase, it strengthens the Sybase ASE identification:

| Marker | Notes |
|--------|-------|
| `SCOPE_IDENTITY()` | Sybase has no equivalent — only `@@identity` |
| `TRY...CATCH` | Sybase uses `@@error` checking after each statement |
| `MERGE` statement | Sybase ASE does not support MERGE |
| `OUTPUT` clause on DML | Sybase does not support OUTPUT inserted/deleted |
| `WITH (NOLOCK)` hint syntax | Sybase uses `(NOHOLDLOCK)` instead |
| `CROSS APPLY` / `OUTER APPLY` | Not available in Sybase ASE |
| `ROW_NUMBER() OVER()` | Limited window function support in Sybase ASE 16+ |
| `OFFSET...FETCH` | Not available — Sybase uses SET ROWCOUNT |

## Complexity Scoring Rubric

### Dimension 1: Line Count (15% weight)

| Range | Score | Notes |
|-------|-------|-------|
| < 50 lines | 0-33 | Typical CRUD procedure |
| 50-200 lines | 34-66 | Moderate business logic |
| > 200 lines | 67-100 | Complex orchestration or transformation |

Scale linearly within each range. A 300-line procedure scores 80; a 500+ line procedure scores 100.

### Dimension 2: JOIN Depth (20% weight)

| Criteria | Score | Detection Pattern |
|----------|-------|-------------------|
| 0-1 JOINs | 0-33 | Count `JOIN` keywords or comma-separated FROM tables |
| 2-4 JOINs or 1 subquery | 34-66 | Include self-joins, count subqueries in WHERE/FROM |
| 5+ JOINs or nested subqueries | 67-100 | Nested subqueries add 20 points each |

### Dimension 3: Cursor Usage (15% weight)

| Criteria | Score | Detection Pattern |
|----------|-------|-------------------|
| No cursors | 0 | No `DECLARE ... CURSOR` found |
| Single cursor, no nesting | 34-50 | One `DECLARE ... CURSOR FOR` block |
| Nested cursors or cursor in loop | 67-100 | `DECLARE CURSOR` inside a `WHILE` loop, or two+ cursors |

Sybase cursor keywords: `DECLARE cursor_name CURSOR FOR`, `OPEN cursor_name`, `FETCH cursor_name INTO`, `CLOSE cursor_name`, `DEALLOCATE CURSOR cursor_name`.

### Dimension 4: Dynamic SQL (20% weight)

| Criteria | Score | Detection Pattern |
|----------|-------|-------------------|
| None | 0 | No `EXEC()` or `EXECUTE()` with string variable |
| Simple EXEC with parameters | 34-50 | `EXEC @sql_var` with parameterized inputs |
| String concatenation + EXEC | 67-100 | `SELECT @sql = 'SELECT ' + @col + ' FROM ' + @table` followed by `EXEC(@sql)` |

### Dimension 5: Cross-Schema References (15% weight)

| Criteria | Score | Detection Pattern |
|----------|-------|-------------------|
| Same database only | 0 | No `database..table` or `database.owner.table` syntax |
| References 1 other database | 34-50 | One external `db..table` reference |
| References 2+ databases or remote servers | 67-100 | Multiple `db..table` patterns or CIS proxy references |

Sybase cross-database pattern: `database_name..table_name` or `database_name.owner_name.table_name`.

### Dimension 6: Parameter Count (15% weight)

| Criteria | Score | Detection Pattern |
|----------|-------|-------------------|
| 0-3 parameters | 0-33 | Count `@param_name` in CREATE PROCEDURE header |
| 4-8 parameters | 34-66 | Moderate interface complexity |
| 9+ parameters or OUTPUT params | 67-100 | Add 15 points for each OUTPUT parameter |

## Financial Application T-SQL Patterns

### Settlement Procedures

```sql
-- Pattern: Settlement calculation with position netting
CREATE PROCEDURE sp_settle_trades
    @settle_date DATETIME,
    @account_id INT
AS
BEGIN
    -- Net positions across counterparties
    SELECT counterparty_id, instrument_id,
           SUM(CASE WHEN side = 'B' THEN quantity ELSE -quantity END) AS net_qty,
           SUM(CASE WHEN side = 'B' THEN amount ELSE -amount END) AS net_amount
    INTO #net_positions
    FROM trades
    WHERE settle_date = @settle_date AND account_id = @account_id
    GROUP BY counterparty_id, instrument_id

    -- Process settlements
    DECLARE settle_cursor CURSOR FOR
        SELECT counterparty_id, instrument_id, net_qty, net_amount
        FROM #net_positions WHERE ABS(net_qty) > 0
    -- ... cursor processing ...
END
```

**Detection**: References to `settle`, `clearing`, `netting` + cursor usage + temp table.

### P&L Calculation Procedures

```sql
-- Pattern: Mark-to-market P&L with COMPUTE BY
CREATE PROCEDURE sp_calc_pnl
    @business_date DATETIME,
    @book_id INT
AS
    SELECT p.instrument_id, p.quantity,
           p.avg_cost, m.close_price,
           (m.close_price - p.avg_cost) * p.quantity AS unrealized_pnl
    FROM positions p
    JOIN market_prices m ON p.instrument_id = m.instrument_id
    WHERE p.book_id = @book_id AND m.price_date = @business_date
    COMPUTE SUM(unrealized_pnl) BY book_id
```

**Detection**: References to `pnl`, `profit`, `loss`, `mark_to_market` + COMPUTE BY + MONEY arithmetic.

### Regulatory Reporting Procedures

```sql
-- Pattern: Regulatory data aggregation with cross-database access
CREATE PROCEDURE sp_regulatory_report
    @report_date DATETIME,
    @report_type VARCHAR(20)
AS
    SELECT t.trade_id, t.instrument_id, r.risk_weight,
           t.notional * r.risk_weight AS rwa
    FROM tradedb..trades t
    JOIN riskdb..risk_weights r ON t.asset_class = r.asset_class
    WHERE t.trade_date <= @report_date
```

**Detection**: References to `regulatory`, `compliance`, `Basel`, `CCAR`, `rwa` + cross-database syntax.
