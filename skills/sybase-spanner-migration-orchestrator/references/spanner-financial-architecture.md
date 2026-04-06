# Spanner Financial Architecture Reference

Reference architectures for financial systems on Google Cloud Spanner, covering schema design patterns, multi-region configuration, BigQuery federation, and GCP service integration.

## Spanner Schema Design for Financial Systems

### Primary Key Strategy (Avoiding Hotspots)

Financial systems on Sybase often use sequential integer primary keys (`IDENTITY` columns). These create write hotspots on Spanner because sequential keys concentrate writes on a single split.

**Recommended key strategies**:

| Pattern | Example | When to Use |
|---------|---------|-------------|
| UUID v4 | `trade_id STRING(36) NOT NULL` | New records, no ordering requirement |
| Bit-reversed sequence | `trade_id INT64 NOT NULL` (bit-reverse the Sybase identity) | Migration from Sybase identity columns |
| Composite natural key | `(account_id, transaction_date, sequence_num)` | Natural hierarchy, range scan friendly |
| Hash-prefixed | `FARM_FINGERPRINT(account_id) % 1000 as shard_key` | Distribute writes for high-volume tables |
| Timestamp-based (with shard) | `(shard_id, created_at, trade_id)` | Time-series with write distribution |

**Anti-patterns to avoid**:
- `INT64` identity columns without bit-reversal (creates hotspot at the end of key space)
- `TIMESTAMP` as the first key column without a shard prefix (time-based hotspot)
- `STRING` keys that sort similarly (e.g., all starting with "TRADE-2026-")

### Interleaved Table Design for Financial Data

Interleaved tables co-locate parent and child rows on the same Spanner split, dramatically improving join performance for parent-child access patterns common in financial systems.

**Trading system example**:
```sql
CREATE TABLE Orders (
  order_id STRING(36) NOT NULL,
  account_id STRING(36) NOT NULL,
  instrument_id STRING(36) NOT NULL,
  order_type STRING(10) NOT NULL,  -- MARKET, LIMIT, STOP
  side STRING(4) NOT NULL,          -- BUY, SELL
  quantity NUMERIC NOT NULL,
  limit_price NUMERIC,
  status STRING(20) NOT NULL,
  created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
  updated_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
) PRIMARY KEY (order_id);

CREATE TABLE OrderExecutions (
  order_id STRING(36) NOT NULL,
  execution_id STRING(36) NOT NULL,
  executed_quantity NUMERIC NOT NULL,
  executed_price NUMERIC NOT NULL,
  execution_venue STRING(20) NOT NULL,
  executed_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
  commission NUMERIC NOT NULL,
  fees NUMERIC NOT NULL,
) PRIMARY KEY (order_id, execution_id),
  INTERLEAVE IN PARENT Orders ON DELETE CASCADE;

CREATE TABLE OrderAuditTrail (
  order_id STRING(36) NOT NULL,
  audit_seq INT64 NOT NULL,
  action STRING(20) NOT NULL,
  field_changed STRING(50),
  old_value STRING(500),
  new_value STRING(500),
  changed_by STRING(100) NOT NULL,
  changed_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
) PRIMARY KEY (order_id, audit_seq),
  INTERLEAVE IN PARENT Orders ON DELETE NO ACTION;
```

