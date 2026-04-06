# BigQuery Migration Patterns for Sybase IQ and Analytics Workloads

This reference provides migration patterns, type mappings, and architectural guidance for migrating Sybase IQ databases and ASE analytics workloads to BigQuery.

## IQ-to-BigQuery Type Mapping

| Sybase IQ Type | BigQuery Type | Notes |
|---------------|--------------|-------|
| INT | INT64 | Direct mapping |
| BIGINT | INT64 | Direct mapping |
| SMALLINT | INT64 | Widened |
| TINYINT | INT64 | Widened |
| NUMERIC(p,s) | NUMERIC / BIGNUMERIC | BIGNUMERIC if precision > 29 |
| DECIMAL(p,s) | NUMERIC / BIGNUMERIC | BIGNUMERIC if precision > 29 |
| MONEY | NUMERIC | 4 decimal places preserved |
| SMALLMONEY | NUMERIC | 4 decimal places preserved |
| FLOAT | FLOAT64 | Direct mapping |
| REAL | FLOAT64 | Widened |
| DOUBLE | FLOAT64 | Direct mapping |
| CHAR(n) | STRING | Variable length in BigQuery |
| VARCHAR(n) | STRING | Variable length in BigQuery |
| NCHAR(n) | STRING | UTF-8 in BigQuery |
| NVARCHAR(n) | STRING | UTF-8 in BigQuery |
| TEXT | STRING | Max 10 MB in BigQuery |
| LONG VARCHAR | STRING | Max 10 MB in BigQuery |
| DATE | DATE | Direct mapping |
| TIME | TIME | Direct mapping |
| DATETIME | DATETIME / TIMESTAMP | Use TIMESTAMP for UTC |
| SMALLDATETIME | DATETIME | Direct mapping |
| TIMESTAMP | TIMESTAMP | Direct mapping |
| BIT | BOOL | Direct mapping |
| BINARY(n) | BYTES | Direct mapping |
| VARBINARY(n) | BYTES | Direct mapping |
| IMAGE | BYTES | Max 10 MB; consider GCS for larger |
| LONG BINARY | BYTES | Max 10 MB; consider GCS for larger |
| XML | STRING | Store as JSON or STRING |
| UNIQUEIDENTIFIER | STRING(36) | UUID format |

## IQ Index to BigQuery Feature Mapping

| IQ Index Type | Purpose | BigQuery Equivalent | Notes |
|--------------|---------|-------------------|-------|
| HG (High Group) | B-tree for high cardinality, group by operations | Clustering columns | Define as first clustering column |
| HNG (High Non-Group) | Bitmap for high cardinality, range queries | Partition + Clustering | Partition by range, cluster by column |
| LF (Low Fast) | Bitmap for low cardinality (<1000 distinct) | Partition column | Use as partition column if <4000 partitions |
| FP (Fast Projection) | Default column index, all columns | Columnar storage (native) | BigQuery stores all columns in columnar format |
| CMP (Compare) | Compressed FP for sorted data | Clustering | Cluster by sorted column |
| WD (Word) | Full-text word index | BigQuery Search Index | CREATE SEARCH INDEX |
| TEXT | Full-text search | BigQuery Search Index | CREATE SEARCH INDEX |
| JOIN INDEX | Pre-computed join results | Materialized View | CREATE MATERIALIZED VIEW |
| DATE | Optimized date index | Date partitioning | PARTITION BY DATE(column) |

## Partitioning Strategies for Financial Data

### By Date (Most Common)

```sql
-- Trade history partitioned by trade date
CREATE TABLE trade_history (
  trade_id INT64 NOT NULL,
  trade_date DATE NOT NULL,
  instrument_id INT64,
  account_id INT64,
  side STRING,
  quantity NUMERIC,
  price NUMERIC,
  amount NUMERIC,
  currency STRING,
  status STRING
)
PARTITION BY trade_date
CLUSTER BY instrument_id, account_id
OPTIONS (
  partition_expiration_days = 2555,  -- 7 years for SOX
  require_partition_filter = TRUE     -- Prevent full table scans
);
```

