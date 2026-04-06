# Sybase-to-Spanner Migration Checklist Reference

Comprehensive checklist for orchestrating Sybase-to-Cloud Spanner database migration across all four phases, with financial compliance gates and market-hours-aware planning.

## Pre-Assessment Intake Questionnaire

Use this questionnaire during Step 0 (Intake & Scoping) to gather the information needed to scope the migration effort and select the right skills.

### Sybase Landscape

1. How many ASE instances are in scope? List instance names, versions (12.5, 15.x, 16.0, SAP ASE), and hosting locations.
2. How many databases exist per ASE instance? List database names and primary business functions.
3. What is the total data volume per database (data + indexes + logs)?
4. What are the largest tables by row count and storage size?
5. How many stored procedures, triggers, user-defined functions, and views exist per database?
6. Are there any Sybase IQ (SAP IQ) instances? Versions, data volumes, and primary use cases?
7. Is Sybase Replication Server in use? What topology? (warm standby, multi-site availability, data consolidation)
8. Are there Open Server applications acting as middleware or data gateways?
9. What character set is configured on each ASE? (UTF-8, ISO 8859-1, cp850, other)
10. What sort order is configured? (binary, dictionary, case-insensitive)
11. What page size is configured per ASE? (2K, 4K, 8K, 16K)
12. Are there any Java-in-the-database features in use (Sybase ASE Java classes)?
13. What Sybase client libraries are applications using? (CTLIB, DBLIB, jConnect, ODBC, ADO.NET)

### Database Architecture

14. Are there cross-database queries (three-part names: database.owner.object)?
15. Are there cross-server queries via CIS (Component Integration Services) or proxy tables?
16. What partition schemes are in use? (hash, range, list, round-robin, semantic)
17. Are there computed columns or function-based indexes?
18. What locking schemes are configured? (allpages, datapages, datarows)
19. Are there encrypted columns (Sybase column-level encryption)?
20. What login-to-user mappings and role-based security is configured?
21. Are there row-level security policies or views enforcing data access controls?

### Financial Domain

22. What financial functions does this system support? (trading, settlement, clearing, regulatory reporting, retail banking, risk management, reference data)
23. What market(s) does the system serve? (equities, fixed income, FX, derivatives, commodities)
24. What are the peak transaction rates? (transactions per second during market hours)
25. What is the end-of-day batch processing window? (start time, duration, hard deadline)
26. Are there month-end, quarter-end, or year-end extended processing windows?
27. What financial calculations are performed in stored procedures? (interest accrual, fee calculation, settlement amounts, NAV, P&L, VaR)
28. What external market data feeds does the system consume? (Bloomberg, Reuters, exchanges)
29. What downstream systems consume data from these databases? (risk engines, regulatory reporting, data warehouses)

### Compliance & Regulatory

30. Is the system in scope for SOX compliance? Which specific controls?
31. Does the system handle payment card data (PCI-DSS scope)?
32. Is the system subject to MiFID II transaction reporting?
33. Are there Dodd-Frank reporting obligations?
34. What are the data retention requirements? (7 years for SOX, varies by regulation)
35. Are there data residency requirements? (geographic constraints on data location)
36. What audit trail mechanisms exist today? (database audit tables, Sybase auditing, application logs)
37. Who are the external auditors and when is the next audit?

### Operational Context

38. What are the SLA requirements? (availability %, max downtime, RTO, RPO)
39. What is the current DR strategy? (Replication Server warm standby, companion server, backup/restore)
40. How is the database backed up? (Sybase dump database, third-party tools, frequency)
41. What monitoring tools are in use? (Foglight, DB-Spy, Spotlight, custom scripts, sp_sysmon)
42. How many DBAs support the Sybase environment? What is their cloud experience level?
43. What is the target migration timeline? Any hard deadlines? (Sybase license renewal, regulatory mandate)
44. What is the available budget for the migration program?
45. Are there any parallel migration efforts (application modernization, cloud migration)?

### Available Data for Analysis

46. Can we access MDA (Monitoring and Diagnostic) tables on each ASE?
47. Are there recent sp_sysmon reports available?
48. Can we access the statement cache and query plan cache?
49. Are production application logs available for query pattern analysis?
50. Is stored procedure source code in version control (Git, SVN)?
51. Are there existing data flow diagrams or architecture documents?
52. Is there a CMDB or configuration database cataloging the Sybase environment?

