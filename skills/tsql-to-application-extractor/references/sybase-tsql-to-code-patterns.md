# Sybase T-SQL to Application Code Patterns

This reference provides complete mappings from Sybase-specific T-SQL constructs to Java Spring Boot and Python FastAPI application code with Spanner client library integration.

## Sybase-Specific Constructs

### @@identity

Sybase returns the last IDENTITY value inserted in the current session.

**Sybase T-SQL:**
```sql
INSERT INTO orders (account_id, instrument_id, quantity)
VALUES (@account_id, @instrument_id, @quantity)
SELECT @order_id = @@identity
```

**Java (Spanner):**
```java
// Pre-generate ID from bit-reversed sequence
long orderId = getNextSequenceValue(transaction, "seq_order_id");
transaction.buffer(
    Mutation.newInsertBuilder("orders")
        .set("order_id").to(orderId)
        .set("account_id").to(request.getAccountId())
        .set("instrument_id").to(request.getInstrumentId())
        .set("quantity").to(request.getQuantity())
        .build());
// orderId is known before insert (no @@identity needed)

private long getNextSequenceValue(TransactionContext tx, String sequenceName) {
    try (ResultSet rs = tx.executeQuery(
            Statement.of("SELECT GET_NEXT_SEQUENCE_VALUE(SEQUENCE " + sequenceName + ")"))) {
        rs.next();
        return rs.getLong(0);
    }
}
```

**Python (Spanner):**
```python
def get_next_sequence_value(transaction, sequence_name):
    result = transaction.execute_sql(
        f"SELECT GET_NEXT_SEQUENCE_VALUE(SEQUENCE {sequence_name})"
    )
    return list(result)[0][0]

def book_order(transaction, request):
    order_id = get_next_sequence_value(transaction, "seq_order_id")
    transaction.insert(
        "orders",
        columns=["order_id", "account_id", "instrument_id", "quantity"],
        values=[(order_id, request.account_id, request.instrument_id, request.quantity)]
    )
    return order_id
```

### COMPUTE BY (Sybase-Specific Aggregation)

Sybase COMPUTE BY generates summary rows within result sets.

**Sybase T-SQL:**
```sql
SELECT account_id, instrument_id, quantity, amount
FROM trades
WHERE trade_date = @date
ORDER BY account_id
COMPUTE SUM(amount) BY account_id
COMPUTE SUM(amount)
```

**Java (Application-level aggregation):**
```java
public TradeReportWithSummaries generateReport(LocalDate date) {
    String sql = "SELECT account_id, instrument_id, quantity, amount "
               + "FROM trades WHERE trade_date = @date ORDER BY account_id";

    List<TradeRow> rows = spannerTemplate.query(sql,
        Statement.newBuilder().bind("date").to(date.toString()).build(),
        (rs, rowNum) -> new TradeRow(
            rs.getLong("account_id"),
            rs.getLong("instrument_id"),
            rs.getBigDecimal("quantity"),
            rs.getBigDecimal("amount")));

    // Application-level COMPUTE BY equivalent
    Map<Long, List<TradeRow>> byAccount = rows.stream()
        .collect(Collectors.groupingBy(TradeRow::getAccountId));

    List<AccountSummary> summaries = byAccount.entrySet().stream()
        .map(e -> new AccountSummary(
            e.getKey(),
            e.getValue(),
            e.getValue().stream()
                .map(TradeRow::getAmount)
                .reduce(BigDecimal.ZERO, BigDecimal::add)))
        .collect(Collectors.toList());

    BigDecimal grandTotal = rows.stream()
        .map(TradeRow::getAmount)
        .reduce(BigDecimal.ZERO, BigDecimal::add);

    return new TradeReportWithSummaries(summaries, grandTotal);
}
```

