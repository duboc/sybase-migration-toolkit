# Analytics Classification Rubric

This reference defines the scoring dimensions and thresholds for classifying Sybase tables and workloads as OLTP (Cloud Spanner), ANALYTICS (BigQuery), HYBRID (Spanner + BigQuery with CDC), or ARCHIVE (Cloud Storage + BigQuery external tables).

## Scoring Dimensions

### 1. Read/Write Ratio (Weight: 20%)

Measured from monOpenObjectActivity (Selects vs Operations) over a minimum 30-day observation window.

| Read % | Write % | Score | Classification Signal |
|--------|---------|-------|----------------------|
| 0-30% | 70-100% | 0 | Strong OLTP |
| 31-50% | 50-69% | 1 | OLTP |
| 51-70% | 30-49% | 2 | Leaning OLTP |
| 71-80% | 20-29% | 3 | HYBRID candidate |
| 81-90% | 10-19% | 4 | Leaning ANALYTICS |
| 91-100% | 0-9% | 5 | Strong ANALYTICS |

**Measurement queries:**

```sql
-- Read/write ratio from MDA tables
SELECT
    DBName,
    ObjectName,
    Selects AS reads,
    (RowsInserted + RowsUpdated + RowsDeleted) AS writes,
    CASE WHEN (Selects + RowsInserted + RowsUpdated + RowsDeleted) > 0
        THEN CAST(Selects AS FLOAT) /
             (Selects + RowsInserted + RowsUpdated + RowsDeleted) * 100
        ELSE 0
    END AS read_pct
FROM master..monOpenObjectActivity
WHERE ObjectName = @table_name
```

### 2. Query Complexity (Weight: 20%)

Analyzed from stored procedures and ad-hoc query patterns accessing the table.

| Pattern | Score | Classification Signal |
|---------|-------|----------------------|
| Point lookups only (WHERE pk = @val) | 0 | Strong OLTP |
| Range scans with selective predicates | 1 | OLTP |
| Simple joins (2-3 tables) with filters | 2 | Leaning OLTP |
| Multi-table joins with aggregations | 3 | HYBRID |
| GROUP BY with HAVING, window functions | 4 | Leaning ANALYTICS |
| Full table scans, COMPUTE BY, UNION ALL reports | 5 | Strong ANALYTICS |

**Complexity detection heuristics:**

- Count aggregation functions: SUM, AVG, COUNT, MIN, MAX
- Count GROUP BY columns
- Count HAVING clauses
- Count window functions (OVER/PARTITION BY)
- Count COMPUTE BY clauses (Sybase-specific)
- Count UNION ALL concatenations
- Detect full table scans (no WHERE or non-selective predicates)
- Detect cross-tab/pivot patterns

### 3. Data Volume (Weight: 15%)

Total table size including indexes, measured from sysindexes.

| Size | Score | Classification Signal |
|------|-------|----------------------|
| < 1 GB | 0 | No size signal |
| 1-10 GB | 1 | Small (either platform) |
| 10-50 GB | 2 | Medium (Spanner handles well) |
| 50-100 GB | 3 | Large (consider BigQuery for analytics) |
| 100-500 GB | 4 | Very large (BigQuery preferred for analytics) |
| > 500 GB | 5 | Massive (BigQuery strongly preferred) |

**Notes:**
- Spanner handles large tables well for OLTP patterns, but BigQuery is more cost-effective for analytics on large datasets
- Consider partitioning requirements: Spanner has different partition limits than BigQuery
- Factor in growth rate: tables growing >10% monthly may be better suited for BigQuery's elastic storage

### 4. Access Pattern (Weight: 15%)

How the table is accessed: real-time interactive, batch scheduled, or mixed.

| Pattern | Score | Classification Signal |
|---------|-------|----------------------|
| Real-time interactive (<100ms SLA) | 0 | Strong OLTP |
| Near-real-time (<1s SLA) | 1 | OLTP |
| Mixed real-time + batch | 2 | HYBRID |
| Batch scheduled (hourly/daily) | 3 | Leaning ANALYTICS |
| Batch scheduled (weekly/monthly) | 4 | ANALYTICS |
| Ad-hoc / on-demand reporting | 5 | Strong ANALYTICS |