### By Ingestion Time

```sql
-- Market data with ingestion time partitioning
CREATE TABLE market_data_raw (
  instrument_id INT64,
  price NUMERIC,
  volume NUMERIC,
  source STRING,
  raw_data JSON
)
PARTITION BY _PARTITIONDATE  -- Automatic ingestion-time partitioning
CLUSTER BY instrument_id, source;
```

### By Integer Range

```sql
-- Account-based partitioning for large account ranges
CREATE TABLE account_balances (
  account_id INT64 NOT NULL,
  balance_date DATE NOT NULL,
  balance NUMERIC,
  currency STRING
)
PARTITION BY RANGE_BUCKET(account_id, GENERATE_ARRAY(0, 10000000, 100000))
CLUSTER BY balance_date;
```

## Clustering Strategies for Financial Queries

Common financial query patterns and optimal clustering:

| Query Pattern | Clustering Columns | Rationale |
|--------------|-------------------|-----------|
| By instrument + date | `instrument_id, trade_date` | Most common securities query pattern |
| By counterparty + date | `counterparty_id, settlement_date` | Settlement and clearing queries |
| By account + date | `account_id, transaction_date` | Account statement and balance queries |
| By currency + date | `currency, value_date` | FX and multi-currency queries |
| By portfolio + instrument | `portfolio_id, instrument_id` | Position and P&L queries |
| By region + product | `region, product_type` | Regulatory and risk reporting |

**BigQuery clustering rules:**
- Maximum 4 clustering columns per table
- Order columns by query filter frequency (most filtered first)
- Clustering is free (no additional storage cost)
- Clustering improves query performance AND reduces cost (fewer bytes scanned)

## Materialized Views (Replacing IQ Join Indexes)

```sql
-- IQ join index replacement: Pre-computed trade summary
CREATE MATERIALIZED VIEW mv_daily_trade_summary
AS
SELECT
  trade_date,
  instrument_id,
  i.instrument_name,
  i.instrument_type,
  COUNT(*) AS trade_count,
  SUM(quantity) AS total_quantity,
  SUM(amount) AS total_amount,
  AVG(price) AS avg_price,
  MIN(price) AS min_price,
  MAX(price) AS max_price
FROM trade_history t
JOIN instruments i ON t.instrument_id = i.instrument_id
GROUP BY trade_date, instrument_id, i.instrument_name, i.instrument_type;

-- BigQuery auto-uses materialized views for matching queries
-- No query rewrite needed in application code
```

## Looker Dashboard Patterns (Replacing Crystal Reports)

### LookML Model for Trade Data

```lookml
# model: trading_analytics.model.lkml
connection: "bigquery_production"

explore: trade_history {
  label: "Trade History"
  join: instruments {
    type: left_outer
    sql_on: ${trade_history.instrument_id} = ${instruments.instrument_id} ;;
    relationship: many_to_one
  }
  join: accounts {
    type: left_outer
    sql_on: ${trade_history.account_id} = ${accounts.account_id} ;;
    relationship: many_to_one
  }
}
```

### Common Financial Dashboard Patterns

| Crystal Report | Looker Equivalent | Pattern |
|---------------|-------------------|---------|
| Daily trade blotter | Looker dashboard with trade_date filter | Explore with date filter, table visualization |
| P&L summary | Looker dashboard with P&L measures | Calculated fields, period comparison |
| Position report | Looker dashboard with position measures | Current snapshot with drill-down |
| Risk report | Looker dashboard with risk metrics | VAR, stress test results, limit utilization |
| Regulatory extract | Scheduled Looker Look with export | CSV/Excel export on schedule |
| Ad-hoc query | Looker Explore | Self-service analytics |

## Scheduled Queries (Replacing IQ Stored Procedures)