**Python (Application-level aggregation):**
```python
from itertools import groupby
from decimal import Decimal

def generate_report(database, date):
    with database.snapshot() as snapshot:
        results = snapshot.execute_sql(
            "SELECT account_id, instrument_id, quantity, amount "
            "FROM trades WHERE trade_date = @date ORDER BY account_id",
            params={"date": date},
            param_types={"date": spanner.param_types.DATE}
        )
        rows = list(results)

    # Application-level COMPUTE BY equivalent
    summaries = []
    grand_total = Decimal("0")
    for account_id, group in groupby(rows, key=lambda r: r[0]):
        group_rows = list(group)
        account_total = sum(r[3] for r in group_rows)
        summaries.append({
            "account_id": account_id,
            "trades": group_rows,
            "total": account_total
        })
        grand_total += account_total

    return {"summaries": summaries, "grand_total": grand_total}
```

### sp_procxmode (Transaction Mode Control)

Sybase allows per-procedure transaction mode setting.

**Sybase T-SQL:**
```sql
-- Set procedure to run in chained mode (auto-commit off)
sp_procxmode sp_book_trade, 'chained'
-- or unchained (auto-commit on, explicit BEGIN TRAN required)
sp_procxmode sp_book_trade, 'unchained'
```

**Java equivalent:**
```java
// Chained mode = always in transaction
// Use @Transactional or readWriteTransaction
@Transactional  // Equivalent to chained mode
public void bookTrade(TradeRequest request) {
    // All operations within implicit transaction
}

// Unchained mode = explicit transaction management
public void bookTradeUnchained(TradeRequest request) {
    // Some operations auto-commit (reads)
    TradeDetails details = readTradeDetails(request);  // No transaction needed

    // Explicit transaction for writes
    dbClient.readWriteTransaction().run(tx -> {
        // BEGIN TRAN equivalent
        insertOrder(tx, request, details);
        updatePosition(tx, request, details);
        insertAudit(tx, request);
        return null;
        // COMMIT TRAN equivalent (on successful return)
    });
}
```

### HOLDLOCK (Lock Hint)

Sybase HOLDLOCK holds shared locks until end of transaction.

**Sybase T-SQL:**
```sql
SELECT quantity, avg_price
FROM positions WITH (HOLDLOCK)
WHERE account_id = @account_id AND instrument_id = @instrument_id
```

**Java (Spanner):**
```java
// Spanner read-write transactions provide serializable isolation
// No lock hints needed -- reads within readWriteTransaction are
// automatically held until commit
dbClient.readWriteTransaction().run(tx -> {
    // This read is within a read-write transaction
    // Spanner automatically provides serializable isolation
    // Equivalent to HOLDLOCK behavior
    Struct position = tx.readRow(
        "positions",
        Key.of(accountId, instrumentId),
        Arrays.asList("quantity", "avg_price"));

    // Position is locked for the duration of this transaction
    // Other transactions attempting to modify will wait or abort
    return null;
});
```

### SET ROWCOUNT

Sybase SET ROWCOUNT limits rows affected by subsequent statements.

**Sybase T-SQL:**
```sql
SET ROWCOUNT 1000
DELETE FROM temp_data WHERE created_date < @cutoff
SET ROWCOUNT 0  -- Reset
```

**Java (Spanner - Partitioned DML for large deletes):**
```java
// For large bulk operations, use partitioned DML
long rowsDeleted = dbClient.executePartitionedUpdate(
    Statement.newBuilder(
        "DELETE FROM temp_data WHERE created_date < @cutoff")
        .bind("cutoff").to(cutoffTimestamp)
        .build());

// For batch-limited operations (SET ROWCOUNT equivalent)
long rowsDeleted = dbClient.readWriteTransaction().run(tx -> {
    return tx.executeUpdate(
        Statement.newBuilder(
            "DELETE FROM temp_data WHERE created_date < @cutoff LIMIT @batch_size")
            .bind("cutoff").to(cutoffTimestamp)
            .bind("batch_size").to(1000L)
            .build());
});
```

### Cursors (DECLARE CURSOR / FETCH)

**Sybase T-SQL:**
```sql
DECLARE trade_cursor CURSOR FOR
    SELECT trade_id, amount FROM pending_trades WHERE status = 'PENDING'
OPEN trade_cursor
FETCH trade_cursor INTO @trade_id, @amount
WHILE @@sqlstatus = 0
BEGIN
    -- Process each trade
    EXEC sp_process_trade @trade_id, @amount
    FETCH trade_cursor INTO @trade_id, @amount
END
CLOSE trade_cursor
DEALLOCATE CURSOR trade_cursor
```