## Phase Gate Criteria

### Phase 1 to Phase 2 Gate

All of the following must be true before proceeding to Phase 2:

- [ ] All applicable Phase 1 skills have completed successfully
- [ ] T-SQL object inventory is complete with complexity scores (simple/medium/complex/rewrite-required)
- [ ] Schema inventory is complete with data type conversion matrix
- [ ] Sybase-specific data types requiring special mapping are cataloged:
  - [ ] `money` / `smallmoney` → precision requirements documented
  - [ ] `datetime` / `smalldatetime` → timestamp precision requirements documented
  - [ ] `image` / `text` / `unitext` → LOB migration strategy defined
  - [ ] `timestamp` (row version) → Spanner commit timestamp mapping defined
- [ ] Replication Server topology is fully documented (if in scope)
- [ ] All external integration points are cataloged with protocols and connection types
- [ ] No critical data gaps that would undermine Phase 2 analysis
- [ ] Component counts validated against Sybase system tables (`sysobjects`, `syscolumns`, `sysindexes`)
- [ ] Financial data types and precision requirements are documented
- [ ] Encrypted columns and security-sensitive data are identified
- [ ] Character set implications for Spanner UTF-8 are assessed
- [ ] Phase 1 summary document is saved to `phase-1-summary.md`
- [ ] `migration-state.json` is updated with Phase 1 completion status

### Phase 2 to Phase 3 Gate

All of the following must be true before proceeding to Phase 3:

- [ ] Cross-database data flows are fully mapped (inter-ASE and intra-ASE)
- [ ] All distributed transactions are identified (two-phase commit, XA, CIS)
- [ ] Transaction isolation levels are cataloged per database and per critical procedure
- [ ] Lock contention hot spots are identified with resolution recommendations
- [ ] Performance baselines established for parallel run comparison:
  - [ ] Transaction throughput (TPS) by hour of day
  - [ ] Query response times (P50, P95, P99) for critical queries
  - [ ] Batch processing duration for end-of-day jobs
  - [ ] Storage I/O profile (reads/writes per second)
- [ ] Batch processing chains mapped with dependency ordering
- [ ] ETL/ELT data flows documented with transformation logic locations
- [ ] Market-hours-sensitive transactions flagged
- [ ] Financial calculation data flows traced end-to-end
- [ ] Phase 2 summary document saved to `phase-2-summary.md`
- [ ] `migration-state.json` updated with Phase 2 completion status

### Phase 3 to Phase 4 Gate

All of the following must be true before proceeding to Phase 4:

- [ ] Dead components identified with evidence (last execution date, reference count)
- [ ] OLTP vs analytics workloads classified for every database
- [ ] Spanner vs BigQuery target assigned for each workload class
- [ ] IQ-to-BigQuery migration path defined (if IQ present)
- [ ] Scope reduction quantified (percentage of objects safe to exclude)
- [ ] **Financial compliance checks completed:**
  - [ ] SOX-controlled procedures identified — no removal without audit committee approval
  - [ ] PCI-DSS-scoped tables identified with encryption migration requirements
  - [ ] Regulatory reporting data flows flagged as highest-priority for accuracy validation
  - [ ] Audit trail tables identified with retention and immutability requirements
  - [ ] Data lineage for regulatory reports documented end-to-end
- [ ] Migration priority sequence established based on business criticality and dependencies
- [ ] Risk quadrants assigned to all in-scope databases
- [ ] Phase 3 summary document saved to `phase-3-summary.md`
- [ ] `migration-state.json` updated with Phase 3 completion status

### Phase 4 Completion Gate

All of the following must be true before producing the unified migration plan:

- [ ] Spanner DDL covers all in-scope tables
- [ ] Primary key design avoids hotspotting (no monotonically increasing keys)
- [ ] Interleaved table relationships defined for parent-child access patterns
- [ ] Secondary indexes support critical query patterns from performance profiling
- [ ] Data type mappings validated for financial precision requirements
- [ ] T-SQL business logic extracted with Spanner client library integration
- [ ] Spanner instance sizing based on Phase 2 performance baselines
- [ ] Multi-region configuration specified (if required)
- [ ] Change Streams configuration designed (if Replication Server in scope)
- [ ] BigQuery target architecture defined for analytics workloads (if applicable)
- [ ] **Parallel run validation plan documented:**
  - [ ] Comparison queries defined for every financial calculation
  - [ ] Zero tolerance confirmed for monetary amounts
  - [ ] Reconciliation process and frequency defined
  - [ ] Parallel run duration: minimum one full business cycle plus one quarter-end
  - [ ] Go/no-go criteria for cutover documented
  - [ ] Rollback trigger conditions defined
- [ ] `migration-state.json` updated with Phase 4 completion status

## Skill Selection Decision Matrix

| Sybase Component Present | Skills to Invoke | Notes |
|--------------------------|-----------------|-------|
| Stored procedures, triggers, functions | `sybase-tsql-analyzer` + `tsql-to-application-extractor` | Always paired: analyze first, then extract |
| Any database (always) | `sybase-schema-profiler` + `sybase-to-spanner-schema-designer` | Core pair for every migration |
| Replication Server | `sybase-replication-mapper` | Maps to Change Streams + Dataflow |
| Open Server, CTLIB, external integrations | `sybase-integration-cataloger` | External dependency discovery |
| Any database (always) | `sybase-data-flow-mapper` | Cross-database dependency mapping |
| Any database (always) | `sybase-transaction-analyzer` | Transaction pattern → Spanner mapping |
| Any database (always) | `sybase-performance-profiler` | Baseline for Spanner sizing and parallel run |
| Any database (always) | `sybase-dead-component-detector` | Scope reduction opportunity |
| Any database (always) | `sybase-analytics-assessor` | OLTP/analytics split decision |
| Sybase IQ present | `sybase-analytics-assessor` (IQ focus) | IQ-to-BigQuery migration path |

## Timeline Estimation Guidelines

### Small Migration (1-3 databases, < 500 GB, < 200 procedures)
- Phase 1: 1-2 weeks
- Phase 2: 1 week
- Phase 3: 1 week
- Phase 4: 2-3 weeks
- Parallel run: 4-6 weeks (minimum one month-end close)
- Total: 10-14 weeks

### Medium Migration (4-10 databases, 500 GB - 5 TB, 200-1000 procedures)
- Phase 1: 2-4 weeks
- Phase 2: 2-3 weeks
- Phase 3: 1-2 weeks
- Phase 4: 4-8 weeks
- Parallel run: 8-12 weeks (minimum one quarter-end close)
- Total: 18-30 weeks

### Large Migration (10+ databases, 5+ TB, 1000+ procedures)
- Phase 1: 4-8 weeks
- Phase 2: 3-6 weeks
- Phase 3: 2-4 weeks
- Phase 4: 8-16 weeks
- Parallel run: 12-16 weeks (minimum one quarter-end close, ideally year-end)
- Total: 30-52 weeks

### Factors That Extend Timeline
- Distributed transactions requiring decomposition: +2-4 weeks per transaction pattern
- Replication Server replacement with Change Streams: +4-8 weeks
- SOX audit committee approval cycles: +4-8 weeks per approval gate
- Market hours constraints limiting cutover windows: extends overall timeline
- IQ-to-BigQuery migration: +4-12 weeks depending on data volume and query complexity

## Risk Escalation Criteria

### Immediate Escalation (Block Phase Progression)
- Financial calculation discrepancy detected during any validation
- SOX-controlled data identified without audit trail migration plan
- PCI-DSS-scoped data identified without encryption migration plan
- Distributed transaction spanning databases that cannot be migrated together
- Performance regression exceeding 20% on critical financial calculations

### Management Escalation (Flag in Status Report)
- Scope increase exceeding 25% from initial estimate
- Timeline risk exceeding 4 weeks from original plan
- Sybase features with no direct Spanner equivalent requiring application redesign
- Team skill gaps requiring external training or consulting resources
- Budget risk from extended parallel run or additional Spanner capacity

### Monitor and Track
- Data type conversion edge cases requiring validation
- Character set conversion anomalies
- Sort order differences between Sybase and Spanner
- Query plan regression on non-critical queries
- Integration point protocol modernization opportunities
