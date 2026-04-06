# Financial System Migration Patterns Reference

Migration strategies and patterns specifically designed for financial system database migrations from Sybase ASE/IQ to Google Cloud Spanner and BigQuery.

## Parallel Run Pattern (Financial Validation)

**Description**: Run both Sybase and Spanner simultaneously, processing identical transactions in both systems and comparing financial outputs in real-time. Only Sybase results are used in production until Spanner is fully validated.

**When to use**:
- Financial calculations where any discrepancy is unacceptable (interest, fees, settlements, NAV, P&L)
- Regulatory requirements demand evidence of equivalence before cutover
- Auditors require validation documentation
- Trading systems where monetary precision is critical

**When to avoid**:
- Reference data tables with no financial calculations (use simple validation instead)
- Read-only reporting databases (validate reports, not transactions)
- Systems with side effects that cannot be safely duplicated (payment initiation, SWIFT messages)

**Implementation approach**:
1. Deploy Spanner alongside Sybase with identical schema (converted)
2. Implement dual-write at the application layer or via CDC pipeline
3. Build a reconciliation service that compares outputs:
   - Row-level comparison for financial amounts (zero tolerance)
   - Aggregate comparison for batch calculations
   - Statistical comparison for analytics workloads (within defined thresholds)
4. Run for minimum one full business cycle (month-end close)
5. Extend to quarter-end close for regulatory reporting validation
6. Document all discrepancies, root causes, and resolutions
7. Present validation evidence to audit committee for cutover approval

**Reconciliation queries**: Design comparison queries for every financial calculation:
```
-- Example: Settlement amount reconciliation
-- Sybase side
SELECT trade_id, settlement_amount, settlement_currency, settlement_date
FROM sybase_settlement_db..trades WHERE settlement_date = @comparison_date

-- Spanner side
SELECT trade_id, settlement_amount, settlement_currency, settlement_date
FROM trades WHERE settlement_date = @comparison_date

-- Comparison: zero tolerance on settlement_amount
-- Flag any row where ABS(sybase_amount - spanner_amount) > 0
```

**Duration guidelines**:
- Trading systems: minimum 2 months including one month-end
- Settlement systems: minimum 3 months including one quarter-end
- Regulatory reporting: one full reporting cycle (quarterly for most regulations)
- Retail banking: one full statement cycle plus one quarter-end

**Risk profile**: Low for data correctness, high for infrastructure cost (running two systems).

## Strangler Fig for Database Migration

**Description**: Incrementally migrate databases from Sybase to Spanner, starting with leaf databases (no inbound dependencies) and working toward hub databases. Use an abstraction layer to route queries to either Sybase or Spanner during transition.

**When to use**:
- Large Sybase landscape with many databases and cross-database dependencies
- Cannot migrate all databases simultaneously
- Need to demonstrate value early with low-risk databases
- Team needs to build Spanner expertise incrementally

**When to avoid**:
- Databases with tight bidirectional coupling that cannot be separated
- Very small environments where big-bang migration is simpler
- Distributed transactions spanning databases that must stay on the same platform

**Implementation approach**:
1. Map cross-database dependencies (Phase 2 output)
2. Identify leaf databases with no inbound cross-database queries
3. Migrate leaf databases first, updating applications to point to Spanner
4. Maintain temporary cross-platform views or proxy tables for transition period
5. Progressively migrate upstream databases as downstream ones complete
6. Hub databases (most dependencies) migrate last

**Migration ordering algorithm**:
```
1. Build dependency graph from Phase 2 data flow mapping
2. Topological sort to identify migration order
3. Leaf nodes (no inbound dependencies) = Wave 1
4. Nodes whose only dependencies are Wave 1 = Wave 2
5. Continue until hub databases are reached
6. Hub databases with bidirectional dependencies = final wave (requires coordinated cutover)
```

**Risk profile**: Medium — requires maintaining cross-platform compatibility during transition.

## Market-Hours-Aware Cutover Pattern

