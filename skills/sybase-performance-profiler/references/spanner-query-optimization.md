# Spanner Query Optimization Reference

Best practices for Cloud Spanner schema design, query optimization, and performance tuning informed by Sybase workload profiling.

## Primary Key Selection for Distribution

Spanner distributes data across splits based on the primary key. Poor key design causes hotspots where one split handles disproportionate load.

### Anti-Pattern: Monotonically Increasing Keys

```sql
-- BAD: Sequential integer causes all inserts to go to the same split
CREATE TABLE orders (
    order_id INT64 NOT NULL,  -- 1, 2, 3, 4, ... all go to last split
    ...
) PRIMARY KEY (order_id);
```

### Solution 1: UUID Primary Keys

```sql
-- GOOD: UUIDs distribute evenly across splits
CREATE TABLE orders (
    order_id STRING(36) NOT NULL DEFAULT (GENERATE_UUID()),
    ...
) PRIMARY KEY (order_id);
```

### Solution 2: Bit-Reversed Sequential IDs

If the application requires sequential IDs for business logic:

```python
# Application-side bit reversal
def bit_reverse(n, bits=64):
    result = 0
    for i in range(bits):
        result = (result << 1) | (n & 1)
        n >>= 1
    return result

# order_id = 1 → large scattered number
# order_id = 2 → different large scattered number
```

### Solution 3: Composite Key with High-Cardinality Prefix

```sql
-- GOOD: Symbol as prefix distributes across many splits
CREATE TABLE market_prices (
    symbol STRING(20) NOT NULL,
    price_time TIMESTAMP NOT NULL,
    price NUMERIC,
) PRIMARY KEY (symbol, price_time);
-- Different symbols go to different splits
```

### Solution 4: Shard ID Prefix

```sql
-- GOOD: Explicit shard distributes writes
CREATE TABLE audit_trail (
    shard_id INT64 NOT NULL,  -- hash(event_source) % 10
    event_time TIMESTAMP NOT NULL,
    audit_id STRING(36) NOT NULL DEFAULT (GENERATE_UUID()),
    ...
) PRIMARY KEY (shard_id, event_time, audit_id);
```

---

## Secondary Index Design

### Basic Secondary Index

```sql
-- Index for looking up orders by client
CREATE INDEX idx_orders_by_client ON orders(client_id);
```

**When to use:** Queries that filter on a non-primary-key column where the result set is small relative to the table.

### STORING Clause (Covered Queries)

The STORING clause includes additional columns in the index, enabling index-only scans without a back-join to the base table.

```sql
-- Without STORING: query needs back-join
CREATE INDEX idx_orders_by_client ON orders(client_id);
-- SELECT order_id, symbol, quantity FROM orders WHERE client_id = 123
-- → index lookup for matching rows + back-join to base table for symbol, quantity

-- With STORING: covered query, no back-join
CREATE INDEX idx_orders_by_client ON orders(client_id)
    STORING (symbol, quantity, order_time, status);
-- SELECT order_id, symbol, quantity FROM orders WHERE client_id = 123
-- → index-only scan, all columns available in index
```

**When to use STORING:**
- Query accesses the same set of columns >80% of the time
- Back-join latency is unacceptable for the use case
- Additional storage cost is justified by query frequency

**Tradeoff:** Each STORING column increases index storage and write amplification (every INSERT/UPDATE must update the index entry).

### NULL_FILTERED Indexes

```sql
-- Only index non-null values (reduces index size)
CREATE NULL_FILTERED INDEX idx_orders_active
    ON orders(status)
    STORING (client_id, symbol);
-- Only rows where status IS NOT NULL are indexed
-- Useful when most rows have NULL for the indexed column
```

**When to use:** Columns where NULL is the common case and queries only care about non-null values (e.g., `assigned_worker` on a queue table).

### Descending Key Indexes