**Java (Stream/Iterator):**
```java
public void processPendingTrades() {
    String sql = "SELECT trade_id, amount FROM pending_trades WHERE status = 'PENDING'";

    dbClient.readWriteTransaction().run(tx -> {
        try (ResultSet rs = tx.executeQuery(Statement.of(sql))) {
            while (rs.next()) {
                long tradeId = rs.getLong("trade_id");
                BigDecimal amount = rs.getBigDecimal("amount");
                processTrade(tx, tradeId, amount);
            }
        }
        return null;
    });
}
```

**Python (Iterator):**
```python
def process_pending_trades(database):
    def process(transaction):
        results = transaction.execute_sql(
            "SELECT trade_id, amount FROM pending_trades WHERE status = 'PENDING'"
        )
        for row in results:
            trade_id, amount = row
            process_trade(transaction, trade_id, amount)

    database.run_in_transaction(process)
```

### Temporary Tables (#temp, ##temp)

**Sybase T-SQL:**
```sql
-- Session temp table
CREATE TABLE #temp_positions (
    account_id INT,
    instrument_id INT,
    quantity NUMERIC(18,4)
)
INSERT INTO #temp_positions SELECT ... FROM positions WHERE ...
-- Use #temp_positions in subsequent queries
```

**Java (In-memory collection):**
```java
// Replace temp tables with in-memory collections
List<PositionSnapshot> tempPositions = spannerTemplate.query(
    "SELECT account_id, instrument_id, quantity FROM positions WHERE ...",
    (rs, rowNum) -> new PositionSnapshot(
        rs.getLong("account_id"),
        rs.getLong("instrument_id"),
        rs.getBigDecimal("quantity")));

// Use tempPositions in subsequent logic
Map<Long, List<PositionSnapshot>> byAccount = tempPositions.stream()
    .collect(Collectors.groupingBy(PositionSnapshot::getAccountId));
```

**Python (In-memory collection):**
```python
# Replace temp tables with in-memory collections
with database.snapshot() as snapshot:
    results = snapshot.execute_sql(
        "SELECT account_id, instrument_id, quantity FROM positions WHERE ..."
    )
    temp_positions = [
        {"account_id": r[0], "instrument_id": r[1], "quantity": r[2]}
        for r in results
    ]

# Use temp_positions in subsequent logic
from collections import defaultdict
by_account = defaultdict(list)
for pos in temp_positions:
    by_account[pos["account_id"]].append(pos)
```

### Dynamic SQL (EXEC(@sql))

**Sybase T-SQL:**
```sql
DECLARE @sql VARCHAR(2000)
SELECT @sql = 'SELECT * FROM ' + @table_name + ' WHERE trade_date = ''' + CONVERT(VARCHAR, @date) + ''''
EXEC(@sql)
```

**Java (Query builder -- never concatenate SQL strings):**
```java
// Use parameterized queries -- NEVER string concatenation
Statement.Builder builder = Statement.newBuilder(
    "SELECT * FROM trades WHERE trade_date = @date");
builder.bind("date").to(date.toString());

// For dynamic column selection, use a safe allowlist
Set<String> allowedColumns = Set.of("trade_id", "account_id", "amount", "status");
String columns = requestedColumns.stream()
    .filter(allowedColumns::contains)
    .collect(Collectors.joining(", "));
String sql = "SELECT " + columns + " FROM trades WHERE trade_date = @date";
```

## Spanner Client Library Patterns

### Mutation Batching (Replacing BCP Bulk Insert)