**Description**: Plan and execute database cutovers within market-hours-aware windows that avoid active trading, settlement processing, and regulatory reporting deadlines.

**When to use**:
- Any financial system with market hours constraints
- Trading systems connected to exchanges
- Settlement systems with T+1/T+2 deadlines
- Regulatory reporting systems with filing deadlines

**Cutover windows by system type**:

| System Type | Acceptable Cutover Window | Blackout Periods |
|-------------|--------------------------|------------------|
| Trading (equities) | Saturday 00:00 - Sunday 12:00 | Monday-Friday 04:00-20:00 ET |
| Trading (FX) | Sunday 15:00 - Sunday 17:00 ET | Sunday 17:00 - Friday 17:00 ET (24h market) |
| Settlement | Weeknight 22:00 - 04:00 | T+1 processing window, month-end |
| Regulatory reporting | Post-filing weekend | Filing deadline week |
| Retail banking | Saturday 23:00 - Sunday 06:00 | Statement generation, month-end |
| Risk management | Weeknight 23:00 - 05:00 | Market open through EOD risk runs |

**Blackout calendar**:
- Month-end: last 3 business days of each month
- Quarter-end: last 5 business days of each quarter
- Year-end: December 15 through January 15
- Regulatory filing dates: varies by regulation
- Exchange maintenance windows: coordinate with exchange calendars

**Cutover runbook template**:
1. T-48h: Final parallel run reconciliation, go/no-go decision
2. T-24h: Communication to all stakeholders, confirm team availability
3. T-4h: Begin controlled shutdown of Sybase write access
4. T-2h: Final data sync from Sybase to Spanner
5. T-1h: Validation queries on Spanner, financial reconciliation
6. T-0: Switch application connection strings to Spanner
7. T+1h: Smoke tests, critical transaction validation
8. T+2h: Monitor error rates, latency, financial calculations
9. T+4h: Preliminary go/no-go for maintaining cutover
10. T+24h: Full business day validation, regulatory reporting check
11. T+48h: Final go/no-go, begin Sybase decommissioning timeline

**Rollback triggers**:
- Any financial calculation discrepancy (zero tolerance)
- Transaction error rate exceeding 0.1%
- Latency regression exceeding 50% on critical paths
- Regulatory reporting failure
- Unresolved data integrity issue

## Data Type Precision Migration Pattern

**Description**: Systematic approach to migrating Sybase financial data types to Spanner with guaranteed precision preservation.

**Sybase money type handling**:

| Sybase Type | Range | Precision | Spanner Target | Verification |
|-------------|-------|-----------|----------------|-------------|
| `money` | -922,337,203,685,477.5808 to 922,337,203,685,477.5807 | 4 decimal places | `NUMERIC` (precision 38, scale 9) | Compare to 4 decimal places |
| `smallmoney` | -214,748.3648 to 214,748.3647 | 4 decimal places | `NUMERIC` | Compare to 4 decimal places |
| `decimal(p,s)` | Varies | User-defined | `NUMERIC` or `FLOAT64` | Match original precision |
| `float` | IEEE 754 double | ~15 significant digits | `FLOAT64` | IEEE 754 comparison |
| `real` | IEEE 754 single | ~7 significant digits | `FLOAT64` (promoted) | Precision improvement |

**Rounding behavior verification**:
- Sybase uses Banker's rounding (round half to even) for money arithmetic
- Spanner NUMERIC uses standard IEEE rounding
- **Critical**: Test every financial calculation to verify rounding matches
- Document any rounding differences and get business approval for the approach

**Validation approach**:
1. Extract sample financial calculations from production (1000+ representative transactions)
2. Run identical calculations on both Sybase and Spanner
3. Compare results to the required decimal precision
4. Flag any discrepancies for investigation
5. Document root cause (rounding, precision, overflow) and resolution
6. Get sign-off from finance team on any accepted differences

## Transaction Pattern Decomposition

**Description**: Systematic approach to decomposing Sybase transaction patterns into Spanner-compatible equivalents.

**Sybase isolation level mapping**:

| Sybase Level | Sybase Behavior | Spanner Equivalent | Migration Notes |
|-------------|----------------|-------------------|-----------------|
| Level 0 (Read Uncommitted) | Dirty reads allowed | Not available | Upgrade to Spanner default (external consistency) |
| Level 1 (Read Committed) | No dirty reads | Spanner default (strong reads) | Direct mapping, Spanner provides stronger guarantees |
| Level 2 (Repeatable Read) | No non-repeatable reads | Spanner default | Spanner provides this natively |
| Level 3 (Serializable) | Full serialization | Spanner default | Spanner provides external consistency (stronger) |
| `HOLDLOCK` | Hold shared locks to end of transaction | Not needed | Spanner TrueTime handles this automatically |
| `NOHOLDLOCK` | Release locks early | Not applicable | Spanner manages concurrency internally |

**Distributed transaction decomposition**:
- Sybase two-phase commit across ASE instances → Spanner single-instance (if data consolidated) or application-level saga pattern
- CIS distributed queries → Spanner federated queries (BigQuery) or materialized views
- DTM (Distributed Transaction Manager) → Cloud Workflows for orchestration

**Lock contention resolution**:
- Sybase page-level locking → Spanner cell-level locking (finer granularity)
- Sybase table-level locks for batch operations → Spanner partitioned DML
- Sybase `sp_lock` hot spots → Spanner interleaved tables to co-locate related data

## Batch Processing Migration Pattern

**Description**: Migrate Sybase end-of-day and periodic batch processing to cloud-native equivalents.

**Sybase batch pattern to GCP mapping**:

| Sybase Pattern | GCP Target | Notes |
|----------------|-----------|-------|
| `isql` scripts in cron | Cloud Run Jobs + Cloud Scheduler | Direct replacement |
| Stored procedure batch chains | Cloud Workflows orchestrating Cloud Run Jobs | Decompose proc chains |
| BCP (Bulk Copy Program) | Spanner batch write API or Dataflow | For bulk data loads |
| Sybase IQ load jobs | BigQuery load jobs or Dataflow | For analytics data |
| End-of-day reconciliation | Cloud Run Jobs with Spanner reads | Financial calc validation |
| Month-end close procedures | Cloud Workflows (complex orchestration) | Multi-step with gates |

**Batch window analysis**:
1. Map current batch window (start time, duration, dependencies)
2. Identify parallelizable batch jobs
3. Estimate Spanner batch performance (partitioned DML for large operations)
4. Design Cloud Workflows DAG for batch orchestration
5. Test batch completion within required window
6. Plan for batch window compression (Spanner is typically faster for batch operations)

## CDC Replacement Pattern (Replication Server to Change Streams)

**Description**: Replace Sybase Replication Server with Spanner Change Streams and Dataflow pipelines.

**Component mapping**:

| Sybase Component | GCP Replacement | Purpose |
|-----------------|-----------------|---------|
| RepAgent | Spanner Change Streams | Capture data changes |
| Replication Server | Dataflow (streaming) | Route and transform changes |
| Subscriptions | Pub/Sub topics + BigQuery subscriptions | Deliver changes to consumers |
| Warm standby | Spanner multi-region | Built-in HA/DR |
| rs_subcmp (comparison) | Custom reconciliation Cloud Run Job | Data comparison |

**Migration approach**:
1. Catalog all Replication Server subscriptions and routes (Phase 1)
2. Map each subscription to a Change Streams + Dataflow pipeline
3. Design Pub/Sub topic structure for change event distribution
4. Implement Dataflow pipelines with transformation logic
5. Run old (RepServer) and new (Change Streams) in parallel during transition
6. Validate change event delivery latency meets SLAs
7. Cut over consumers from Replication Server to Change Streams + Pub/Sub

**Latency considerations**:
- Sybase Replication Server: typically 1-5 second latency
- Spanner Change Streams + Dataflow: typically sub-second to 2 seconds
- Validate that downstream consumers tolerate any latency differences
- Financial trading systems may require sub-100ms latency (evaluate carefully)