**Detection methods:**
- Check job scheduler for batch jobs referencing the table
- Check application response time SLAs
- Analyze time-of-day access patterns from MDA tables
- Identify reporting tool connections (Crystal Reports, BI tools)

### 5. Schema Shape (Weight: 15%)

The structural characteristics of the table and its relationships.

| Pattern | Score | Classification Signal |
|---------|-------|----------------------|
| Normalized (3NF) with FK constraints | 0 | Strong OLTP |
| Normalized with moderate denormalization | 1 | OLTP |
| Mixed normalized + summary tables | 2 | HYBRID |
| Denormalized wide tables (>30 columns) | 3 | Leaning ANALYTICS |
| Star schema (fact table with dimension FKs) | 4 | ANALYTICS |
| Snowflake schema / cube support tables | 5 | Strong ANALYTICS |

**Star schema indicators:**
- Table has 3+ outbound FK relationships to smaller tables (dimensions)
- Table has numeric measure columns (amount, quantity, price, volume)
- Table has date/time columns used as partition keys
- Table follows append-only pattern (inserts only, no updates/deletes)
- Related smaller tables have descriptive string columns (name, description, category)

### 6. Data Freshness Requirement (Weight: 15%)

How fresh the data must be when queried.

| Freshness | Score | Classification Signal |
|-----------|-------|----------------------|
| Sub-second (real-time trading) | 0 | Strong OLTP |
| < 1 second | 1 | OLTP |
| 1 second - 1 minute | 2 | HYBRID (possible stale reads) |
| 1 minute - 1 hour | 3 | HYBRID (CDC acceptable latency) |
| 1 hour - 1 day | 4 | ANALYTICS (batch refresh OK) |
| > 1 day (historical/archive) | 5 | Strong ANALYTICS / ARCHIVE |

## Composite Score Calculation

```
composite_score = SUM(dimension_score * weight) / 5.0

Classification thresholds:
  IF composite_score <= 1.5:  -> OLTP (Cloud Spanner)
  ELIF composite_score <= 2.5: -> HYBRID (Spanner + BigQuery with CDC)
  ELIF composite_score <= 4.0: -> ANALYTICS (BigQuery)
  ELSE:                        -> ARCHIVE (Cloud Storage + BigQuery external)
```

## Special Classification Rules

These rules override the composite score:

| Rule | Condition | Override Classification |
|------|-----------|----------------------|
| IQ instance | Server type is Sybase IQ | ANALYTICS (always) |
| Zero writes, old data | 100% reads, no writes in 2+ years, no freshness requirement | ARCHIVE |
| Real-time trading | Sub-second freshness requirement, regardless of read ratio | OLTP |
| Regulatory mandate | Table subject to regulatory access SLA | As required by regulation |
| Compliance archive | Data retained only for compliance, no active access | ARCHIVE |

## Target Platform Characteristics

### Cloud Spanner (OLTP)
- Low-latency point lookups and range scans
- Strong consistency with serializable transactions
- Interleaved tables for data co-location
- Scales horizontally with automatic sharding
- Cost model: node-hours + storage

### BigQuery (ANALYTICS)
- Columnar storage optimized for analytical queries
- Massive parallel processing for aggregations
- Partitioning by date/integer, clustering by dimensions
- Serverless with on-demand or reservation pricing
- Cost model: query bytes scanned + storage

### Spanner + BigQuery with CDC (HYBRID)
- OLTP writes go to Spanner (low latency, strong consistency)
- Change Streams capture mutations in near-real-time
- Dataflow pipeline transforms and loads to BigQuery
- Analytics queries run on BigQuery (optimized for aggregations)
- CDC latency: typically seconds to low minutes

### Cloud Storage + BigQuery External (ARCHIVE)
- Cheapest storage option for rarely-accessed data
- BigQuery external tables for on-demand querying
- Parquet/ORC format for analytical efficiency
- No real-time access requirement
- Cost model: storage only (queries on-demand)