**Java:**
```java
public void bulkInsert(List<TradeRecord> records) {
    List<Mutation> mutations = records.stream()
        .map(r -> Mutation.newInsertBuilder("trades")
            .set("trade_id").to(r.getTradeId())
            .set("account_id").to(r.getAccountId())
            .set("amount").to(r.getAmount())
            .set("spanner_commit_ts").to(Value.COMMIT_TIMESTAMP)
            .build())
        .collect(Collectors.toList());

    // Batch write (max ~80,000 mutations or 100MB per commit)
    // For larger batches, chunk into multiple commits
    List<List<Mutation>> chunks = Lists.partition(mutations, 10000);
    for (List<Mutation> chunk : chunks) {
        dbClient.write(chunk);
    }
}
```

**Python:**
```python
def bulk_insert(database, records):
    # Batch insert using batch context
    BATCH_SIZE = 10000
    for i in range(0, len(records), BATCH_SIZE):
        chunk = records[i:i + BATCH_SIZE]
        with database.batch() as batch:
            batch.insert(
                "trades",
                columns=["trade_id", "account_id", "amount", "spanner_commit_ts"],
                values=[
                    (r.trade_id, r.account_id, r.amount, spanner.COMMIT_TIMESTAMP)
                    for r in chunk
                ]
            )
```

### Stale Read Configuration

**Java:**
```java
// Exact staleness (read data as of 15 seconds ago)
// Useful for reporting queries where slight staleness is acceptable
try (ResultSet rs = dbClient
        .singleUse(TimestampBound.ofExactStaleness(15, TimeUnit.SECONDS))
        .executeQuery(Statement.of("SELECT * FROM positions WHERE portfolio_id = @id"))) {
    // Process results
}

// Strong read (default, latest data)
// Required for trading operations
try (ResultSet rs = dbClient
        .singleUse(TimestampBound.strong())
        .executeQuery(Statement.of("SELECT * FROM positions WHERE portfolio_id = @id"))) {
    // Process results
}
```

**Python:**
```python
import datetime

# Exact staleness
with database.snapshot(exact_staleness=datetime.timedelta(seconds=15)) as snapshot:
    results = snapshot.execute_sql(
        "SELECT * FROM positions WHERE portfolio_id = @id",
        params={"id": portfolio_id},
        param_types={"id": spanner.param_types.INT64}
    )

# Strong read (default)
with database.snapshot() as snapshot:
    results = snapshot.execute_sql("SELECT * FROM positions WHERE portfolio_id = @id",
        params={"id": portfolio_id},
        param_types={"id": spanner.param_types.INT64}
    )
```

### Read-Write Transaction with Retry

**Java:**
```java
// Spanner client automatically retries aborted transactions
// The transaction function may be called multiple times
TradeResult result = dbClient.readWriteTransaction().run(transaction -> {
    // READ: Get current position (automatically locked)
    Struct position = transaction.readRow(
        "positions",
        Key.of(accountId, instrumentId),
        Arrays.asList("quantity", "avg_cost"));

    // COMPUTE: Calculate new position
    BigDecimal newQty = position.getBigDecimal("quantity").add(tradeQuantity);

    // WRITE: Update position
    transaction.buffer(
        Mutation.newUpdateBuilder("positions")
            .set("portfolio_id").to(portfolioId)
            .set("instrument_id").to(instrumentId)
            .set("quantity").to(newQty)
            .set("updated_at").to(Value.COMMIT_TIMESTAMP)
            .build());

    return new TradeResult(newQty);
});
// If another transaction modifies the same position concurrently,
// Spanner aborts this transaction and the client retries automatically
```

**Python:**
```python
def update_position(transaction, portfolio_id, instrument_id, trade_quantity):
    # READ
    result = transaction.read(
        "positions",
        columns=["quantity", "avg_cost"],
        keyset=spanner.KeySet(keys=[(portfolio_id, instrument_id)])
    )
    row = list(result)[0]
    current_qty = row[0]

    # COMPUTE
    new_qty = current_qty + trade_quantity

    # WRITE
    transaction.update(
        "positions",
        columns=["portfolio_id", "instrument_id", "quantity", "updated_at"],
        values=[(portfolio_id, instrument_id, new_qty, spanner.COMMIT_TIMESTAMP)]
    )
    return new_qty

# Spanner automatically retries on abort
result = database.run_in_transaction(
    update_position, portfolio_id, instrument_id, trade_quantity
)
```