**Settlement system example**:
```sql
CREATE TABLE Settlements (
  settlement_id STRING(36) NOT NULL,
  trade_id STRING(36) NOT NULL,
  settlement_date DATE NOT NULL,
  settlement_amount NUMERIC NOT NULL,
  settlement_currency STRING(3) NOT NULL,
  status STRING(20) NOT NULL,
  counterparty_id STRING(36) NOT NULL,
  created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
) PRIMARY KEY (settlement_id);

CREATE TABLE SettlementLegs (
  settlement_id STRING(36) NOT NULL,
  leg_id STRING(36) NOT NULL,
  delivery_type STRING(10) NOT NULL,  -- DVP, FOP, PAYMENT
  amount NUMERIC NOT NULL,
  currency STRING(3) NOT NULL,
  custodian_id STRING(36),
  status STRING(20) NOT NULL,
  settled_at TIMESTAMP,
) PRIMARY KEY (settlement_id, leg_id),
  INTERLEAVE IN PARENT Settlements ON DELETE CASCADE;

CREATE TABLE SettlementInstructions (
  settlement_id STRING(36) NOT NULL,
  instruction_id STRING(36) NOT NULL,
  instruction_type STRING(20) NOT NULL,
  swift_message_type STRING(10),
  message_content STRING(MAX),
  sent_at TIMESTAMP,
  acknowledged_at TIMESTAMP,
) PRIMARY KEY (settlement_id, instruction_id),
  INTERLEAVE IN PARENT Settlements ON DELETE CASCADE;
```

### Data Type Mapping for Financial Precision