```sql
-- BigQuery scheduled query replacing IQ procedure sp_daily_position_snapshot
-- Schedule: Daily at 18:00 UTC (after market close)

INSERT INTO position_snapshots (snapshot_date, portfolio_id, instrument_id, quantity, market_value, unrealized_pnl)
SELECT
  CURRENT_DATE() AS snapshot_date,
  p.portfolio_id,
  p.instrument_id,
  p.quantity,
  p.quantity * md.close_price AS market_value,
  (p.quantity * md.close_price) - (p.quantity * p.avg_cost) AS unrealized_pnl
FROM positions p
JOIN market_data md
  ON p.instrument_id = md.instrument_id
  AND md.price_date = CURRENT_DATE()
WHERE p.quantity != 0;
```

## Bulk Migration Strategy

### Step 1: BCP Extract from Sybase

```bash
# Extract from Sybase IQ using BCP
bcp database.dbo.trade_history out trade_history.dat \
  -S IQ_SERVER \
  -U extract_user \
  -P ${PASSWORD} \
  -c \              # Character mode
  -t "|" \          # Pipe delimiter
  -r "\n" \         # Row terminator
  -b 100000         # Batch size
```

### Step 2: Upload to GCS

```bash
# Upload to Cloud Storage staging bucket
gsutil -m cp trade_history.dat gs://${BUCKET}/staging/trade_history/

# For large files (>100GB), use parallel composite uploads
gsutil -o GSUtil:parallel_composite_upload_threshold=150M \
  cp trade_history.dat gs://${BUCKET}/staging/trade_history/
```

### Step 3: Load to BigQuery

```bash
# Load from GCS to BigQuery
bq load \
  --source_format=CSV \
  --field_delimiter="|" \
  --max_bad_records=0 \        # Zero tolerance for financial data
  --null_marker="NULL" \
  ${DATASET}.trade_history \
  gs://${BUCKET}/staging/trade_history/trade_history.dat \
  trade_history_schema.json
```

### Step 4: Dataflow Transform (for complex transformations)

```python
# Apache Beam pipeline for Sybase IQ to BigQuery with transforms
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions

class TransformTradeRecord(beam.DoFn):
    def process(self, record):
        # Type conversions
        record['trade_date'] = parse_sybase_datetime(record['trade_date'])
        # Currency standardization
        record['currency'] = standardize_currency(record['currency'])
        # Amount precision
        record['amount'] = Decimal(record['amount']).quantize(Decimal('0.0001'))
        yield record

with beam.Pipeline(options=PipelineOptions()) as p:
    (p
     | 'Read from GCS' >> beam.io.ReadFromText('gs://bucket/staging/*.dat')
     | 'Parse CSV' >> beam.Map(parse_pipe_delimited)
     | 'Transform' >> beam.ParDo(TransformTradeRecord())
     | 'Write to BQ' >> beam.io.WriteToBigQuery(
         'project:dataset.trade_history',
         schema=TRADE_HISTORY_SCHEMA,
         write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND,
         create_disposition=beam.io.BigQueryDisposition.CREATE_IF_NEEDED))
```

## Data Validation After Migration

```sql
-- Row count validation
SELECT 'BigQuery' AS source, COUNT(*) AS row_count FROM `project.dataset.trade_history`;
-- Compare with Sybase IQ: SELECT COUNT(*) FROM trade_history

-- Financial amount validation (critical - zero tolerance)
SELECT
  'BigQuery' AS source,
  SUM(amount) AS total_amount,
  COUNT(DISTINCT instrument_id) AS instrument_count,
  MIN(trade_date) AS earliest_date,
  MAX(trade_date) AS latest_date
FROM `project.dataset.trade_history`;
-- Compare with Sybase IQ equivalent

-- Checksum validation by date partition
SELECT
  trade_date,
  COUNT(*) AS row_count,
  SUM(amount) AS total_amount,
  TO_HEX(MD5(STRING_AGG(CAST(trade_id AS STRING), ',' ORDER BY trade_id))) AS checksum
FROM `project.dataset.trade_history`
GROUP BY trade_date
ORDER BY trade_date;
```
