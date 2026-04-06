# Financial Transaction Patterns Reference

Detailed reference for financial enterprise transaction patterns in Sybase environments and their Cloud Spanner migration strategies.

## Trade Lifecycle Transactions

### Order-to-Settlement Atomic Chain

In financial trading systems, the trade lifecycle typically spans multiple database operations that must maintain strict consistency guarantees.

**Sybase pattern: Trade booking as single atomic unit**

```sql
CREATE PROCEDURE sp_book_trade
    @order_id INT,
    @symbol VARCHAR(20),
    @quantity DECIMAL(18,4),
    @price DECIMAL(18,6),
    @book_id VARCHAR(20),
    @counterparty_id INT
AS
BEGIN
    DECLARE @fill_id INT, @position_qty DECIMAL(18,4)

    BEGIN TRAN trade_booking

    -- Step 1: Create order record
    INSERT INTO orders (order_id, symbol, quantity, price, status, order_time)
    VALUES (@order_id, @symbol, @quantity, @price, 'FILLED', GETDATE())

    IF @@error != 0 GOTO error_handler

    -- Step 2: Create fill record
    SELECT @fill_id = MAX(fill_id) + 1 FROM fills
    INSERT INTO fills (fill_id, order_id, fill_price, fill_quantity, fill_time)
    VALUES (@fill_id, @order_id, @price, @quantity, GETDATE())

    IF @@error != 0 GOTO error_handler

    -- Step 3: Update position (read-modify-write)
    SELECT @position_qty = quantity
    FROM positions WITH (HOLDLOCK)
    WHERE book_id = @book_id AND symbol = @symbol

    IF @position_qty IS NULL
        INSERT INTO positions (book_id, symbol, quantity, avg_price)
        VALUES (@book_id, @symbol, @quantity, @price)
    ELSE
        UPDATE positions
        SET quantity = @position_qty + @quantity,
            avg_price = ((@position_qty * avg_price) + (@quantity * @price)) / (@position_qty + @quantity)
        WHERE book_id = @book_id AND symbol = @symbol

    IF @@error != 0 GOTO error_handler

    -- Step 4: Create settlement instruction
    INSERT INTO settlement_instructions (order_id, counterparty_id, symbol, quantity, settlement_date, status)
    VALUES (@order_id, @counterparty_id, @symbol, @quantity, DATEADD(dd, 2, GETDATE()), 'PENDING')

    IF @@error != 0 GOTO error_handler

    -- Step 5: Audit trail
    INSERT INTO audit_trail (event_type, entity_id, details, event_time)
    VALUES ('TRADE_BOOKED', @order_id, 'Order filled and position updated', GETDATE())

    COMMIT TRAN trade_booking
    RETURN 0

error_handler:
    ROLLBACK TRAN trade_booking
    RAISERROR('Trade booking failed for order %d', 16, 1, @order_id)
    RETURN -1
END
```

**Spanner equivalent:**

```python
def book_trade(transaction, order):
    # Step 1: Insert order
    transaction.insert('orders', columns=[...], values=[...])

    # Step 2: Insert fill
    transaction.insert('fills', columns=[...], values=[...])

    # Step 3: Read-modify-write position (Spanner handles locking)
    position = list(transaction.read(
        'positions',
        columns=['book_id', 'symbol', 'quantity', 'avg_price'],
        keyset=spanner.KeySet(keys=[[order['book_id'], order['symbol']]])))

    if not position:
        transaction.insert('positions', columns=[...], values=[...])
    else:
        old_qty = position[0][2]
        new_qty = old_qty + order['quantity']
        new_avg = ((old_qty * position[0][3]) + (order['quantity'] * order['price'])) / new_qty
        transaction.update('positions',
            columns=['book_id', 'symbol', 'quantity', 'avg_price'],
            values=[[order['book_id'], order['symbol'], new_qty, new_avg]])

    # Step 4: Insert settlement instruction
    transaction.insert('settlement_instructions', columns=[...], values=[...])

    # Step 5: Audit trail with commit timestamp
    transaction.insert('audit_trail',
        columns=['event_type', 'entity_id', 'details', 'commit_ts'],
        values=['TRADE_BOOKED', order['order_id'], 'Order filled', spanner.COMMIT_TIMESTAMP])

# Automatic retry on ABORTED (replaces @@error handling)
database.run_in_transaction(book_trade, order=order_data)
```

**Key differences:**
- Spanner `run_in_transaction` auto-retries on ABORTED (replaces deadlock retry logic)
- No explicit HOLDLOCK needed (Spanner read-write transaction provides it)
- Commit timestamp replaces `GETDATE()` for audit trails (globally consistent)
- No `@@error` checking; exceptions propagate naturally

---

## Position Keeping Patterns

### Read-Modify-Write with Spanner Mutations

Position keeping is the most contention-sensitive operation in trading systems. Multiple trades for the same book/symbol may update the same position row simultaneously.

