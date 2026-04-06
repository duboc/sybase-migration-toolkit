# Financial Protocol Integration Patterns

Reference for migrating financial messaging protocol integrations from Sybase ASE to GCP services.

## FIX Protocol (Financial Information eXchange)

### Overview

FIX is the standard protocol for electronic trading communication. FIX engines typically persist trade data to Sybase for order management, execution reporting, and regulatory audit trails.

### Sybase Integration Pattern

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Counterparty │◄───►│  FIX Engine  │◄───►│  Sybase ASE  │
│  (Exchange,  │ FIX │ (QuickFIX,   │ CT  │  (tradedb)   │
│   Broker)    │     │  Cameron)    │ Lib │              │
└──────────────┘     └──────────────┘     └──────────────┘
```

**Typical Sybase tables:**
- `fix_sessions` — FIX session configuration (SenderCompID, TargetCompID, BeginString)
- `fix_messages` — Raw FIX message log for audit/replay
- `orders` — Parsed order data from NewOrderSingle (35=D)
- `executions` — Execution reports (35=8)
- `order_cancel_requests` — Cancel/replace requests (35=F, 35=G)

**Detection patterns:**
```
# FIX engine config files
[SESSION]
BeginString=FIX.4.4
SenderCompID=TRADING_FIRM
TargetCompID=EXCHANGE_A
DataDictionary=FIX44.xml
PersistMessages=Y
JdbcDriver=com.sybase.jdbc4.jdbc.SybDriver
JdbcURL=jdbc:sybase:Tds:trade-db-01:5000/tradedb
JdbcStoreTable=fix_messages
```

### GCP Migration Architecture

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────┐
│ Counterparty │◄───►│  Cloud Run       │◄───►│ Cloud Spanner│
│  (Exchange,  │ FIX │  (FIX Engine)    │gRPC │  (tradedb)   │
│   Broker)    │     │                  │     │              │
└──────────────┘     └────────┬─────────┘     └──────────────┘
                              │
                     ┌────────▼─────────┐
                     │    Pub/Sub       │
                     │ (trade events)   │
                     └────────┬─────────┘
                              │
              ┌───────────────┼───────────────┐
     ┌────────▼────────┐  ┌──▼───────────┐  ┌▼────────────────┐
     │ Cloud Run       │  │ Dataflow     │  │ Cloud Run       │
     │ (Risk Service)  │  │ (Analytics)  │  │ (Compliance)    │
     └─────────────────┘  └──────────────┘  └─────────────────┘
```

**Key migration considerations:**
- FIX engine must maintain sub-millisecond message processing latency
- Cloud Run provides auto-scaling for burst traffic (market open/close)
- Spanner replaces Sybase for trade persistence with global consistency
- Pub/Sub distributes trade events to downstream consumers (replaces Sybase replication)
- FIX message audit log: consider BigQuery for long-term storage (cost-effective for write-heavy audit)

**Effort estimate**: 2-4 weeks for FIX engine persistence layer migration.

## SWIFT (Society for Worldwide Interbank Financial Telecommunication)

### Overview

SWIFT handles international payment messaging. Sybase stores SWIFT message data, payment instructions, and compliance/sanctions screening results.

### Sybase Integration Pattern

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ SWIFT Network│◄───►│ SWIFT Gateway│◄───►│  Sybase ASE  │
│ (SWIFTNet)   │MT/MX│ (Alliance    │ CT  │ (paymentdb)  │
│              │     │  Access)     │ Lib │              │
└──────────────┘     └──────────────┘     └──────────────┘
                              │
                     ┌────────▼─────────┐
                     │ Sanctions        │
                     │ Screening Engine │
                     └──────────────────┘
```

**Typical Sybase tables:**
- `swift_messages` — Raw MT/MX messages (MT103, MT202, pain.001, etc.)
- `payments` — Parsed payment instructions
- `beneficiaries` — Beneficiary account information
- `sanctions_results` — Sanctions screening results (OFAC, EU, UN lists)
- `payment_audit` — Full audit trail for regulatory compliance

**Detection patterns:**
```
# SWIFT message types in code/config
MT103  — Single Customer Credit Transfer
MT202  — General Financial Institution Transfer
MT300  — Foreign Exchange Confirmation
MT940  — Customer Statement Message
pain.001 — Customer Credit Transfer Initiation (ISO 20022)
camt.053 — Bank To Customer Statement (ISO 20022)
```

### GCP Migration Architecture

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────┐
│ SWIFT Network│◄───►│  Cloud Run       │◄───►│ Cloud Spanner│
│ (SWIFTNet)   │MT/MX│  (SWIFT Handler) │gRPC │ (paymentdb)  │
│              │     │                  │     │              │
└──────────────┘     └────────┬─────────┘     └──────────────┘
                              │
                     ┌────────▼─────────┐
                     │   Cloud HSM      │
                     │ (Message Signing)│
                     └──────────────────┘
```

**Key migration considerations:**
- **Cloud HSM** replaces on-premise HSM for SWIFT message signing and encryption
- **Compliance**: SWIFT CSP (Customer Security Programme) requirements must be met on GCP
- **Data residency**: Payment data may have jurisdictional restrictions — verify Spanner region configuration
- **Sanctions screening**: Can remain as-is or migrate to Cloud Run; must maintain <100ms screening latency
- **Audit trail**: Spanner with commit timestamps for payment audit; BigQuery for long-term archival

**Effort estimate**: 4-8 weeks due to compliance and security requirements.

## IBM MQ (MQSeries) Integration

### Overview

IBM MQ provides reliable messaging between Sybase and other systems. Common in financial enterprises for trade routing, settlement instructions, and market data distribution.

