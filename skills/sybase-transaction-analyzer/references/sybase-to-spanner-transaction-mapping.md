# Sybase to Spanner Transaction Mapping Reference

Complete mapping of Sybase ASE transaction semantics to Cloud Spanner equivalents for migration planning.

## Transaction Mode Mapping

### Chained Mode (ANSI Compliance)

In chained mode (`SET CHAINED ON`), Sybase implicitly begins a transaction on the first data-modifying statement. The transaction remains open until an explicit `COMMIT` or `ROLLBACK`.

**Sybase behavior:**
```sql
-- Chained mode: implicit transaction start
SET CHAINED ON
UPDATE positions SET quantity = 100 WHERE book_id = 'FX'  -- implicit BEGIN TRAN
INSERT INTO audit_trail VALUES ('POSITION_UPDATE', GETDATE())
COMMIT  -- commits both statements atomically
```

**Spanner equivalent:**
```python
# Spanner: explicit transaction via run_in_transaction
def update_position(transaction):
    transaction.execute_update(
        "UPDATE positions SET quantity = 100 WHERE book_id = 'FX'")
    transaction.execute_update(
        "INSERT INTO audit_trail (event, ts) VALUES ('POSITION_UPDATE', PENDING_COMMIT_TIMESTAMP())")

database.run_in_transaction(update_position)
```

### Unchained Mode (Sybase Default)

In unchained mode (`SET CHAINED OFF`), each statement auto-commits unless wrapped in explicit `BEGIN TRAN / COMMIT`.

**Sybase behavior:**
```sql
-- Unchained mode: explicit transaction required
SET CHAINED OFF
BEGIN TRAN
    UPDATE positions SET quantity = 100 WHERE book_id = 'FX'
    INSERT INTO audit_trail VALUES ('POSITION_UPDATE', GETDATE())
COMMIT TRAN
-- Without BEGIN TRAN, each statement would auto-commit independently
```

**Spanner equivalent:**
```python
# Same as chained mode - Spanner always requires explicit transaction boundary
# Auto-commit is available for single statements via execute_update()
# For multi-statement atomicity, use run_in_transaction()
database.run_in_transaction(update_position)
```

### Mixed Mode (sp_procxmode)

Sybase allows per-procedure transaction mode via `sp_procxmode`. This means different procedures in the same session can behave differently.

```sql
-- Set procedure to chained mode
sp_procxmode sp_book_trade, 'chained'

-- Set procedure to unchained mode
sp_procxmode sp_quick_lookup, 'unchained'

-- Set procedure to work in any mode
sp_procxmode sp_flexible_proc, 'anymode'
```

**Spanner migration:** There is no per-function transaction mode in Spanner. Standardize all code to use explicit `run_in_transaction` for multi-statement operations and auto-commit for single statements.

---

## Isolation Level Mapping

### Level 0: Read Uncommitted (Dirty Reads)

**Sybase:**
```sql
SET TRANSACTION ISOLATION LEVEL 0
SELECT * FROM positions  -- may read uncommitted data
```

**Spanner:** No dirty read capability. Alternatives:

| Use Case | Spanner Alternative | Staleness |
|----------|-------------------|-----------|
| Dashboard monitoring | Stale read (exact_staleness=15s) | 15 seconds |
| Approximate counts | Stale read (exact_staleness=10s) | 10 seconds |
| Non-critical reporting | Stale read (max_staleness=30s) | Up to 30 seconds |
| Queue polling | Stale read (exact_staleness=1s) | 1 second |

```python
# Stale read replacement for Level 0
with database.snapshot(exact_staleness=datetime.timedelta(seconds=15)) as snapshot:
    results = snapshot.execute_sql("SELECT * FROM positions")
```

### Level 1: Read Committed (Sybase Default)

**Sybase:**
```sql
SET TRANSACTION ISOLATION LEVEL 1
-- Reads only committed data
-- Non-repeatable reads possible (another transaction may commit between two reads)
```

**Spanner:** Spanner provides serializable isolation by default, which is stronger. Reads within a transaction are repeatable. This is a safe upgrade with no behavioral issues in most cases.

### Level 2: Repeatable Read

**Sybase:**
```sql
SET TRANSACTION ISOLATION LEVEL 2
-- Reads are repeatable within the transaction
-- Phantom reads still possible (new rows may appear)
```

**Spanner:** Spanner provides serializable (no phantoms), which is strictly stronger. Safe upgrade.

### Level 3: Serializable

**Sybase:**
```sql
SET TRANSACTION ISOLATION LEVEL 3
-- Full serializable isolation
```

**Spanner:** Exact match. Spanner provides external consistency, which is even stronger than serializable (global ordering).

---

## Lock Hint Mapping

### HOLDLOCK → Spanner Read-Write Transaction

**Sybase:**
```sql
SELECT * FROM positions WITH (HOLDLOCK) WHERE book_id = 'FX'
-- Holds shared lock until transaction commits, preventing modifications
```

**Spanner:** Within a read-write transaction, all reads acquire shared locks automatically. No hint needed.

```python
def check_and_update(transaction):
    # Read acquires lock automatically in read-write transaction
    pos = transaction.execute_sql(
        "SELECT quantity FROM positions WHERE book_id = 'FX'")
    # Lock held until commit - no HOLDLOCK hint needed
    transaction.execute_update(
        "UPDATE positions SET quantity = @new_qty WHERE book_id = 'FX'",
        params={'new_qty': new_quantity})
```

### NOHOLDLOCK → Spanner Read-Only Transaction or Stale Read

**Sybase:**
```sql
SELECT * FROM prices WITH (NOHOLDLOCK) WHERE symbol = 'AAPL'
-- Releases shared lock immediately after read
```

