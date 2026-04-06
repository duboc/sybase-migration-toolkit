# Financial Schema Templates for Cloud Spanner

This reference provides Spanner DDL templates for common financial domain schemas, demonstrating interleaving, key design, commit timestamps, and Change Stream patterns.

## Trade Lifecycle Schema

Models the full trade lifecycle: order -> execution (fill) -> allocation -> settlement.

```sql
-- Sequences
CREATE SEQUENCE seq_order_id OPTIONS (
  sequence_kind = 'bit_reversed_positive',
  skip_range_min = 1, skip_range_max = 50000000
);
CREATE SEQUENCE seq_fill_id OPTIONS (
  sequence_kind = 'bit_reversed_positive',
  skip_range_min = 1, skip_range_max = 100000000
);
CREATE SEQUENCE seq_allocation_id OPTIONS (
  sequence_kind = 'bit_reversed_positive',
  skip_range_min = 1, skip_range_max = 100000000
);
CREATE SEQUENCE seq_settlement_id OPTIONS (
  sequence_kind = 'bit_reversed_positive',
  skip_range_min = 1, skip_range_max = 50000000
);

-- Parent: Orders
CREATE TABLE orders (
  order_id INT64 NOT NULL DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE seq_order_id)),
  account_id INT64 NOT NULL,
  instrument_id INT64 NOT NULL,
  order_type STRING(20) NOT NULL,   -- MARKET, LIMIT, STOP, etc.
  side STRING(4) NOT NULL,          -- BUY, SELL, SHRT, COVR
  quantity NUMERIC NOT NULL,
  limit_price NUMERIC,
  stop_price NUMERIC,
  time_in_force STRING(10),         -- DAY, GTC, IOC, FOK
  status STRING(20) NOT NULL,       -- NEW, PARTIAL, FILLED, CANCELLED
  order_date TIMESTAMP NOT NULL,
  expire_date TIMESTAMP,
  cancel_reason STRING(200),
  trader_id INT64 NOT NULL,
  desk_id INT64,
  created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
  updated_at TIMESTAMP OPTIONS (allow_commit_timestamp = true),
) PRIMARY KEY (order_id);

-- Child: Fills (interleaved in orders)
CREATE TABLE fills (
  order_id INT64 NOT NULL,
  fill_id INT64 NOT NULL DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE seq_fill_id)),
  fill_quantity NUMERIC NOT NULL,
  fill_price NUMERIC NOT NULL,
  fill_amount NUMERIC NOT NULL,    -- quantity * price
  counterparty_id INT64,
  exchange_id INT64,
  execution_venue STRING(50),       -- Exchange code or OTC
  fill_date TIMESTAMP NOT NULL,
  settlement_date DATE NOT NULL,
  commission NUMERIC,
  fees NUMERIC,
  created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
) PRIMARY KEY (order_id, fill_id),
  INTERLEAVE IN PARENT orders ON DELETE NO ACTION;

-- Grandchild: Allocations (interleaved in fills)
CREATE TABLE allocations (
  order_id INT64 NOT NULL,
  fill_id INT64 NOT NULL,
  allocation_id INT64 NOT NULL DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE seq_allocation_id)),
  target_account_id INT64 NOT NULL,
  allocated_quantity NUMERIC NOT NULL,
  allocated_amount NUMERIC NOT NULL,
  allocation_pct NUMERIC,           -- Percentage of fill
  status STRING(20) NOT NULL,       -- PENDING, CONFIRMED, SETTLED
  created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
) PRIMARY KEY (order_id, fill_id, allocation_id),
  INTERLEAVE IN PARENT fills ON DELETE NO ACTION;

-- Settlement (separate table, FK to allocations)
CREATE TABLE settlements (
  settlement_id INT64 NOT NULL DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE seq_settlement_id)),
  order_id INT64 NOT NULL,
  fill_id INT64 NOT NULL,
  allocation_id INT64 NOT NULL,
  settlement_date DATE NOT NULL,
  settlement_amount NUMERIC NOT NULL,
  settlement_currency STRING(3) NOT NULL,
  status STRING(20) NOT NULL,        -- PENDING, MATCHED, SETTLED, FAILED
  custodian_id INT64,
  depository_ref STRING(50),
  failed_reason STRING(500),
  created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
  updated_at TIMESTAMP OPTIONS (allow_commit_timestamp = true),
) PRIMARY KEY (settlement_id);

-- Indexes for trade lifecycle
CREATE INDEX ix_orders_account ON orders (account_id, order_date DESC)
  STORING (instrument_id, side, quantity, status, order_type);
CREATE INDEX ix_orders_instrument ON orders (instrument_id, order_date DESC)
  STORING (account_id, side, quantity, status);
CREATE INDEX ix_orders_status ON orders (status, order_date DESC)
  STORING (account_id, instrument_id, side, quantity);
CREATE NULL_FILTERED INDEX ix_orders_cancel ON orders (cancel_reason)
  STORING (order_id, account_id, status);
CREATE INDEX ix_settlements_date ON settlements (settlement_date, status)
  STORING (settlement_amount, settlement_currency);

-- Change Stream for trade lifecycle
CREATE CHANGE STREAM cs_trade_lifecycle
FOR orders, fills, allocations, settlements
OPTIONS (
  retention_period = '7d',
  value_capture_type = 'NEW_AND_OLD_VALUES'
);
```

