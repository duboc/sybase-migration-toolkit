# Spanner Schema Design Patterns

This reference provides Cloud Spanner schema design patterns, anti-patterns, and decision matrices for designing optimal schemas from Sybase source schemas.

## Interleaved Table Design Patterns

### Parent-Child Interleaving

Interleaved tables are physically co-located on the same Spanner splits, providing single-split reads for parent + children queries.

**When to interleave:**
- Parent and child are always queried together
- Child rows are meaningless without parent context
- Access pattern is "get parent and all its children"
- One-to-many relationship with moderate fanout (<10,000 children per parent)

**When NOT to interleave:**
- Child table is frequently queried independently (without parent context)
- Very high fanout (>10,000 children per parent) -- can create hot splits
- Many-to-many relationship (use a link/junction table instead)
- Tables in different bounded contexts accessed by different services

### Maximum Depth

Spanner supports up to 7 levels of interleaving. Recommended maximum for practical use:

| Depth | Use Case | Example |
|-------|---------|---------|
| 1 | Simple parent-child | accounts -> transactions |
| 2 | Three-level hierarchy | orders -> fills -> allocations |
| 3 | Deep hierarchy | entities -> accounts -> transactions -> details |
| 4+ | Rarely needed | Consider flattening or separate tables with FKs |

### Cascade Rules

| Rule | Behavior | Financial Use |
|------|----------|--------------|
| ON DELETE CASCADE | Deleting parent auto-deletes children | NEVER for financial records |
| ON DELETE NO ACTION | Prevent parent deletion if children exist | ALWAYS for financial records |

**Financial data rule**: Always use ON DELETE NO ACTION. Financial records (trades, transactions, positions) must never be cascade-deleted. Deletion should be explicit and audited.

### Interleaving Decision Matrix

| Factor | Interleave | FK Only | No Relationship |
|--------|-----------|---------|----------------|
| Co-access frequency | >80% co-accessed | <50% co-accessed | Independent access |
| Transaction scope | Same transaction | Occasional same txn | Different transactions |
| Query locality | Point lookup parent+children | Join across tables | No join pattern |
| Fanout | 1-10,000 children | >10,000 children | N/A |
| Independent query | Rare | Frequent | Always |
| Bounded context | Same service | Same or different | Different services |

## Key Design Patterns

### BIT_REVERSED_POSITIVE Sequences

The primary strategy for replacing Sybase IDENTITY columns:

```sql
CREATE SEQUENCE seq_trade_id
  OPTIONS (
    sequence_kind = 'bit_reversed_positive',
    start_with_counter = 1,
    skip_range_min = 1,
    skip_range_max = 10000000  -- Reserve range for migration backfill
  );
```

**How it works:**
- Counter increments internally (1, 2, 3, ...)
- Output is bit-reversed (avoids monotonic distribution)
- Values spread across keyspace (prevents write hotspots)
- Unique and non-negative
- skip_range reserves IDs for migrating existing data with original values

### Key Design Anti-Patterns

| Anti-Pattern | Problem | Solution |
|-------------|---------|---------|
| Monotonic INT/BIGINT key | Write hotspot on last split | BIT_REVERSED_POSITIVE sequence |
| Timestamp-only primary key | Write hotspot at current time | Prepend entity ID or hash prefix |
| Auto-increment starting at 1 | Hotspot on split containing key 1 | Bit-reversed sequence |
| Sequential composite key (date, seq) | Hotspot on current date partition | Reverse key order or add hash |
| Low-cardinality first key column | Poor distribution across splits | Use high-cardinality column first |
| UUIDv1 (time-based) | Contains timestamp prefix, still monotonic | Use UUIDv4 (random) |

### Composite Key Ordering

```sql
-- GOOD: High-cardinality column first
CREATE TABLE transactions (
  account_id INT64 NOT NULL,      -- High cardinality, distributes writes
  transaction_id INT64 NOT NULL,  -- Sequence within account
) PRIMARY KEY (account_id, transaction_id);

-- BAD: Low-cardinality or monotonic column first
-- CREATE TABLE transactions (
--   transaction_date DATE NOT NULL,   -- Monotonic, creates hotspot
--   transaction_id INT64 NOT NULL,
-- ) PRIMARY KEY (transaction_date, transaction_id);
```

## Commit Timestamp Usage

### Purpose
- Provides server-side transaction commit time
- Guaranteed unique and monotonically increasing
- Essential for audit trails and change tracking

### Configuration

```sql
-- Column definition
spanner_commit_ts TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true)

-- Insert with commit timestamp
INSERT INTO audit_trail (audit_id, entity_type, entity_id, action, spanner_commit_ts)
VALUES (123, 'TRADE', 456, 'BOOK', PENDING_COMMIT_TIMESTAMP());

-- Read commit timestamp
SELECT * FROM audit_trail WHERE spanner_commit_ts > @last_read_ts;
```