**Spanner:** Use a read-only transaction or stale read for non-locking reads.

```python
# Read-only transaction (no locks)
with database.snapshot() as snapshot:
    prices = snapshot.execute_sql(
        "SELECT * FROM prices WHERE symbol = 'AAPL'")
```

### READPAST → Application-Level Queue Pattern

**Sybase:**
```sql
SELECT TOP 1 * FROM message_queue WITH (READPAST, UPDLOCK)
WHERE status = 'PENDING'
-- Skips rows locked by other transactions, useful for queue processing
```

**Spanner:** No READPAST equivalent. Redesign using:

1. **Partitioned queue:** Assign queue items to workers via partition key
2. **Optimistic queue:** Read, attempt update, retry on ABORTED
3. **Cloud Pub/Sub:** Replace database queue with message queue service

```python
# Optimistic queue pattern for Spanner
def process_next_message(transaction):
    results = transaction.execute_sql(
        "SELECT message_id FROM message_queue "
        "WHERE status = 'PENDING' AND assigned_worker IS NULL "
        "LIMIT 1")
    for row in results:
        transaction.execute_update(
            "UPDATE message_queue SET status = 'PROCESSING', "
            "assigned_worker = @worker WHERE message_id = @id "
            "AND status = 'PENDING'",
            params={'worker': worker_id, 'id': row[0]})
```

---

## Savepoint Mapping

### Sybase Savepoints

```sql
BEGIN TRAN
    INSERT INTO orders VALUES (...)
    SAVE TRAN after_order              -- savepoint

    UPDATE positions SET ...
    IF @@error != 0
    BEGIN
        ROLLBACK TRAN after_order      -- rollback to savepoint
        -- order insert is preserved, position update rolled back
    END

    INSERT INTO audit_trail VALUES (...)
COMMIT TRAN
```

### Spanner: No Native Savepoints

Spanner does not support savepoints. Migration strategies:

1. **Restructure as separate transactions** (if partial commit is acceptable)
2. **Application-level checkpointing** with compensating operations
3. **Conditional logic** replacing savepoint rollback with IF/ELSE flow

```python
def book_trade_with_fallback(transaction):
    # Insert order (equivalent to pre-savepoint)
    transaction.execute_update("INSERT INTO orders ...")

    # Attempt position update (equivalent to post-savepoint)
    try:
        transaction.execute_update("UPDATE positions SET ...")
    except Exception:
        # Cannot rollback to savepoint in Spanner
        # Option 1: Let entire transaction abort and retry
        raise
        # Option 2: Insert compensating record
        # transaction.execute_update("INSERT INTO failed_updates ...")

    transaction.execute_update("INSERT INTO audit_trail ...")
```

---

## XA/DTC → Saga Patterns

### Sybase XA Distributed Transactions

```sql
-- Two-phase commit across multiple resource managers
xa_start 'trade_global_txn', 1
    -- Operations on ASE database 1
    INSERT INTO trading_db..orders VALUES (...)
    -- Operations on ASE database 2 (or Oracle, DB2)
    INSERT INTO settlement_db..instructions VALUES (...)
xa_end 'trade_global_txn', 1
xa_prepare 'trade_global_txn', 1
xa_commit 'trade_global_txn', 1
```

### Spanner: Single Database or Saga

**Option 1: Consolidate into single Spanner database**
- If both databases can merge into one Spanner database
- Spanner transactions are always single-database
- Strongest consistency guarantee

**Option 2: Saga pattern with Cloud Workflows**
```yaml
# Cloud Workflows saga definition
main:
  steps:
    - book_order:
        call: http.post
        args:
          url: ${TRADING_SERVICE}/orders
          body: ${order_data}
        result: order_result
    - create_settlement:
        try:
          call: http.post
          args:
            url: ${SETTLEMENT_SERVICE}/instructions
            body:
              order_id: ${order_result.body.order_id}
        except:
          steps:
            - compensate_order:
                call: http.delete
                args:
                  url: ${TRADING_SERVICE}/orders/${order_result.body.order_id}
            - raise_error:
                raise: "Settlement creation failed, order compensated"
```

**Option 3: Outbox pattern**
- Write to local database + outbox table atomically
- Background process reads outbox and applies to remote database
- Eventually consistent but reliable

---

## @@trancount Nesting → Spanner Flat Transactions

### Sybase Nested Transactions

```sql
-- Outer procedure
BEGIN TRAN                    -- @@trancount = 1
    EXEC sp_inner_procedure   -- may have its own BEGIN TRAN
COMMIT TRAN                   -- @@trancount = 0, actual commit

-- Inner procedure
CREATE PROCEDURE sp_inner_procedure AS
BEGIN
    BEGIN TRAN                -- @@trancount = 2 (nested)
        INSERT INTO audit_trail VALUES (...)
    COMMIT TRAN               -- @@trancount = 1 (decrements, no actual commit)
END
```

### Spanner: No Nested Transactions

Spanner transactions are flat. Migration approach:

1. **Remove inner BEGIN TRAN/COMMIT** when called within outer transaction
2. **Pass transaction object** to inner functions
3. **Use @@trancount checks** to conditionally begin/commit

```python
# Spanner: pass transaction to inner function
def outer_procedure(transaction):
    transaction.execute_update("INSERT INTO orders ...")
    inner_procedure(transaction)  # share same transaction
    transaction.execute_update("INSERT INTO audit_trail ...")

def inner_procedure(transaction):
    # No separate transaction - uses passed transaction
    transaction.execute_update("INSERT INTO audit_detail ...")
```