## Position Keeping Schema

Models portfolio positions with commit timestamps for point-in-time reconstruction.

```sql
-- Sequences
CREATE SEQUENCE seq_portfolio_id OPTIONS (
  sequence_kind = 'bit_reversed_positive',
  skip_range_min = 1, skip_range_max = 1000000
);
CREATE SEQUENCE seq_position_id OPTIONS (
  sequence_kind = 'bit_reversed_positive',
  skip_range_min = 1, skip_range_max = 10000000
);

-- Parent: Portfolios
CREATE TABLE portfolios (
  portfolio_id INT64 NOT NULL DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE seq_portfolio_id)),
  portfolio_name STRING(100) NOT NULL,
  portfolio_type STRING(20) NOT NULL,  -- TRADING, INVESTMENT, HEDGE, CLIENT
  entity_id INT64 NOT NULL,
  base_currency STRING(3) NOT NULL,
  benchmark_id INT64,
  inception_date DATE NOT NULL,
  status STRING(10) NOT NULL,          -- ACTIVE, CLOSED, SUSPENDED
  manager_id INT64,
  created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
  updated_at TIMESTAMP OPTIONS (allow_commit_timestamp = true),
) PRIMARY KEY (portfolio_id);

-- Child: Positions (interleaved in portfolios)
CREATE TABLE positions (
  portfolio_id INT64 NOT NULL,
  instrument_id INT64 NOT NULL,
  quantity NUMERIC NOT NULL,
  avg_cost NUMERIC NOT NULL,
  cost_basis NUMERIC NOT NULL,         -- quantity * avg_cost
  unrealized_pnl NUMERIC,
  realized_pnl NUMERIC NOT NULL DEFAULT (0),
  market_value NUMERIC,
  accrued_interest NUMERIC,
  currency STRING(3) NOT NULL,
  lot_method STRING(10),               -- FIFO, LIFO, AVG, SPECIFIC
  first_trade_date DATE,
  last_trade_date DATE,
  created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
  updated_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
) PRIMARY KEY (portfolio_id, instrument_id),
  INTERLEAVE IN PARENT portfolios ON DELETE NO ACTION;

-- Position history for point-in-time reconstruction
CREATE TABLE position_history (
  portfolio_id INT64 NOT NULL,
  instrument_id INT64 NOT NULL,
  snapshot_date DATE NOT NULL,
  quantity NUMERIC NOT NULL,
  avg_cost NUMERIC NOT NULL,
  market_value NUMERIC,
  unrealized_pnl NUMERIC,
  realized_pnl NUMERIC,
  spanner_commit_ts TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
) PRIMARY KEY (portfolio_id, instrument_id, snapshot_date DESC),
  INTERLEAVE IN PARENT portfolios ON DELETE NO ACTION;

-- Indexes
CREATE INDEX ix_positions_instrument ON positions (instrument_id)
  STORING (quantity, market_value, unrealized_pnl);
CREATE INDEX ix_position_history_date ON position_history (snapshot_date DESC, portfolio_id)
  STORING (quantity, market_value),
  INTERLEAVE IN portfolios;

-- Change Stream for positions (CDC to BigQuery for analytics)
CREATE CHANGE STREAM cs_positions
FOR positions
OPTIONS (
  retention_period = '7d',
  value_capture_type = 'NEW_AND_OLD_VALUES'
);
```

## Account Hierarchy Schema

Models entity -> account -> sub-account with interleaving for co-located access.

