# Sybase ASE to Cloud Spanner Incompatibility Matrix

Exhaustive mapping of Sybase ASE constructs to Cloud Spanner equivalents or migration strategies.

## Incompatibility Categories

### Category 1: NEEDS_MODIFICATION (Known Pattern Replacement)

These Sybase constructs have direct or near-direct Spanner equivalents. Migration involves syntax translation and minor logic adjustments.

| Sybase Construct | Spanner Equivalent | Migration Notes |
|-----------------|-------------------|-----------------|
| `IDENTITY` columns | `BIT_REVERSED_POSITIVE` sequence | Prevents write hotspots; values are not sequential. Applications must not depend on ordering. |
| `@@identity` | Return value from `GET_NEXT_SEQUENCE_VALUE` | Must be called explicitly; no automatic last-insert-id. |
| `SET ROWCOUNT n` | `LIMIT n` clause | Add LIMIT to SELECT; for DML, restructure with subquery. |
| `MONEY` / `SMALLMONEY` | `NUMERIC(19,4)` / `NUMERIC(10,4)` | Direct type mapping; verify arithmetic precision. |
| `DATETIME` / `SMALLDATETIME` | `TIMESTAMP` | Spanner TIMESTAMP is UTC-only; handle timezone conversion in application. |
| `TEXT` / `UNITEXT` | `STRING(MAX)` | Spanner STRING max is 2,621,440 characters. |
| `IMAGE` | `BYTES(MAX)` | Spanner BYTES max is 10,485,760 bytes. Consider Cloud Storage for larger objects. |
| `VARCHAR(n)` | `STRING(n)` | Direct mapping; Spanner uses UTF-8 character count. |
| `BIT` | `BOOL` | Direct mapping. |
| `SET CHAINED ON` | Default Spanner behavior (explicit transactions) | No change needed — Spanner always uses explicit transactions. |
| `SET CHAINED OFF` (unchained) | Autocommit per statement | Wrap each DML in its own transaction or use Spanner autocommit mode. |
| Sequences (ASE 15.7+) | `BIT_REVERSED_POSITIVE` sequence | Values will not be sequential; applications must not assume ordering. |
| `ISNULL()` | `IFNULL()` or `COALESCE()` | Direct function replacement. |
| `CONVERT()` | `CAST()` | Spanner uses CAST; some format codes need application-layer formatting. |
| `GETDATE()` | `CURRENT_TIMESTAMP` | Direct replacement; Spanner returns UTC. |
| `DATEDIFF()` | `TIMESTAMP_DIFF()` | Different function signature; map date parts. |
| `DATEADD()` | `TIMESTAMP_ADD()` | Different function signature. |
| `SUBSTRING()` | `SUBSTR()` | Spanner uses SUBSTR with 1-based indexing. |
| `LEN()` | `LENGTH()` | Direct replacement. |
| `CHARINDEX()` | `STRPOS()` | Different argument order in Spanner. |

### Category 2: REQUIRES_EXTRACTION (Application-Layer Migration)

These constructs have no Spanner equivalent and the logic must be moved to application code or GCP services.

| Sybase Construct | GCP Replacement | Architecture Pattern |
|-----------------|----------------|---------------------|
| Server-side cursors (`DECLARE CURSOR`) | Client-side iteration in application code | Application reads result set and iterates. Use Spanner streaming reads for large datasets. |
| `#temp_tables` (local) | Application-level collections (arrays, maps) | Store intermediate results in application memory. For large datasets, use Cloud Storage staging. |
| `##temp_tables` (global) | Shared state via Memorystore or Cloud Storage | If multiple sessions need shared temp data, use Memorystore (Redis). |
| `COMPUTE BY` / `COMPUTE SUM` | Application-layer aggregation | Fetch detail rows and compute subtotals in application code. Or use multiple queries with GROUP BY ROLLUP. |
| Triggers (INSERT/UPDATE/DELETE) | Change Streams + Cloud Run | Spanner Change Streams capture mutations; Cloud Run processes them asynchronously. Not synchronous like triggers. |
| Complex stored procedures | Cloud Run services | Extract business logic to microservices. Use Spanner client libraries for data access. |
| Orchestration procedures | Cloud Workflows + Cloud Run | Replace procedure call chains with Cloud Workflows orchestrating Cloud Run services. |
| Dynamic SQL (`EXEC(@sql)`) | Application-layer query building | Build queries in application code using parameterized Spanner client library calls. |
| Error handling (`@@error` checks) | Application-layer try/catch | Spanner client libraries throw exceptions; handle in application code. |
| `RAISERROR` with severity | Application-layer exceptions | Map Sybase error severities to application exception types. |
| `WAITFOR DELAY` | Cloud Scheduler + Cloud Run | Schedule delayed execution via Cloud Scheduler triggering Cloud Run. |
| `PRINT` / debug output | Cloud Logging | Application writes to Cloud Logging instead of database message output. |
| Cross-database JOINs (`db..table`) | Spanner multi-database with foreign keys, or Dataflow | If databases consolidate into one Spanner instance, use schemas. Otherwise, use Dataflow for cross-database operations. |
| Transaction savepoints (partial) | Spanner supports savepoints | Spanner DML transactions support savepoints; verify compatibility with specific usage. |
| Nested transactions | Flatten to single transaction | Spanner does not support nested transactions. Restructure to single transaction boundary. |

