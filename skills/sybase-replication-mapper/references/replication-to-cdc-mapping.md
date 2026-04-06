# Sybase Replication Server to GCP CDC Architecture Mapping

Reference guide for translating Sybase Replication Server concepts to Google Cloud Platform Change Data Capture services.

## Component-Level Mapping

### Source-Side Components

| Sybase Component | Role | GCP Equivalent | Implementation Details |
|-----------------|------|---------------|----------------------|
| **RepAgent (Replication Agent)** | Reads transaction log, sends LTL to RepServer | **Datastream** connector or **Spanner Change Streams** | Datastream connects to source databases and captures changes. For Spanner-native CDC, Change Streams watch specific tables. |
| **LTL (Log Transfer Language)** | Wire protocol between RepAgent and RepServer | **Change Stream records** or **Datastream CDC format** | Change events encoded as JSON/Avro records. Includes operation type, before/after images, timestamps. |
| **Transaction log scanning** | RepAgent scans syslogs for committed transactions | **Spanner Change Streams** | Change Streams automatically capture committed mutations. No log scanning needed — built into Spanner. |

### Processing Components

| Sybase Component | Role | GCP Equivalent | Implementation Details |
|-----------------|------|---------------|----------------------|
| **Replication Server** | Central routing and transformation engine | **Pub/Sub + Dataflow** | Pub/Sub handles message routing; Dataflow handles transformations. No single equivalent — decomposed into specialized services. |
| **Stable Queue Manager (SQM)** | Durable message queuing | **Pub/Sub message retention** | Pub/Sub retains messages for up to 31 days. Supports exactly-once delivery with ordering keys. |
| **Distributor thread (DSI)** | Applies transactions to replicate database | **Dataflow sink** or **Cloud Run consumer** | Dataflow writes to target Spanner/BigQuery. Cloud Run for custom application logic. |
| **RSSD (Rep Server System Database)** | Metadata store for replication configuration | **Cloud Monitoring + Terraform/Config** | Replication configuration managed as Infrastructure as Code. Monitoring via Cloud Monitoring dashboards. |

### Replication Patterns

| Sybase Pattern | Description | GCP Architecture |
|---------------|-------------|-----------------|
| **Warm Standby** | Full database replication for disaster recovery | **Spanner multi-region configuration** — Built-in replication with 99.999% SLA. No custom setup needed. Select `nam-eur-asia1` or regional config. |
| **Active-Active** | Bi-directional replication with conflict resolution | **Spanner + application-level conflict resolution** — Spanner is single-writer per row. Application must implement last-writer-wins, merge, or custom conflict resolution. |
| **Cascading replication** | Multi-hop: Primary → RepServer A → RepServer B → Replicate | **Pub/Sub topic chaining** — Topic A → Subscription → Dataflow → Topic B → Subscription → Consumer. Or single Dataflow pipeline with fan-out. |
| **Consolidated replication** | Multiple primaries replicate to single target | **Multiple Change Streams → single Pub/Sub topic** — Each source publishes to the same topic; consumer processes all changes. Use ordering keys per source. |

## Function String Migration

### PASS_THROUGH Function Strings

**Sybase**: Default function strings apply DML as-is to replicate.

**GCP**: Spanner Change Streams → Pub/Sub → Dataflow → target Spanner. No transformation needed.

```
Sybase Flow:
  RepAgent → RepServer → Default rs_insert/rs_update/rs_delete → Replicate ASE

GCP Flow:
  Spanner Change Stream → Pub/Sub → Dataflow (identity transform) → Target Spanner
```

**Implementation:**
1. Create Change Stream on source tables: `CREATE CHANGE STREAM trade_changes FOR trades, positions`
2. Dataflow template: `SpannerChangeStreams_to_PubSub` (built-in template)
3. Consumer Dataflow reads from Pub/Sub and writes to target Spanner

### TRANSFORM Function Strings

**Sybase**: Custom function strings that modify data during replication (column mapping, type conversion, calculations).

**GCP**: Dataflow transformation pipeline.

```python
# Dataflow transform example: Currency conversion during replication
class CurrencyConvertDoFn(beam.DoFn):
    def process(self, change_record):
        if change_record['table'] == 'trades':
            row = change_record['new_values']
            fx_rate = self.get_fx_rate(row['currency'], 'GBP')
            row['amount_gbp'] = row['amount_usd'] * fx_rate
            yield row

pipeline = (
    p
    | 'ReadChanges' >> ReadFromPubSub(topic='trade-changes')
    | 'ParseJSON' >> beam.Map(json.loads)
    | 'ConvertCurrency' >> beam.ParDo(CurrencyConvertDoFn())
    | 'WriteToSpanner' >> WriteToSpanner(instance='trading', database='tradedb_uk')
)
```

### CONFLICT_RESOLUTION Function Strings