```sql
-- Sequences
CREATE SEQUENCE seq_entity_id OPTIONS (
  sequence_kind = 'bit_reversed_positive',
  skip_range_min = 1, skip_range_max = 1000000
);
CREATE SEQUENCE seq_account_id OPTIONS (
  sequence_kind = 'bit_reversed_positive',
  skip_range_min = 1, skip_range_max = 5000000
);
CREATE SEQUENCE seq_sub_account_id OPTIONS (
  sequence_kind = 'bit_reversed_positive',
  skip_range_min = 1, skip_range_max = 10000000
);
CREATE SEQUENCE seq_transaction_id OPTIONS (
  sequence_kind = 'bit_reversed_positive',
  skip_range_min = 1, skip_range_max = 500000000
);

-- Parent: Entities (legal entities, corporations, individuals)
CREATE TABLE entities (
  entity_id INT64 NOT NULL DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE seq_entity_id)),
  entity_name STRING(200) NOT NULL,
  entity_type STRING(20) NOT NULL,     -- CORPORATION, INDIVIDUAL, TRUST, FUND
  tax_id STRING(50),                   -- Encrypted or tokenized
  domicile_country STRING(2),
  incorporation_date DATE,
  status STRING(10) NOT NULL,
  kyc_status STRING(20),               -- PENDING, APPROVED, EXPIRED
  kyc_expiry_date DATE,
  created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
  updated_at TIMESTAMP OPTIONS (allow_commit_timestamp = true),
) PRIMARY KEY (entity_id);

-- Child: Accounts (interleaved in entities)
CREATE TABLE accounts (
  entity_id INT64 NOT NULL,
  account_id INT64 NOT NULL DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE seq_account_id)),
  account_number STRING(20) NOT NULL,
  account_name STRING(100),
  account_type STRING(20) NOT NULL,    -- CASH, MARGIN, CUSTODY, IRA, 401K
  currency STRING(3) NOT NULL,
  balance NUMERIC NOT NULL DEFAULT (0),
  available_balance NUMERIC NOT NULL DEFAULT (0),
  credit_limit NUMERIC,
  status STRING(10) NOT NULL,
  opened_date DATE NOT NULL,
  closed_date DATE,
  branch_id INT64,
  officer_id INT64,
  created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
  updated_at TIMESTAMP OPTIONS (allow_commit_timestamp = true),
) PRIMARY KEY (entity_id, account_id),
  INTERLEAVE IN PARENT entities ON DELETE NO ACTION;

-- Grandchild: Sub-accounts (interleaved in accounts)
CREATE TABLE sub_accounts (
  entity_id INT64 NOT NULL,
  account_id INT64 NOT NULL,
  sub_account_id INT64 NOT NULL DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE seq_sub_account_id)),
  sub_account_type STRING(20) NOT NULL, -- PRINCIPAL, INCOME, FEE, TAX
  currency STRING(3) NOT NULL,
  balance NUMERIC NOT NULL DEFAULT (0),
  status STRING(10) NOT NULL,
  created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
) PRIMARY KEY (entity_id, account_id, sub_account_id),
  INTERLEAVE IN PARENT accounts ON DELETE NO ACTION;

-- Grandchild: Transactions (interleaved in accounts)
CREATE TABLE transactions (
  entity_id INT64 NOT NULL,
  account_id INT64 NOT NULL,
  transaction_id INT64 NOT NULL DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE seq_transaction_id)),
  transaction_date DATE NOT NULL,
  value_date DATE NOT NULL,
  transaction_type STRING(20) NOT NULL, -- CREDIT, DEBIT, FEE, INTEREST, DIVIDEND
  amount NUMERIC NOT NULL,
  currency STRING(3) NOT NULL,
  balance_after NUMERIC NOT NULL,
  description STRING(500),
  reference STRING(50),
  counterparty_name STRING(200),
  status STRING(10) NOT NULL,
  created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
) PRIMARY KEY (entity_id, account_id, transaction_id),
  INTERLEAVE IN PARENT accounts ON DELETE NO ACTION;

-- Indexes
CREATE UNIQUE INDEX ix_accounts_number ON accounts (account_number);
CREATE INDEX ix_transactions_date ON transactions (entity_id, account_id, transaction_date DESC)
  STORING (amount, transaction_type, balance_after, description),
  INTERLEAVE IN accounts;
CREATE INDEX ix_entities_name ON entities (entity_name)
  STORING (entity_type, status);
```

## Market Data Time-Series Schema

Models instrument price data avoiding timestamp-based hotspots.

