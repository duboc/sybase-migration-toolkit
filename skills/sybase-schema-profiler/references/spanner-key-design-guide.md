# Spanner Key Design Guide for Sybase Migration

Reference guide for designing Cloud Spanner primary keys and interleaved tables when migrating from Sybase ASE.

## The Hotspot Problem

Spanner distributes data across splits based on primary key ranges. Monotonically increasing keys (sequential integers, auto-increment IDENTITY, timestamps) cause all new writes to concentrate on a single split, creating a write hotspot.

**Sybase patterns that cause Spanner hotspots:**

| Sybase Pattern | Why It Hotspots | Frequency in Financial Apps |
|---------------|----------------|----------------------------|
| `IDENTITY` column as PK | Sequential values: 1, 2, 3, ... all go to the same split tail | Very common — most transaction tables |
| `DATETIME` as leading PK column | Chronological data always writes to the latest time range | Common — audit logs, price history |
| Sequential counter tables | `SELECT MAX(id) + 1` pattern | Common — legacy order numbering |
| Date-partitioned keys | `(trade_date, sequence)` — all today's trades go to one split | Common — daily batch processing |

## Key Design Strategies

### Strategy 1: Bit-Reversed Sequences (Recommended for IDENTITY replacement)

Spanner's `BIT_REVERSED_POSITIVE` sequence generates values that are uniformly distributed across the key space by bit-reversing a monotonic counter.

```sql
-- Create a bit-reversed sequence
CREATE SEQUENCE trade_seq OPTIONS (
    sequence_kind = 'bit_reversed_positive'
);

-- Use in table definition
CREATE TABLE trades (
    trade_id    INT64 DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE trade_seq)),
    account_id  INT64 NOT NULL,
    trade_date  TIMESTAMP NOT NULL,
    instrument  STRING(20) NOT NULL,
    quantity    INT64,
    price       NUMERIC
) PRIMARY KEY (trade_id);
```

**Characteristics:**
- Values are INT64, not sequential (e.g., 4611686018427387904, 2305843009213693952, ...)
- Uniformly distributed across key space
- Globally unique within the sequence
- Applications must NOT assume ordering or contiguity
- Ideal for replacing Sybase IDENTITY columns

### Strategy 2: UUID Primary Keys

Use V4 UUIDs for maximum distribution when keys must be generated client-side.

```sql
CREATE TABLE orders (
    order_id    STRING(36) DEFAULT (GENERATE_UUID()),
    customer_id INT64 NOT NULL,
    order_date  TIMESTAMP NOT NULL,
    status      STRING(20)
) PRIMARY KEY (order_id);
```

**Characteristics:**
- 36-character string storage (larger than INT64)
- Client-generated — no sequence contention
- Excellent distribution
- Not human-readable or sortable
- Best for: distributed systems where multiple clients create records

### Strategy 3: Hash-Prefixed Keys

Prepend a hash of the natural key to distribute writes while preserving the natural key.

```sql
CREATE TABLE market_prices (
    shard_id      INT64 NOT NULL,  -- MOD(FARM_FINGERPRINT(instrument_id), 1000)
    instrument_id STRING(20) NOT NULL,
    price_date    DATE NOT NULL,
    close_price   NUMERIC,
    volume        INT64
) PRIMARY KEY (shard_id, instrument_id, price_date);
```

**Characteristics:**
- Requires application logic to compute shard_id
- Point lookups need the shard_id (or scan all shards)
- Range scans within an instrument still efficient (within a shard)
- Best for: high-write tables where you also need range scans by natural key

### Strategy 4: Composite Natural Keys

Use existing high-cardinality business keys that naturally distribute well.

```sql
CREATE TABLE positions (
    account_id    INT64 NOT NULL,
    instrument_id STRING(20) NOT NULL,
    position_date DATE NOT NULL,
    quantity      INT64,
    avg_cost      NUMERIC,
    market_value  NUMERIC
) PRIMARY KEY (account_id, instrument_id, position_date);
```

**Characteristics:**
- No synthetic key needed
- account_id distributes well if many accounts
- Efficient range scans by account
- Best for: tables with natural composite keys (account + instrument, portfolio + date)

## Interleaved Table Design

Interleaving co-locates child rows with their parent row on the same Spanner split. This makes parent-child joins extremely efficient (no cross-split reads).

### When to Interleave

| Interleave | Don't Interleave |
|-----------|-----------------|
| Parent and child are always queried together | Child table is queried independently (without parent context) |
| 1:many relationship with bounded fan-out | Very high fan-out (millions of children per parent) |
| Child is meaningless without parent context | Child is a shared reference/lookup table |
| Both tables have similar write patterns | Write patterns are very different (batch vs real-time) |