**Sybase pattern: Pessimistic locking**

```sql
-- Acquire exclusive lock before read
SELECT @current_qty = quantity, @current_avg = avg_price
FROM positions WITH (UPDLOCK)
WHERE book_id = @book_id AND symbol = @symbol

-- Modify
SET @new_qty = @current_qty + @delta
SET @new_avg = ((@current_qty * @current_avg) + (@delta * @trade_price)) / @new_qty

-- Write
UPDATE positions
SET quantity = @new_qty, avg_price = @new_avg, last_updated = GETDATE()
WHERE book_id = @book_id AND symbol = @symbol
```

**Spanner pattern: Optimistic concurrency**

```python
def update_position(transaction, book_id, symbol, delta, trade_price):
    # Read acquires shared lock within read-write transaction
    results = list(transaction.read(
        'positions',
        columns=['quantity', 'avg_price'],
        keyset=spanner.KeySet(keys=[[book_id, symbol]])))

    if results:
        current_qty, current_avg = results[0]
        new_qty = current_qty + delta
        new_avg = ((current_qty * current_avg) + (delta * trade_price)) / new_qty
        transaction.update('positions',
            columns=['book_id', 'symbol', 'quantity', 'avg_price', 'last_updated'],
            values=[[book_id, symbol, new_qty, new_avg, spanner.COMMIT_TIMESTAMP]])
    else:
        transaction.insert('positions',
            columns=['book_id', 'symbol', 'quantity', 'avg_price', 'last_updated'],
            values=[[book_id, symbol, delta, trade_price, spanner.COMMIT_TIMESTAMP]])

# If concurrent update, Spanner aborts and run_in_transaction retries
database.run_in_transaction(update_position,
    book_id='FX_SPOT', symbol='EUR/USD', delta=1000000, trade_price=1.0842)
```

**Hot-spot mitigation for high-frequency positions:**
- Use Spanner interleaved tables to co-locate position with parent book
- Consider position sharding (split position by value date or sub-book)
- Use bit-reversal for position IDs if sequential inserts cause hotspots

---

## EOD Batch Transactions

### Settlement Batch Processing

EOD settlement involves processing thousands of trades, typically within a tight time window (e.g., 18:00-22:00).

**Sybase pattern: Large batch in single transaction**

```sql
-- PROBLEMATIC: Single transaction processing all trades
BEGIN TRAN eod_settlement
    -- Process all pending trades (could be 100K+ rows)
    UPDATE settlement_instructions
    SET status = 'PROCESSING'
    WHERE settlement_date = @today AND status = 'PENDING'

    -- Net positions by counterparty
    INSERT INTO net_positions
    SELECT counterparty_id, symbol, SUM(quantity), settlement_date
    FROM settlement_instructions
    WHERE status = 'PROCESSING'
    GROUP BY counterparty_id, symbol, settlement_date

    -- Generate SWIFT messages
    INSERT INTO swift_outbound
    SELECT ... FROM net_positions WHERE ...

    -- Update balances
    UPDATE nostro_accounts SET balance = balance + @net_amount
    WHERE account_id = @account AND currency = @ccy

COMMIT TRAN eod_settlement  -- massive transaction, long lock hold
```

**Spanner migration: Partitioned DML + orchestration**

```python
# Step 1: Mark trades for processing (Partitioned DML - non-atomic but scalable)
database.execute_partitioned_dml(
    "UPDATE settlement_instructions SET status = 'PROCESSING' "
    "WHERE settlement_date = @today AND status = 'PENDING'",
    params={'today': settlement_date})

# Step 2: Net positions (read-only snapshot + batch insert)
with database.snapshot() as snapshot:
    net_positions = list(snapshot.execute_sql(
        "SELECT counterparty_id, symbol, SUM(quantity) "
        "FROM settlement_instructions "
        "WHERE status = 'PROCESSING' "
        "GROUP BY counterparty_id, symbol"))

# Step 3: Insert net positions in batches of 1000
for batch in chunks(net_positions, 1000):
    with database.batch() as b:
        for row in batch:
            b.insert('net_positions', columns=[...], values=row)

# Step 4: Generate SWIFT messages (per-counterparty transactions)
for counterparty in counterparties:
    database.run_in_transaction(generate_swift, counterparty=counterparty)

# Step 5: Update balances (per-account transactions)
for account in accounts:
    database.run_in_transaction(update_balance, account=account)
```

**Key design change:** Break monolithic batch transaction into:
1. Partitioned DML for bulk status updates
2. Read-only snapshot for aggregation
3. Batch mutations for bulk inserts
4. Per-entity transactions for balance updates (maintains atomicity where needed)

---

## Balance Reconciliation Patterns

### Nostro/Vostro Reconciliation