```sql
-- Instruments (reference data, no interleaving - accessed independently)
CREATE TABLE instruments (
  instrument_id INT64 NOT NULL DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE seq_instrument_id)),
  ticker STRING(20),
  isin STRING(12),
  cusip STRING(9),
  sedol STRING(7),
  instrument_name STRING(200) NOT NULL,
  instrument_type STRING(20) NOT NULL,  -- EQUITY, BOND, OPTION, FUTURE, FX
  currency STRING(3) NOT NULL,
  exchange STRING(10),
  country STRING(2),
  sector STRING(50),
  issuer_id INT64,
  maturity_date DATE,                   -- For bonds/options
  coupon_rate NUMERIC,                  -- For bonds
  strike_price NUMERIC,                 -- For options
  status STRING(10) NOT NULL,
  created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
) PRIMARY KEY (instrument_id);

-- Prices (interleaved in instruments - always accessed with instrument)
-- Key design: instrument_id first to distribute writes across instruments
CREATE TABLE instrument_prices (
  instrument_id INT64 NOT NULL,
  price_date DATE NOT NULL,
  open_price NUMERIC,
  high_price NUMERIC,
  low_price NUMERIC,
  close_price NUMERIC NOT NULL,
  adjusted_close NUMERIC,
  volume INT64,
  source STRING(20),
  created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
) PRIMARY KEY (instrument_id, price_date DESC),
  INTERLEAVE IN PARENT instruments ON DELETE NO ACTION;

-- Intraday prices (for real-time trading, NOT interleaved to avoid hot splits)
-- Key: instrument_id first, then timestamp, to distribute by instrument
CREATE TABLE intraday_prices (
  instrument_id INT64 NOT NULL,
  price_timestamp TIMESTAMP NOT NULL,
  bid_price NUMERIC,
  ask_price NUMERIC,
  last_price NUMERIC NOT NULL,
  volume INT64,
  source STRING(20),
) PRIMARY KEY (instrument_id, price_timestamp DESC),
  ROW DELETION POLICY (OLDER_THAN(price_timestamp, INTERVAL 90 DAY));
  -- TTL: auto-delete intraday prices after 90 days

-- Indexes
CREATE UNIQUE INDEX ix_instruments_isin ON instruments (isin)
  STORING (instrument_name, instrument_type, currency, status);
CREATE UNIQUE INDEX ix_instruments_cusip ON instruments (cusip)
  STORING (instrument_name, instrument_type, currency, status);
CREATE INDEX ix_instruments_type ON instruments (instrument_type, status)
  STORING (ticker, instrument_name, currency);
```

## Audit Trail Schema

Models a comprehensive audit trail with commit timestamps and TTL for non-compliance data.

```sql
CREATE SEQUENCE seq_audit_id OPTIONS (
  sequence_kind = 'bit_reversed_positive',
  skip_range_min = 1, skip_range_max = 1000000000
);

CREATE TABLE audit_entries (
  audit_id INT64 NOT NULL DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE seq_audit_id)),
  entity_type STRING(50) NOT NULL,     -- TRADE, ACCOUNT, POSITION, INSTRUMENT
  entity_id INT64 NOT NULL,
  action STRING(20) NOT NULL,          -- CREATE, UPDATE, DELETE, VIEW, EXPORT
  field_name STRING(100),              -- Which field changed (for UPDATE)
  old_value STRING(MAX),               -- Previous value (JSON for complex)
  new_value STRING(MAX),               -- New value (JSON for complex)
  user_id INT64 NOT NULL,
  user_name STRING(100),
  ip_address STRING(45),               -- IPv4 or IPv6
  session_id STRING(36),
  application STRING(50),
  reason STRING(500),                  -- Business reason for change
  spanner_commit_ts TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
) PRIMARY KEY (audit_id);

-- Index for entity-based audit queries
CREATE INDEX ix_audit_entity ON audit_entries (entity_type, entity_id, spanner_commit_ts DESC)
  STORING (action, user_name, field_name);

-- Index for user-based audit queries
CREATE INDEX ix_audit_user ON audit_entries (user_id, spanner_commit_ts DESC)
  STORING (entity_type, entity_id, action);

-- Index for time-based audit queries (compliance review)
CREATE INDEX ix_audit_time ON audit_entries (spanner_commit_ts DESC)
  STORING (entity_type, entity_id, action, user_name);

-- Change Stream for audit entries (CDC to compliance data lake)
CREATE CHANGE STREAM cs_audit
FOR audit_entries
OPTIONS (
  retention_period = '7d',
  value_capture_type = 'NEW_VALUES'
);

-- NOTE: Do NOT apply TTL to audit_entries
-- SOX requires 7-year retention for financial audit trails
-- Data lifecycle is managed by archival procedures, not TTL
```