```sql
-- For "latest N" queries
CREATE INDEX idx_orders_by_time_desc
    ON orders(order_time DESC)
    STORING (symbol, quantity, status);
-- SELECT * FROM orders ORDER BY order_time DESC LIMIT 10
-- → efficient index scan from the end
```

### Composite Indexes (Multi-Column)

```sql
-- For multi-predicate queries
CREATE INDEX idx_orders_symbol_date
    ON orders(symbol, order_time DESC)
    STORING (quantity, price, status);
-- SELECT * FROM orders WHERE symbol = 'AAPL' ORDER BY order_time DESC LIMIT 100
-- → single index range scan
```

**Column ordering rules:**
1. Equality predicates first (`symbol = 'AAPL'`)
2. Range/inequality predicates next (`order_time > '2024-01-01'`)
3. ORDER BY columns last (matching sort direction)

---

## Interleaved Table Access Patterns

### When to Interleave

Interleave child tables with parent when:
- Queries frequently join parent + child (`orders` + `fills`)
- Child rows are always accessed in context of parent
- Parent-child cardinality is manageable (< 10K children per parent)
- Delete patterns align (cascade or no orphans)

### DDL Pattern

```sql
CREATE TABLE orders (
    order_id INT64 NOT NULL,
    client_id INT64 NOT NULL,
    symbol STRING(20),
    quantity NUMERIC,
    price NUMERIC,
    status STRING(10),
    order_time TIMESTAMP NOT NULL,
) PRIMARY KEY (order_id);

CREATE TABLE fills (
    order_id INT64 NOT NULL,
    fill_id INT64 NOT NULL,
    fill_price NUMERIC,
    fill_quantity NUMERIC,
    fill_time TIMESTAMP NOT NULL,
) PRIMARY KEY (order_id, fill_id),
  INTERLEAVE IN PARENT orders ON DELETE CASCADE;

CREATE TABLE order_audit (
    order_id INT64 NOT NULL,
    audit_seq INT64 NOT NULL,
    event_type STRING(20),
    details STRING(MAX),
    event_time TIMESTAMP NOT NULL,
) PRIMARY KEY (order_id, audit_seq),
  INTERLEAVE IN PARENT orders ON DELETE CASCADE;
```

### Storage Layout

Interleaved data is physically co-located:

```
Split contents (conceptual):
  orders row: order_id=1001, symbol=AAPL, qty=100
    fills row: order_id=1001, fill_id=1, price=150.25
    fills row: order_id=1001, fill_id=2, price=150.30
    order_audit row: order_id=1001, audit_seq=1, event=CREATED
    order_audit row: order_id=1001, audit_seq=2, event=FILLED
  orders row: order_id=1002, symbol=GOOG, qty=50
    fills row: order_id=1002, fill_id=1, price=140.00
```

### When NOT to Interleave

- Child table is accessed independently of parent (e.g., `fills` queried by `symbol` without `order_id`)
- Very high child cardinality (>100K per parent) causing split imbalance
- Different lifecycle (child outlives parent)
- Different access frequency (child accessed 100x more than parent)

---

## Stale Reads

### Exact Staleness

Read data as of a specific time in the past. Guaranteed to not block on writes.

```python
import datetime

# Read data that may be up to 15 seconds old
with database.snapshot(exact_staleness=datetime.timedelta(seconds=15)) as snapshot:
    results = snapshot.execute_sql(
        "SELECT symbol, price FROM market_prices WHERE symbol = 'AAPL'")
```

**Use cases:**
- Dashboard/monitoring displays (10-15s staleness)
- Analytics queries (30-60s staleness)
- Cache warming (any staleness)

### Max Staleness

Read data that is at most N seconds old. May read from nearest replica.

```python
# Read from nearest replica, data at most 30 seconds old
with database.snapshot(max_staleness=datetime.timedelta(seconds=30)) as snapshot:
    results = snapshot.execute_sql("SELECT COUNT(*) FROM orders WHERE status = 'OPEN'")
```