| Sybase Type | Spanner Type | Notes |
|-------------|-------------|-------|
| `money` | `NUMERIC` | Spanner NUMERIC has precision 38, scale 9 (exceeds Sybase money's 4 decimal places) |
| `smallmoney` | `NUMERIC` | Same mapping, smaller range |
| `decimal(p,s)` | `NUMERIC` | Spanner NUMERIC handles up to 29 digits before decimal, 9 after |
| `float(precision)` | `FLOAT64` | IEEE 754 double precision |
| `real` | `FLOAT64` | Promoted from single to double precision |
| `int` / `integer` | `INT64` | Promoted from 32-bit to 64-bit |
| `smallint` | `INT64` | Promoted |
| `tinyint` | `INT64` | Promoted |
| `bigint` | `INT64` | Direct mapping |
| `char(n)` | `STRING(n)` | Fixed-length in Sybase, variable in Spanner |
| `varchar(n)` | `STRING(n)` | Direct mapping |
| `nchar(n)` / `nvarchar(n)` | `STRING(n)` | Spanner is always UTF-8 |
| `text` / `unitext` | `STRING(MAX)` | Max 10 MB in Spanner |
| `image` | `BYTES(MAX)` | Max 10 MB in Spanner |
| `binary(n)` / `varbinary(n)` | `BYTES(n)` | Direct mapping |
| `datetime` | `TIMESTAMP` | Spanner has nanosecond precision (exceeds Sybase's 3.33ms) |
| `smalldatetime` | `TIMESTAMP` | Precision improvement |
| `date` | `DATE` | Direct mapping |
| `time` | `STRING(12)` | Spanner has no TIME type; store as string or extract from TIMESTAMP |
| `timestamp` (row version) | `TIMESTAMP OPTIONS (allow_commit_timestamp=true)` | Different semantics: Spanner commit timestamp vs Sybase row version |
| `bit` | `BOOL` | Direct mapping |
| `uniqueidentifier` | `STRING(36)` | UUID stored as string |

### Secondary Index Strategy

Design secondary indexes based on Phase 2 performance profiling query patterns:

```sql
-- Support account-based queries (common in retail banking)
CREATE INDEX idx_orders_by_account ON Orders(account_id, created_at DESC);

-- Support instrument-based queries (common in trading)
CREATE INDEX idx_orders_by_instrument ON Orders(instrument_id, created_at DESC)
  STORING (account_id, order_type, side, quantity, status);

-- Support settlement date queries
CREATE INDEX idx_settlements_by_date ON Settlements(settlement_date, status)
  STORING (settlement_amount, settlement_currency, counterparty_id);

-- Support regulatory reporting queries (MiFID II transaction reporting)
CREATE INDEX idx_executions_by_time ON OrderExecutions(executed_at)
  STORING (order_id, executed_quantity, executed_price, execution_venue);

-- NULL-filtered index for active orders only
CREATE NULL_FILTERED INDEX idx_active_orders ON Orders(status)
  WHERE status != 'COMPLETED' AND status != 'CANCELLED';
```

**Index design principles for financial systems**:
- Use `STORING` clauses to avoid secondary lookups for covered queries
- Use `NULL_FILTERED` for indexes on sparse columns
- Limit to 5-7 secondary indexes per table (Spanner write amplification)
- Always include the columns needed for regulatory reporting queries

## Multi-Region Configuration

### Regional vs Multi-Region Deployment

| Configuration | Use Case | Latency | Availability | Cost |
|--------------|----------|---------|-------------|------|
| Regional | Single-market trading, cost-sensitive | Lowest (single-digit ms) | 99.999% | Lowest |
| Dual-region | DR requirement, two data centers | Low (single-digit ms in primary) | 99.999% | Medium |
| Multi-region (nam-eur-asia14) | Global trading, regulatory multi-residency | Higher (cross-region replication) | 99.999% | Highest |
| Multi-region (nam6, eur6) | Continental deployment | Medium | 99.999% | High |

**Financial system recommendations**:
- Trading systems (single market): Regional deployment in the region closest to the exchange
- Trading systems (multi-market): Multi-region with read replicas near each exchange
- Settlement systems: Dual-region for DR, regional for performance
- Regulatory reporting: Region must comply with data residency requirements
- Retail banking: Regional per country/regulatory jurisdiction

### Disaster Recovery Architecture

**Sybase DR to Spanner DR mapping**:

| Sybase DR Approach | Spanner Equivalent | Notes |
|-------------------|-------------------|-------|
| Replication Server warm standby | Multi-region (automatic) | No manual failover needed |
| Companion server failover | Spanner handles automatically | Zero manual intervention |
| Database dump + load | Spanner export to GCS + import | For point-in-time recovery |
| Transaction log shipping | Spanner Change Streams to GCS | Continuous backup stream |

**RTO/RPO comparison**:
- Sybase Replication Server: RTO 5-30 minutes, RPO seconds to minutes
- Spanner multi-region: RTO 0 (automatic), RPO 0 (synchronous replication)
- Spanner PITR (Point-In-Time Recovery): recover to any point within retention window (up to 7 days)

## BigQuery Federation for Analytics

### OLTP/Analytics Split Architecture

```
                    +------------------+
                    |   Applications   |
                    +--------+---------+
                             |
                    +--------v---------+
                    |    Cloud Run     |
                    |  Microservices   |
                    +--------+---------+
                             |
              +--------------+--------------+
              |                             |
     +--------v---------+        +---------v--------+
     |   Cloud Spanner  |        |    BigQuery      |
     |   (OLTP - hot)   |        | (Analytics/cold) |
     +--------+---------+        +---------+--------+
              |                             ^
              |    Spanner-BigQuery          |
              +-------- Federation ---------+
              |                             |
     +--------v---------+                   |
     | Change Streams   +----> Dataflow +---+
     +------------------+    (streaming)
```

**When to use BigQuery instead of Spanner**:
- Historical data analysis (queries spanning months/years)
- Ad-hoc analytical queries from business analysts
- Regulatory reporting requiring complex aggregations
- Machine learning model training on financial data
- Data warehouse / data lake workloads migrating from Sybase IQ
- Queries scanning large volumes with low concurrency

**Spanner-BigQuery federation**:
```sql
-- Query Spanner data from BigQuery (federated query)
SELECT t.trade_id, t.instrument_id, t.quantity, t.price,
       r.risk_score, r.var_95
FROM EXTERNAL_QUERY('projects/my-project/locations/us/connections/spanner-conn',
  'SELECT trade_id, instrument_id, quantity, price FROM trades WHERE trade_date = CURRENT_DATE()')
AS t
JOIN `my-project.risk_analytics.daily_risk_scores` AS r
ON t.trade_id = r.trade_id;
```

### IQ-to-BigQuery Migration Path

For environments with Sybase IQ, BigQuery is the natural target:

| Sybase IQ Feature | BigQuery Equivalent | Notes |
|-------------------|-------------------|-------|
| Column-store tables | Native column-store | BigQuery is columnar by default |
| IQ multiplex | BigQuery slots (auto-scaling) | No server management |
| IQ load commands | BigQuery load jobs, Dataflow | Multiple ingestion methods |
| IQ stored procedures | BigQuery scripting, Cloud Run | Procedure migration |
| IQ user-defined functions | BigQuery UDFs (SQL/JS) | Function migration |
| IQ join indexes | BigQuery materialized views | Pre-computed aggregations |
| IQ text indexes | BigQuery SEARCH function | Full-text search capability |

## Cloud Run Microservices Architecture

### T-SQL to Cloud Run Service Pattern

```
  Sybase Stored Procedure          Cloud Run Microservice
  +-----------------------+        +---------------------------+
  | CREATE PROC calc_fee  |        | /api/v1/fees/calculate    |
  |   @trade_id int,      |   →    | POST request body:        |
  |   @fee_type varchar   |        |   { trade_id, fee_type }  |
  | AS                    |        |                           |
  |   SELECT ...          |        | Spanner client library    |
  |   UPDATE ...          |        |   read → calculate →      |
  |   RETURN @fee         |        |   write → return fee      |
  +-----------------------+        +---------------------------+
```

**Service decomposition guidelines**:
- One Cloud Run service per business domain (fees, settlements, risk)
- Each service owns its Spanner tables (no cross-service direct DB access)
- Use Pub/Sub for async communication between services
- Use Cloud Endpoints or Apigee for API management
- Each service has its own CI/CD pipeline via Cloud Build

### Change Streams Integration

```
  Spanner Table           Change Streams        Dataflow         Downstream
  +-------------+        +---------------+     +----------+     +-----------+
  | trades      | -----> | watch trades  | --> | transform| --> | Pub/Sub   |
  | (mutations) |        | INSERT/UPDATE |     | + filter |     | → BigQuery|
  +-------------+        +---------------+     +----------+     | → other   |
                                                                +-----------+
```

**Change Streams configuration for financial systems**:
- Retention period: 7 days (maximum) for financial audit requirements
- Value capture type: `NEW_AND_OLD_VALUES` for audit trail reconstruction
- Watch specific tables critical for downstream consumers
- Dataflow pipeline with exactly-once semantics for financial data integrity

## Cost Modeling

### Spanner Cost Components

| Component | Pricing Model | Sizing Input |
|-----------|--------------|-------------|
| Compute (nodes) | Per node-hour ($0.90/node-hour) | Phase 2 performance baselines (TPS, QPS) |
| Storage | Per GB-month ($0.30/GB) | Phase 1 schema profiler (data volume) |
| Network (inter-region) | Per GB egress | Multi-region configuration |
| Backup | Per GB-month ($0.30/GB for PITR) | Retention requirements |

**Sizing guidelines**:
- 1 Spanner node handles approximately 10,000 reads/sec or 2,000 writes/sec
- Financial systems typically need 2-5 nodes for medium workloads
- Add 50% headroom for peak periods (market open, EOD batch)
- Multi-region doubles compute cost (synchronous replication)

### Cost Comparison Template

| Cost Category | Current (Sybase) | Target (Spanner + GCP) | Savings |
|--------------|-----------------|----------------------|---------|
| Database licensing | $X/year | $0 (Spanner is usage-based) | |
| Server hardware | $X/year | Included in Spanner | |
| DBA labor (Sybase-specific) | $X/year | Reduced (managed service) | |
| Replication Server licensing | $X/year | $0 (Change Streams included) | |
| DR infrastructure | $X/year | Included in multi-region | |
| Spanner compute | N/A | $X/year | |
| Spanner storage | N/A | $X/year | |
| BigQuery (if applicable) | N/A | $X/year | |
| Cloud Run compute | N/A | $X/year | |
| Migration effort (one-time) | N/A | $X (one-time) | |
| **Total annual** | **$X** | **$X** | **$X** |