### Category 3: INCOMPATIBLE (Complete Redesign Required)

These constructs have no Spanner equivalent and no straightforward workaround. The entire approach must be redesigned.

| Sybase Construct | Redesign Approach | Effort Estimate |
|-----------------|-------------------|-----------------|
| `xp_cmdshell` (OS commands) | Cloud Run + Cloud Storage | High — must identify all OS interactions, build Cloud Run services, handle file I/O via Cloud Storage |
| Java-in-database (Sybase Java) | Cloud Run / GKE | High — extract Java classes, containerize, deploy to Cloud Run. Rewrite database interaction layer. |
| Proxy tables (CIS) | Federation via Dataflow or Cloud Run | High — CIS provides transparent cross-system queries. Must build explicit integration layer. |
| Open Server callbacks | Cloud Run with Spanner client | High — Open Server provides custom server-side handlers. Must redesign as Cloud Run services. |
| `CREATE EXISTING TABLE` (remote) | Dataflow / BigQuery federation | Medium — replace transparent remote table access with explicit ETL or federated queries. |
| `READTEXT` / `WRITETEXT` / `UPDATETEXT` | STRING/BYTES with standard DML | Medium — rewrite TEXT column manipulation to use standard DML on STRING(MAX) columns. |
| `sp_addtype` (custom types) | Resolve to base types | Low — Spanner has no user-defined types. Replace all custom type references with base types. |
| Component Integration Services (CIS) | Cloud Run integration layer | High — entire CIS framework must be replaced with explicit service-to-service communication. |

## Financial Domain Migration Patterns

### Settlement Processing

**Sybase pattern**: Cursor-driven settlement with temp table staging and cross-database position lookups.

**Spanner pattern**:
1. Cloud Run service reads pending trades via Spanner streaming read
2. Application code performs netting calculations
3. Single Spanner transaction writes settlement records
4. Change Stream triggers downstream notifications via Pub/Sub

### P&L Calculation

**Sybase pattern**: COMPUTE BY for subtotals, MONEY arithmetic, cross-database market data joins.

**Spanner pattern**:
1. Cloud Run service queries positions and market prices
2. Application code performs mark-to-market calculations using NUMERIC precision
3. Results written to Spanner P&L tables
4. Looker dashboard replaces COMPUTE BY report output

### Regulatory Reporting

**Sybase pattern**: Scheduled stored procedures with cross-database aggregation, WAITFOR-based scheduling.

**Spanner pattern**:
1. Cloud Scheduler triggers Cloud Run at required intervals
2. Cloud Run queries Spanner for regulatory data
3. BigQuery used for complex aggregation and historical analysis
4. Results written to Spanner and exported to regulatory systems

## Migration Effort Estimation

| Compatibility | Typical Effort per Object | Automation Potential |
|--------------|--------------------------|---------------------|
| COMPATIBLE | 0.5-2 hours | High — Harbourbridge can auto-convert most syntax |
| NEEDS_MODIFICATION | 2-8 hours | Medium — pattern-based replacement with manual verification |
| REQUIRES_EXTRACTION | 1-5 days | Low — requires application architecture design |
| INCOMPATIBLE | 1-3 weeks | None — full redesign required |

## Spanner-Specific Considerations

### Transaction Limits
- Maximum transaction size: 80,000 mutations per commit
- Maximum transaction duration: 10 seconds (online), 60 minutes (Partitioned DML)
- Settlement batches exceeding these limits must be partitioned

### Read/Write Patterns
- Spanner strongly consistent reads have higher latency than stale reads
- Use stale reads (bounded staleness) for reporting queries where real-time consistency is not required
- Financial calculations requiring point-in-time consistency should use exact staleness

### Data Locality
- Spanner multi-region configurations provide 99.999% availability
- For financial applications, use `nam-eur-asia1` or regional configurations based on regulatory requirements
- Data residency requirements may constrain Spanner region selection