### Interleaving Syntax

```sql
-- Parent table
CREATE TABLE accounts (
    account_id   INT64 NOT NULL,
    account_name STRING(100),
    account_type STRING(20),
    currency     STRING(3)
) PRIMARY KEY (account_id);

-- Child table interleaved in parent
CREATE TABLE transactions (
    account_id      INT64 NOT NULL,
    transaction_id  INT64 NOT NULL,
    transaction_date TIMESTAMP NOT NULL,
    amount          NUMERIC,
    description     STRING(200)
) PRIMARY KEY (account_id, transaction_id),
  INTERLEAVE IN PARENT accounts ON DELETE CASCADE;
```

**Rules:**
- Child PK must start with the parent PK columns (prefix requirement)
- Maximum 7 levels of interleaving depth
- `ON DELETE CASCADE`: deleting parent deletes all children
- `ON DELETE NO ACTION`: cannot delete parent if children exist

### Financial Domain Interleaving Recommendations

```
accounts
  ├── transactions          (INTERLEAVE, ON DELETE CASCADE)
  ├── balances              (INTERLEAVE, ON DELETE CASCADE)
  └── account_audit         (INTERLEAVE, ON DELETE CASCADE)

portfolios
  ├── positions             (INTERLEAVE, ON DELETE NO ACTION)
  │   └── position_history  (INTERLEAVE, ON DELETE CASCADE)
  └── portfolio_returns     (INTERLEAVE, ON DELETE CASCADE)

orders
  ├── order_items           (INTERLEAVE, ON DELETE CASCADE)
  └── order_status_history  (INTERLEAVE, ON DELETE CASCADE)

trades
  ├── trade_allocations     (INTERLEAVE, ON DELETE CASCADE)
  ├── trade_confirmations   (INTERLEAVE, ON DELETE CASCADE)
  └── trade_settlements     (INTERLEAVE, ON DELETE CASCADE)
```

**Do NOT interleave these (use foreign keys instead):**

| Table | Reason |
|-------|--------|
| `instruments` / `securities` | Referenced by many tables; queried independently for reference data |
| `counterparties` | Shared reference; queried independently |
| `currencies` | Lookup table; very small, queried from many contexts |
| `exchange_rates` | Time-series data queried independently |
| `users` / `traders` | Referenced across many domains |

### Interleaving Depth Example (Financial)

```
Level 1: accounts (root)
  Level 2: portfolios (INTERLEAVE IN accounts)
    Level 3: positions (INTERLEAVE IN portfolios)
      Level 4: position_history (INTERLEAVE IN positions)
        Level 5: position_adjustments (INTERLEAVE IN position_history)
```

Maximum 7 levels allowed. Financial schemas rarely need more than 4-5.

## Commit Timestamp Columns

Spanner can automatically set a column to the commit timestamp when a row is written. Useful for audit trails.

```sql
CREATE TABLE account_audit (
    account_id    INT64 NOT NULL,
    audit_id      INT64 NOT NULL,
    change_type   STRING(10),   -- INSERT, UPDATE, DELETE
    changed_by    STRING(50),
    changed_at    TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
    old_values    JSON,
    new_values    JSON
) PRIMARY KEY (account_id, audit_id),
  INTERLEAVE IN PARENT accounts ON DELETE CASCADE;

-- Insert with commit timestamp
INSERT INTO account_audit (account_id, audit_id, change_type, changed_by, changed_at)
VALUES (123, 456, 'UPDATE', 'system', PENDING_COMMIT_TIMESTAMP());
```

**Notes:**
- `PENDING_COMMIT_TIMESTAMP()` sets the value to the exact commit time
- Column must have `OPTIONS (allow_commit_timestamp = true)`
- Commit timestamp columns should NOT be the leading PK column (hotspot risk)
- Use as trailing column in composite keys: `(account_id, changed_at)` is fine

## Migration Checklist

- [ ] All IDENTITY columns replaced with `BIT_REVERSED_POSITIVE` sequences
- [ ] No monotonically increasing values as leading PK column
- [ ] Parent-child relationships evaluated for interleaving
- [ ] Interleaved hierarchies do not exceed 7 levels
- [ ] Reference/lookup tables use foreign keys (not interleaving)
- [ ] Commit timestamp columns defined for audit trail tables
- [ ] Secondary indexes reviewed for STORING clause optimization
- [ ] Application code updated to not assume sequential key ordering
- [ ] Batch insert operations validated against 80,000 mutation limit