**Use cases:**
- Approximate counts for UI
- Non-critical reporting
- Global deployments (read from local replica)

### Strong Reads

Default behavior. Reads the latest committed data.

```python
# Strong read (default) - latest committed data
with database.snapshot() as snapshot:
    results = snapshot.execute_sql(
        "SELECT balance FROM accounts WHERE account_id = 'ACC001'")
```

**Use cases:**
- Financial calculations requiring exact values
- Regulatory reporting
- Settlement processing

---

## Query Statistics and Execution Plans

### Query Statistics Tables

```sql
-- Enable query statistics
ALTER DATABASE db SET OPTIONS (
    optimizer_statistics_package = 'latest'
);

-- Query the statistics
SELECT * FROM SPANNER_SYS.QUERY_STATS_TOP_MINUTE
ORDER BY avg_latency_seconds DESC;

-- Columns available:
-- text, text_truncated, text_fingerprint
-- execution_count, avg_latency_seconds, avg_rows_returned
-- avg_bytes_returned, avg_rows_scanned, avg_cpu_seconds
```

### Execution Plan Analysis

```sql
-- Get execution plan (without executing)
@{EXPLAIN} SELECT o.order_id, f.fill_price
FROM orders o
JOIN fills f ON o.order_id = f.order_id
WHERE o.client_id = 123;
```

**Key plan operators to look for:**

| Operator | Meaning | Optimization |
|----------|---------|-------------|
| `Table Scan` | Full table scan | Add index or restructure query |
| `Index Scan` | Full index scan | May need more selective predicate |
| `Index Seek` | Targeted index lookup | Good - efficient |
| `Distributed Union` | Query across splits | Normal for large tables |
| `Cross Apply` | Nested loop join | Check if interleaving would help |
| `Hash Join` | Hash-based join | OK for large joins |
| `Sort` | Explicit sorting | Check if index can provide order |
| `Filter` | Post-scan filtering | Check if predicate can be pushed to index |

### Optimizer Hints

```sql
-- Force a specific index
@{FORCE_INDEX=idx_orders_by_client}
SELECT * FROM orders WHERE client_id = 123;

-- Force a join type
SELECT /*@ JOIN_METHOD=HASH_JOIN */
    o.*, f.*
FROM orders o
JOIN fills f ON o.order_id = f.order_id;

-- Specify join order
SELECT /*@ JOIN_ORDER=(orders, fills, settlements) */
    ...
FROM orders o
JOIN fills f ON o.order_id = f.order_id
JOIN settlements s ON o.order_id = s.order_id;

-- Group by optimization
SELECT /*@ GROUPBY_SCAN_OPTIMIZATION=true */
    symbol, COUNT(*)
FROM orders
GROUP BY symbol;
```

**Use hints sparingly:** Optimizer hints override the query optimizer's decisions. Only use when you have verified that the optimizer's default plan is suboptimal for your specific data distribution and access pattern.

---

## Financial Workload Optimization Checklist

| Check | Table/Query | Action |
|-------|------------|--------|
| No monotonic PKs | orders, fills, audit_trail | Use UUID or bit-reversed keys |
| Interleave parent-child | orders→fills, books→positions | Apply INTERLEAVE IN PARENT |
| STORING on frequent indexes | idx_orders_by_client | Add frequently queried columns |
| Stale reads for dashboards | market_prices, position_summary | Configure 10-15s staleness |
| Read-only transactions | portfolio views, reports | Switch from read-write to read-only |
| Partitioned DML for batches | EOD settlement updates | Use execute_partitioned_dml |
| Commit timestamps for audit | audit_trail, change_log | Add PENDING_COMMIT_TIMESTAMP() |
| NULL_FILTERED for sparse cols | assigned_worker, processed_by | Reduce index size |
| Descending key for recency | latest orders, recent trades | ORDER BY ... DESC in index |
| Node autoscaling | Market open/close bursts | Configure min/max/target CPU |