### Constraints
- Column must have `allow_commit_timestamp = true` option
- Value must be `PENDING_COMMIT_TIMESTAMP()` in DML or `Value.COMMIT_TIMESTAMP` in mutations
- Cannot be used as primary key (monotonic, causes hotspot)
- Read of commit timestamp returns actual commit time after transaction completes

### Financial Audit Use Cases
- Trade execution timestamp (when exactly was the trade committed to Spanner)
- Position update timestamp (for point-in-time position reconstruction)
- Balance change timestamp (for reconciliation and audit trail)
- Configuration change timestamp (for change management audit)

## TTL Configuration (Row Deletion Policy)

```sql
-- Auto-delete rows after expiration
CREATE TABLE user_sessions (
  session_id STRING(36) NOT NULL,
  user_id INT64,
  expires_at TIMESTAMP NOT NULL,
  session_data JSON,
) PRIMARY KEY (session_id),
ROW DELETION POLICY (OLDER_THAN(expires_at, INTERVAL 0 DAY));

-- TTL with buffer period (delete 30 days after expiry)
CREATE TABLE temp_calculations (
  calc_id INT64 NOT NULL,
  result JSON,
  created_at TIMESTAMP NOT NULL,
) PRIMARY KEY (calc_id),
ROW DELETION POLICY (OLDER_THAN(created_at, INTERVAL 30 DAY));
```

**When to use TTL:**
- Session data
- Temporary calculation results
- Cache entries
- Staging data for ETL
- Short-lived notifications

**When NOT to use TTL:**
- Financial transaction records (regulatory retention)
- Audit trail entries (SOX 7-year retention)
- Trade history (compliance requirement)
- Position snapshots (reconstruction requirement)

## Change Stream Setup

### Configuration

```sql
CREATE CHANGE STREAM cs_name
FOR table1, table2(column1, column2)  -- Specific tables/columns
OPTIONS (
  retention_period = '7d',           -- How long to retain change records
  value_capture_type = 'NEW_AND_OLD_VALUES'  -- or 'NEW_VALUES', 'OLD_VALUES'
);
```

### Value Capture Types

| Type | Captures | Use Case | Storage Impact |
|------|---------|---------|---------------|
| NEW_VALUES | Only new column values | CDC to BigQuery (append) | Lower |
| OLD_AND_NEW_VALUES | Both old and new values | Audit, change tracking | Higher |
| NEW_ROW | Full new row | Simple CDC | Medium |
| OLD_AND_NEW_VALUES | Full old and new rows | Compliance audit | Highest |

### Watched Tables Decision

| Criterion | Watch | Don't Watch |
|----------|-------|------------|
| Has downstream consumers | Yes | -- |
| Replicated in Sybase | Yes (replacement) | -- |
| Analytics copy needed | Yes (CDC to BigQuery) | -- |
| High-write ephemeral data | -- | No (TTL data, sessions) |
| Static reference data | -- | No (rarely changes) |
| Dead/excluded tables | -- | No (not in scope) |

### Retention Period

- Minimum: 1 day
- Maximum: 7 days
- Recommended: Match downstream processing SLA + buffer
- Example: If Dataflow pipeline has 1-hour SLA with 4-hour recovery, set retention to 3 days

## Foreign Key vs Interleaving Decision Matrix

| Scenario | Use Interleaving | Use FK Only | Use Both |
|----------|-----------------|------------|---------|
| Parent-child, always co-accessed | Yes | -- | Optional FK for integrity |
| Cross-context reference | -- | Yes | -- |
| Self-referencing hierarchy | -- | Yes | -- |
| Many-to-many (via junction) | Interleave junction in one parent | FK to other parent | Yes (both) |
| Lookup/reference table | -- | Yes | -- |
| High-fanout (>10K children) | -- | Yes | -- |

## Spanner Graph Schema Design

For complex entity relationship networks, consider Spanner Graph:

```sql
-- Define graph schema for counterparty relationships
CREATE PROPERTY GRAPH FinancialEntityGraph
  NODE TABLES (
    entities,
    accounts,
    instruments
  )
  EDGE TABLES (
    account_relationships
      SOURCE KEY (from_account_id) REFERENCES accounts (account_id)
      DESTINATION KEY (to_account_id) REFERENCES accounts (account_id),
    entity_instrument_holdings
      SOURCE KEY (entity_id) REFERENCES entities (entity_id)
      DESTINATION KEY (instrument_id) REFERENCES instruments (instrument_id)
  );
```

**Use cases for Graph in financial domain:**
- Counterparty relationship networks
- Beneficial ownership chains
- Transaction flow analysis (AML)
- Inter-company exposure mapping
- Instrument dependency graphs (e.g., CDO underlying assets)