### Sybase Integration Pattern

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Upstream     │ MQ  │  MQ Trigger  │ CT  │  Sybase ASE  │
│ System       │────►│  Monitor     │────►│  (tradedb)   │
│ (Trade       │     │              │ Lib │              │
│  Capture)    │     └──────────────┘     └──────────────┘
└──────────────┘

┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Sybase ASE  │ CT  │  MQ Client   │ MQ  │ Downstream   │
│  (tradedb)   │────►│  Application │────►│ System       │
│              │ Lib │              │     │ (Settlement) │
└──────────────┘     └──────────────┘     └──────────────┘
```

**Common MQ-Sybase patterns:**
- **MQ Trigger → Sybase**: MQ trigger monitor detects message arrival, invokes program that reads message and inserts into Sybase
- **Sybase → MQ**: Application reads from Sybase (often via cursor), formats message, puts to MQ queue
- **Request/Reply via MQ**: Synchronous request through MQ where Sybase provides the data
- **Transactional MQ + Sybase**: XA transactions coordinating MQ put/get with Sybase DML

**Detection patterns:**
```
# MQ configuration
DEFINE QLOCAL('TRADE.IN') +
  PROCESS('TRADE.PROCESS') +
  TRIGGER +
  TRIGTYPE(FIRST) +
  INITQ('SYSTEM.DEFAULT.INITIATION.QUEUE')

DEFINE PROCESS('TRADE.PROCESS') +
  APPLICID('/opt/apps/trade_loader') +
  APPLTYPE(UNIX)
```

### GCP Migration Architecture

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────┐
│ Upstream     │Pub/ │  Cloud Run       │gRPC │ Cloud Spanner│
│ System       │Sub  │  (Message        │     │  (tradedb)   │
│              │────►│   Consumer)      │────►│              │
└──────────────┘     └──────────────────┘     └──────────────┘

OR (hybrid during migration):

┌──────────────┐     ┌──────────────┐     ┌──────────────────┐     ┌──────────────┐
│ IBM MQ       │     │ MQ-Pub/Sub   │     │  Cloud Run       │     │ Cloud Spanner│
│ Queue        │────►│  Connector   │────►│  (Consumer)      │────►│  (tradedb)   │
│              │     │              │     │                  │     │              │
└──────────────┘     └──────────────┘     └──────────────────┘     └──────────────┘
```

**Key migration considerations:**
- **Ordering**: MQ guarantees message ordering within a queue. Pub/Sub supports ordering keys — use `account_id` or `trade_id` as ordering key.
- **Transactional messaging**: XA transactions (MQ + Sybase) have no direct equivalent. Use Pub/Sub with Spanner in an "outbox pattern" for exactly-once semantics.
- **Trigger monitors**: Replace with Pub/Sub push subscriptions to Cloud Run endpoints.
- **Hybrid period**: Use IBM MQ connector for Pub/Sub during transition to avoid cutting over all producers/consumers simultaneously.
- **Dead letter queues**: Pub/Sub has native dead-letter topic support; configure for failed message handling.

**Effort estimate**: 1-3 weeks per queue/integration depending on complexity.

## Batch File Feed Patterns

### BCP (Bulk Copy Program)

**Sybase BCP patterns:**
```bash
# BCP OUT: Extract data from Sybase to flat file
bcp tradedb..daily_positions out /data/exports/positions_20260331.dat \
    -S TRADE_SERVER -U batch_user -P password \
    -c -t"|" -r"\n"

# BCP IN: Load flat file into Sybase
bcp tradedb..market_prices in /data/feeds/prices_20260331.dat \
    -S TRADE_SERVER -U batch_user -P password \
    -c -t"|" -r"\n" -b 10000

# BCP with format file
bcp tradedb..trades out /data/exports/trades.dat \
    -S TRADE_SERVER -U batch_user -P password \
    -f /data/formats/trades.fmt
```

**GCP equivalents:**

| BCP Operation | GCP Replacement | Implementation |
|--------------|----------------|----------------|
| `bcp out` (extract) | Dataflow → Cloud Storage | Dataflow reads from Spanner, writes CSV/Avro to GCS |
| `bcp in` (load) | Cloud Storage → Dataflow → Spanner | Dataflow reads from GCS, writes to Spanner via mutations |
| Format files | Dataflow schema definition | Avro schema or Dataflow PCollection schema |
| Batch size (`-b`) | Dataflow bundle size / Spanner mutation limit | Respect 80,000 mutations per commit |

### isql Batch Scripts

**Sybase isql patterns:**
```bash
# Execute SQL script
isql -S TRADE_SERVER -U batch_user -P password -i /scripts/eod_report.sql -o /reports/eod.txt

# Inline SQL
isql -S TRADE_SERVER -U batch_user -P password <<EOF
SELECT account_id, SUM(balance)
FROM balances
WHERE balance_date = GETDATE()
GROUP BY account_id
go
EOF
```

**GCP equivalents:**
- `gcloud spanner databases execute-sql` for ad-hoc queries
- Spanner client library scripts (Python/Java) for complex batch operations
- Cloud Scheduler + Cloud Run for scheduled batch SQL

## Integration Testing Checklist

- [ ] JDBC connections validated with Spanner JDBC driver
- [ ] ODBC DSNs reconfigured for Spanner ODBC driver
- [ ] All SQL queries tested against GoogleSQL syntax
- [ ] FIX engine trade persistence verified with Spanner
- [ ] SWIFT message handling latency validated
- [ ] MQ-to-Pub/Sub message ordering verified
- [ ] BCP operations replaced with Dataflow pipelines
- [ ] Connection pooling settings tuned for Spanner session management
- [ ] Authentication migrated from Sybase native to IAM service accounts
- [ ] Error handling updated for Spanner exception model