```sql
-- Sybase: Compare internal position with external statement
CREATE PROCEDURE sp_reconcile_nostro
    @account_id VARCHAR(20),
    @value_date DATE
AS
BEGIN
    BEGIN TRAN reconciliation
        -- Read internal balance
        SELECT @internal = balance
        FROM nostro_accounts WITH (HOLDLOCK)
        WHERE account_id = @account_id

        -- Read external balance (from loaded statement)
        SELECT @external = statement_balance
        FROM external_statements
        WHERE account_id = @account_id AND value_date = @value_date

        -- Calculate breaks
        SET @break_amount = @internal - @external

        -- Record reconciliation result
        INSERT INTO recon_results (account_id, value_date, internal_bal, external_bal, break_amount, status)
        VALUES (@account_id, @value_date, @internal, @external, @break_amount,
                CASE WHEN ABS(@break_amount) < 0.01 THEN 'MATCHED' ELSE 'BREAK' END)

        -- If break, create investigation item
        IF ABS(@break_amount) >= 0.01
            INSERT INTO recon_breaks (account_id, value_date, break_amount, status)
            VALUES (@account_id, @value_date, @break_amount, 'OPEN')

    COMMIT TRAN reconciliation
END
```

**Spanner equivalent:** Standard read-write transaction; no special handling needed since reconciliation is naturally per-account.

---

## Margin Calculation Atomicity

### Real-Time Margin Updates

Margin calculations must be atomic: read positions, calculate margin requirement, compare with collateral, and update margin status.

```sql
-- Sybase: Margin calculation must be atomic
BEGIN TRAN margin_check
    -- Read all positions for client
    SELECT @total_exposure = SUM(quantity * current_price * margin_rate)
    FROM positions p
    JOIN margin_rates m ON p.product_type = m.product_type
    WHERE p.client_id = @client_id

    -- Read available collateral
    SELECT @collateral = SUM(value)
    FROM collateral
    WHERE client_id = @client_id AND status = 'AVAILABLE'

    -- Calculate margin status
    SET @margin_ratio = @collateral / @total_exposure

    -- Update margin status
    UPDATE margin_status
    SET ratio = @margin_ratio,
        status = CASE
            WHEN @margin_ratio >= 1.5 THEN 'ADEQUATE'
            WHEN @margin_ratio >= 1.0 THEN 'WARNING'
            ELSE 'MARGIN_CALL'
        END,
        last_calculated = GETDATE()
    WHERE client_id = @client_id

    -- If margin call, create notification
    IF @margin_ratio < 1.0
        INSERT INTO margin_calls (client_id, required_amount, status, created)
        VALUES (@client_id, @total_exposure - @collateral, 'PENDING', GETDATE())

COMMIT TRAN margin_check
```

**Spanner equivalent:** Direct mapping to read-write transaction. The per-client scope keeps transaction size manageable.

```python
def check_margin(transaction, client_id):
    exposure = transaction.execute_sql(
        "SELECT SUM(p.quantity * p.current_price * m.margin_rate) "
        "FROM positions p JOIN margin_rates m ON p.product_type = m.product_type "
        "WHERE p.client_id = @client_id",
        params={'client_id': client_id})

    collateral = transaction.execute_sql(
        "SELECT SUM(value) FROM collateral "
        "WHERE client_id = @client_id AND status = 'AVAILABLE'",
        params={'client_id': client_id})

    ratio = collateral_value / exposure_value
    status = 'ADEQUATE' if ratio >= 1.5 else 'WARNING' if ratio >= 1.0 else 'MARGIN_CALL'

    transaction.execute_update(
        "UPDATE margin_status SET ratio = @ratio, status = @status, "
        "last_calculated = PENDING_COMMIT_TIMESTAMP() "
        "WHERE client_id = @client_id",
        params={'ratio': ratio, 'status': status, 'client_id': client_id})

    if ratio < 1.0:
        transaction.insert('margin_calls', ...)

database.run_in_transaction(check_margin, client_id=client_id)
```

---

## Anti-Patterns to Flag During Migration

| Sybase Anti-Pattern | Risk | Spanner Impact | Remediation |
|-------------------|------|---------------|-------------|
| Large batch in single TRAN | HIGH | Exceeds mutation limits (80K) | Break into partitioned DML + batch mutations |
| Interactive transaction (user wait) | CRITICAL | Transaction timeout (10s recommended) | Separate read and write phases |
| Cursor processing within TRAN | HIGH | Long transaction duration | Batch processing with checkpoints |
| SELECT INTO #temp within TRAN | MEDIUM | No tempdb in Spanner | Use CTEs or application-side buffering |
| WAITFOR DELAY within TRAN | HIGH | Wastes transaction time | Move delay outside transaction |
| Nested BEGIN TRAN (@@trancount > 1) | MEDIUM | Spanner has no nested transactions | Flatten to single transaction boundary |
| Cross-database TRAN | HIGH | Spanner transactions are single-database | Consolidate schemas or use saga pattern |