**Sybase**: Function strings that handle active-active conflicts using origin site, timestamps, or priority.

**GCP**: Application-level conflict resolution in Cloud Run.

```python
# Cloud Run conflict resolution service
@app.route('/resolve-conflict', methods=['POST'])
def resolve_conflict():
    change = request.json

    # Last-writer-wins based on modification timestamp
    current = spanner_client.read('positions',
        columns=['modified_at'],
        keyset=KeySet(keys=[[change['account_id'], change['instrument_id']]]))

    current_row = list(current)[0] if current else None

    if current_row is None or change['modified_at'] > current_row[0]:
        # Apply the change
        spanner_client.commit(mutations=[
            Mutation.replace('positions',
                columns=['account_id', 'instrument_id', 'quantity', 'modified_at'],
                values=[[change['account_id'], change['instrument_id'],
                         change['quantity'], change['modified_at']]])
        ])

    return {'status': 'resolved', 'action': 'applied' if applied else 'skipped'}
```

### BUSINESS_RULE Function Strings

**Sybase**: Function strings that call stored procedures or implement multi-step business logic.

**GCP**: Cloud Run microservices orchestrated by Cloud Workflows.

```yaml
# Cloud Workflows: Settlement processing (replaces BUSINESS_RULE function string)
main:
  steps:
    - process_settlement:
        call: http.post
        args:
          url: https://settlement-service.run.app/process
          body:
            settlement_id: ${settlement_id}
        result: settlement_result

    - update_positions:
        call: http.post
        args:
          url: https://position-service.run.app/update-after-settle
          body:
            account_id: ${account_id}
            settlement: ${settlement_result}

    - notify_clearing:
        call: http.post
        args:
          url: https://notification-service.run.app/clearing-house
          body:
            settlement_id: ${settlement_id}
            status: ${settlement_result.status}
```

## Latency Architecture Patterns

### REAL_TIME (< 1 second)

```
Spanner Change Stream → Pub/Sub (push subscription) → Cloud Run
```

- Push subscriptions deliver immediately upon message arrival
- Cloud Run auto-scales to handle burst traffic
- End-to-end latency: 100-500ms typical

### NEAR_REAL_TIME (1-30 seconds)

```
Spanner Change Stream → Pub/Sub → Dataflow (streaming) → Target
```

- Dataflow streaming with 1-second windows
- Micro-batch processing for efficiency
- End-to-end latency: 2-10 seconds typical

### BATCH (> 30 seconds)

```
Cloud Scheduler → Dataflow (batch) → BigQuery / Target Spanner
```

- Scheduled batch jobs via Cloud Scheduler
- Dataflow batch reads from Spanner, transforms, and writes to target
- Runs at configured intervals (hourly, daily, etc.)

## Subscription Set Migration

Sybase subscription sets group related tables for consistent replication. GCP equivalents:

| Sybase Concept | GCP Equivalent | Configuration |
|---------------|---------------|---------------|
| Subscription set | Change Stream with multiple tables | `CREATE CHANGE STREAM my_stream FOR table1, table2, table3` |
| Subscription | Pub/Sub subscription | One subscription per consumer |
| Article (replicated table) | Change Stream table spec | Individual table in Change Stream FOR clause |
| Filter (WHERE clause replication) | Dataflow filter transform | `beam.Filter(lambda row: row['region'] == 'US')` |

## Monitoring Replacement

| Sybase Monitoring | GCP Equivalent | Setup |
|------------------|---------------|-------|
| `rs_helpcounter` | Cloud Monitoring custom metrics | Dashboard with Change Stream throughput, Pub/Sub message counts |
| RepServer error log | Cloud Logging | Dataflow and Cloud Run logs aggregated in Cloud Logging |
| Queue depth monitoring | Pub/Sub metrics: `num_undelivered_messages` | Alert on growing backlog |
| Replication latency | Custom metric: publish time vs consume time | End-to-end latency tracking |
| DSI thread status | Cloud Run instance health | Health checks and auto-restart |

## Migration Checklist

- [ ] All replication routes documented with latency SLAs
- [ ] Function strings classified (PASS_THROUGH, TRANSFORM, CONFLICT_RESOLUTION, BUSINESS_RULE)
- [ ] BUSINESS_RULE function strings have extraction plan to Cloud Run
- [ ] CONFLICT_RESOLUTION strategy defined for active-active routes
- [ ] Pub/Sub topics and subscriptions designed per route
- [ ] Dataflow pipelines designed for TRANSFORM function strings
- [ ] Ordering key strategy defined for Pub/Sub (account_id, trade_id, etc.)
- [ ] Warm standby replaced by Spanner multi-region configuration
- [ ] Monitoring dashboards designed to replace RepServer monitoring
- [ ] End-to-end latency testing plan created for each REAL_TIME route
