# Regulatory Compliance Guide for Sybase-to-Spanner Migration

Comprehensive compliance mapping for SOX, PCI-DSS, MiFID II, Dodd-Frank, and Basel III/IV controls during database migration from Sybase ASE to Google Cloud Spanner.

## SOX (Sarbanes-Oxley Act) Compliance

### SOX Controls Affected by Database Migration

| SOX Control Area | Sybase Implementation | Spanner Implementation | Migration Risk | Mitigation |
|-----------------|----------------------|----------------------|---------------|------------|
| Financial data integrity | Sybase constraints, triggers | Spanner constraints, application-layer validation | Medium | Parallel run validation for all financial calculations |
| Audit trail | Sybase audit tables, triggers | Spanner commit timestamps, Change Streams, audit tables | High | Design audit table migration before any data migration |
| Separation of duties | Sybase roles, login/user mapping | Cloud IAM, Spanner database roles | Medium | Map all Sybase roles to IAM roles before cutover |
| Change management | Sybase DDL scripts, manual approvals | Terraform/IaC, Cloud Build pipelines | Low | IaC improves controls over manual DDL |
| Access controls | Sybase GRANT/REVOKE, proxy tables | Spanner IAM, fine-grained access control | Medium | Audit all grants and replicate in IAM |
| Data retention | Sybase table partitioning, archival scripts | Spanner TTL, BigQuery long-term storage | Medium | Verify retention periods meet 7-year requirement |
| Backup and recovery | Sybase dump database, transaction logs | Spanner PITR, export to GCS | Low | Spanner PITR provides better RPO than Sybase dump |

### SOX Audit Trail Migration Strategy

**Principle**: Audit trail continuity must be maintained throughout migration. There must be no gap in the audit record.

**Approach**:
1. **Pre-migration**: Export complete Sybase audit trail to BigQuery for long-term retention
2. **During migration**: Dual-write audit events to both Sybase and Spanner audit tables
3. **Post-migration**: Spanner audit tables become the primary record; BigQuery retains historical
4. **Verification**: Reconcile audit event counts between Sybase and Spanner during parallel run

**Spanner audit table design**:
```sql
CREATE TABLE AuditTrail (
  audit_id STRING(36) NOT NULL,
  table_name STRING(128) NOT NULL,
  record_key STRING(500) NOT NULL,
  action STRING(10) NOT NULL,  -- INSERT, UPDATE, DELETE
  field_name STRING(128),
  old_value STRING(MAX),
  new_value STRING(MAX),
  changed_by STRING(100) NOT NULL,
  changed_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
  application_name STRING(100),
  session_id STRING(100),
  ip_address STRING(45),
) PRIMARY KEY (audit_id);

-- Index for regulatory queries (who changed what, when)
CREATE INDEX idx_audit_by_table_time ON AuditTrail(table_name, changed_at DESC);
CREATE INDEX idx_audit_by_user ON AuditTrail(changed_by, changed_at DESC);
CREATE INDEX idx_audit_by_record ON AuditTrail(table_name, record_key, changed_at DESC);
```

**SOX auditor communication plan**:
- Notify external auditors 6 months before planned migration
- Provide migration plan with audit trail continuity documentation
- Schedule pre-migration audit review of controls mapping
- Provide parallel run evidence package before cutover approval
- Schedule post-migration audit of new controls within one quarter

### SOX-Specific Phase Gate Requirements

Before any database cutover involving SOX-controlled data:
- [ ] Audit committee has reviewed and approved the migration plan
- [ ] External auditors have reviewed controls mapping documentation
- [ ] Audit trail continuity is verified through parallel run evidence
- [ ] IAM roles replicate all Sybase separation-of-duties controls
- [ ] Data retention mechanisms are tested and validated
- [ ] Backup and recovery procedures are documented and tested
- [ ] Change management process for Spanner DDL changes is in place

## PCI-DSS (Payment Card Industry Data Security Standard)

### PCI-DSS Requirements Mapping

| PCI-DSS Requirement | Sybase Control | Spanner / GCP Control | Migration Notes |
|---------------------|---------------|----------------------|-----------------|
| Req 3: Protect stored cardholder data | Sybase column-level encryption, data masking | Spanner CMEK, Cloud KMS, application-layer encryption | Re-encrypt during migration; never expose PAN in transit |
| Req 3.4: Render PAN unreadable | Sybase encryption functions | Spanner CMEK + application tokenization | Consider tokenization service (e.g., DLP API) |
| Req 7: Restrict access by business need | Sybase GRANT/REVOKE per column | Spanner IAM + fine-grained access control + VPC SC | Map column-level grants to IAM policies |
| Req 8: Identify and authenticate access | Sybase login/password | Cloud IAM, Workload Identity | Stronger authentication via IAM |
| Req 10: Track and monitor all access | Sybase auditing, sysaudits table | Cloud Audit Logs, Spanner audit | Automatic with GCP; more comprehensive than Sybase |
| Req 10.5: Secure audit trails | Sybase table permissions | Cloud Audit Logs (immutable), GCS WORM | Improved immutability guarantees |
| Req 11.5: Change detection | Manual file integrity monitoring | Cloud Asset Inventory, Config Connector | Automated change detection |
| Req 12.10: Incident response | Manual procedures | Cloud Security Command Center, Chronicle | Improved detection and response |

### PCI-DSS Data Migration Strategy

**Cardholder Data Environment (CDE) migration**:

1. **Scope identification** (Phase 1): Identify all tables and columns containing:
   - Primary Account Number (PAN)
   - Cardholder name
   - Expiration date
   - Service code
   - Sensitive authentication data (must NEVER be stored post-authorization)

2. **Encryption migration**:
   - Generate new Cloud KMS encryption keys before migration
   - Decrypt from Sybase encryption → re-encrypt with Cloud KMS in transit
   - **Never transmit PAN in cleartext** during migration, even within VPC
   - Use Dataflow with Cloud KMS integration for encrypted data pipeline
   - Validate encryption at rest on Spanner using CMEK verification

3. **Tokenization opportunity**:
   - Migration is an ideal time to implement tokenization
   - Replace stored PANs with tokens via Cloud DLP API or third-party tokenization
   - Reduces PCI-DSS scope for Spanner environment
   - Store tokens in Spanner, actual PANs in a separate tokenization vault

4. **Network segmentation**:
   - Spanner CDE instance in a dedicated VPC with VPC Service Controls
   - Private Google Access only (no public IP)
   - Cloud NAT for outbound if required
   - VPC flow logs enabled for all CDE network traffic

### PCI-DSS Specific Phase Gate Requirements

Before migrating any PCI-DSS-scoped database:
- [ ] CDE scope is documented and approved by QSA (Qualified Security Assessor)
- [ ] Cloud KMS keys are generated and key management procedures documented
- [ ] Encryption migration procedure is tested with non-production data
- [ ] VPC Service Controls perimeter is configured around Spanner CDE instance
- [ ] IAM policies replicate Sybase column-level access controls
- [ ] Cloud Audit Logs are configured and retention meets PCI-DSS requirements
- [ ] Tokenization strategy is approved (if implementing during migration)
- [ ] QSA has reviewed and approved the migration approach

## MiFID II (Markets in Financial Instruments Directive)

### MiFID II Requirements Affected by Migration

| MiFID II Requirement | Impact Area | Sybase Implementation | Spanner Implementation |
|---------------------|-------------|----------------------|----------------------|
| Transaction reporting (RTS 25) | Trade execution data | Sybase tables with regulatory reporting queries | Spanner tables with BigQuery for complex reporting |
| Best execution (RTS 27/28) | Order and execution data | Sybase execution venue analysis | Spanner + BigQuery for execution quality analysis |
| Record keeping (Article 16) | All communications and transactions | Sybase archival tables | Spanner + BigQuery cold storage + GCS archive |
| Clock synchronization | Timestamp accuracy | Sybase server time (NTP) | Spanner TrueTime (GPS + atomic clocks, microsecond accuracy) |
| Order record keeping | Full order lifecycle | Sybase order tables with audit triggers | Spanner with commit timestamps + Change Streams |

### Transaction Reporting Migration

**MiFID II transaction reporting fields that require precision migration**:

| Field | Sybase Type | Spanner Type | Validation |
|-------|------------|-------------|------------|
| Transaction reference number | `varchar(52)` | `STRING(52)` | Exact match |
| Trading venue transaction ID | `varchar(52)` | `STRING(52)` | Exact match |
| Executing entity ID (LEI) | `char(20)` | `STRING(20)` | Exact match |
| Price | `money` or `decimal(18,8)` | `NUMERIC` | Precision to 8 decimal places |
| Quantity | `decimal(25,5)` | `NUMERIC` | Precision to 5 decimal places |
| Notional amount | `money` | `NUMERIC` | Precision to 4 decimal places |
| Timestamp | `datetime` | `TIMESTAMP` | Microsecond precision (Spanner exceeds requirement) |
| Venue | `char(4)` (MIC code) | `STRING(4)` | Exact match |

**Reporting continuity plan**:
1. Validate that all MiFID II transaction reports produce identical output from Spanner
2. Run parallel reporting during parallel run period
3. Submit test reports from Spanner to ARM (Approved Reporting Mechanism) in test mode
4. Get regulatory approval for reporting system change (if required by NCA)
5. Switch production reporting to Spanner only after successful test submissions

### Clock Synchronization Improvement

MiFID II RTS 25 requires timestamp accuracy to 1 microsecond for high-frequency trading and 1 millisecond for other activities.

- **Sybase**: Relies on OS-level NTP (typically 1-10ms accuracy)
- **Spanner**: Uses TrueTime (GPS + atomic clocks, microsecond accuracy)
- **Migration benefit**: Spanner provides significantly better timestamp accuracy than Sybase, exceeding MiFID II requirements
- **Validation**: Verify that application-layer timestamps are also derived from TrueTime (use commit timestamps)

## Dodd-Frank Act Compliance

### Dodd-Frank Requirements Mapping

| Dodd-Frank Area | Database Impact | Migration Consideration |
|----------------|-----------------|----------------------|
| Swap data reporting | Trade repository data feeds | Ensure reporting pipeline continuity during migration |
| Real-time public reporting | Trade data publication | No interruption allowed; use parallel run |
| Clearing mandates | Clearing house interfaces | Test all clearing interfaces with Spanner data source |
| Trade execution | SEF/exchange integration | Validate order routing with new database backend |
| Position limits | Position calculation queries | Verify position aggregation calculations in Spanner |
| Large trader reporting | Threshold monitoring queries | Validate threshold calculations produce identical results |

### Swap Data Repository (SDR) Reporting Continuity

**Migration approach for SDR reporting**:
1. Map all SDR reporting queries from Sybase stored procedures
2. Replicate reporting logic in Cloud Run services reading from Spanner
3. Run parallel SDR reports during migration (both Sybase and Spanner sourced)
4. Validate field-level accuracy for all CFTC/SEC required fields
5. Coordinate cutover timing with SDR provider (DTCC, ICE, Bloomberg)
6. Maintain Sybase as backup reporting source for 30 days post-cutover

## Basel III/IV Compliance

### Capital Calculation Migration

| Basel Calculation | Database Dependency | Migration Risk | Mitigation |
|------------------|-------------------|---------------|------------|
| Risk-Weighted Assets (RWA) | Position data, exposure calculations | High | Parallel run with daily RWA reconciliation |
| Liquidity Coverage Ratio (LCR) | Cash flow projections, HQLA classification | High | Validate LCR calculations to 2 decimal places |
| Net Stable Funding Ratio (NSFR) | Funding source classification, maturity buckets | Medium | Reconcile NSFR components daily during parallel run |
| Credit Valuation Adjustment (CVA) | Counterparty exposure, market data | High | CVA calculation validation with production data |
| Leverage Ratio | On/off balance sheet exposures | Medium | Reconcile exposure aggregations |
| Fundamental Review of Trading Book (FRTB) | Sensitivity calculations, scenario analysis | High | Run FRTB scenarios in parallel on both platforms |

### Risk Calculation Validation Strategy

**Daily reconciliation during parallel run**:
```
For each Basel calculation:
1. Run calculation on Sybase (production)
2. Run identical calculation on Spanner (parallel)
3. Compare results:
   - RWA: tolerance ±$1 (monetary)
   - LCR/NSFR: tolerance ±0.01% (ratio)
   - CVA: tolerance ±$1 (monetary)
4. Log all comparisons with timestamps
5. Investigate any variance exceeding tolerance
6. Root cause analysis for every discrepancy
7. Weekly summary report to risk committee
```

**Regulatory notification requirements**:
- Some regulators require notification before changing core risk calculation infrastructure
- Check with compliance team whether NCA/PRA/Fed notification is required
- Prepare regulatory briefing document explaining:
  - What is changing (database platform)
  - What is not changing (calculation logic, reporting outputs)
  - Validation approach (parallel run evidence)
  - Rollback plan (ability to revert to Sybase)

## Cross-Regulation Compliance Matrix

### Data Classification for Migration Prioritization

| Data Category | SOX | PCI-DSS | MiFID II | Dodd-Frank | Basel | Migration Priority |
|--------------|-----|---------|----------|------------|-------|-------------------|
| Financial transactions | Yes | - | Yes | Yes | Yes | Critical — parallel run required |
| Payment card data | - | Yes | - | - | - | Critical — encryption migration |
| Trade execution data | Yes | - | Yes | Yes | Yes | Critical — reporting continuity |
| Audit trails | Yes | Yes | Yes | - | - | Critical — no gaps allowed |
| Position/exposure data | Yes | - | - | Yes | Yes | High — risk calculation dependency |
| Reference data | - | - | Yes | - | - | Medium — can migrate early |
| Historical/archive data | Yes | - | Yes | - | - | Low — BigQuery migration |
| Operational/monitoring | - | - | - | - | - | Low — can migrate last |

### Compliance Gate Checklist (All Regulations)

Before any production database cutover:

**Pre-Migration (8-12 weeks before)**:
- [ ] Compliance team has reviewed and approved migration plan
- [ ] External auditors notified (SOX)
- [ ] QSA consulted (PCI-DSS)
- [ ] Regulatory notification filed (if required by NCA for MiFID II/Basel)
- [ ] SDR provider notified (Dodd-Frank)
- [ ] Data residency requirements validated for GCP region selection

**During Parallel Run**:
- [ ] Financial calculations reconciled daily with zero tolerance for monetary amounts
- [ ] Audit trail events reconciled (Sybase vs Spanner event counts match)
- [ ] Regulatory reports generated from both sources and compared
- [ ] Risk calculations (RWA, LCR, NSFR) reconciled daily
- [ ] Encryption verified for all PCI-DSS-scoped data in Spanner
- [ ] Access control audit: IAM policies match Sybase grants

**Pre-Cutover (1 week before)**:
- [ ] Parallel run evidence package compiled
- [ ] Zero financial discrepancies confirmed (or all resolved and documented)
- [ ] Audit committee sign-off obtained (SOX)
- [ ] QSA approval for CDE migration (PCI-DSS)
- [ ] Test regulatory reports submitted successfully from Spanner
- [ ] Rollback procedure tested and documented
- [ ] All stakeholders notified of cutover window

**Post-Cutover (first 30 days)**:
- [ ] Daily financial reconciliation continues (Spanner vs archived Sybase data)
- [ ] First regulatory report filed from Spanner (MiFID II, Dodd-Frank)
- [ ] First risk calculation submission from Spanner (Basel)
- [ ] Sybase maintained as warm standby for 30 days (rollback capability)
- [ ] Post-migration audit scheduled within one quarter (SOX)
- [ ] PCI-DSS re-assessment scheduled (if scope changed)

## GCP Security Controls for Financial Compliance

### IAM and Access Control

| Sybase Control | GCP Equivalent | Configuration |
|---------------|---------------|---------------|
| `sa` (system admin) | Project Owner (restrict to break-glass) | Use custom roles for daily operations |
| `sso_role` | Organization Policy constraints | Enforce SSO via Cloud Identity |
| Database owner (`dbo`) | Spanner Database Admin role | Per-database IAM binding |
| `GRANT SELECT ON table` | Spanner fine-grained access control | Database roles with table-level permissions |
| `GRANT EXECUTE ON proc` | Cloud Run IAM invoker role | Service-to-service authentication |
| Sybase auditing | Cloud Audit Logs (always on) | Data Access logs for sensitive tables |
| Proxy table access | VPC Service Controls | Perimeter around Spanner resources |

### Encryption and Key Management

| Requirement | Sybase Approach | GCP Approach |
|------------|----------------|-------------|
| Encryption at rest | Sybase encrypted columns, TDE (limited) | Spanner default encryption + CMEK via Cloud KMS |
| Encryption in transit | SSL/TLS (application configured) | Always encrypted (gRPC with TLS, automatic) |
| Key rotation | Manual, application-managed | Cloud KMS automatic rotation (configurable schedule) |
| Key access logging | Not native | Cloud KMS + Cloud Audit Logs (automatic) |
| HSM-backed keys | Third-party HSM integration | Cloud HSM (FIPS 140-2 Level 3) |
| Key destruction | Manual | Cloud KMS scheduled destruction with configurable delay |

### Monitoring and Alerting for Compliance

**Required Cloud Monitoring alerts for financial systems**:
- Spanner latency exceeding SLA thresholds (P99 > configured threshold)
- Spanner error rate exceeding 0.01% (financial transaction sensitivity)
- IAM policy changes on Spanner resources (change detection)
- Cloud KMS key access anomalies (unusual key usage patterns)
- VPC Service Controls violations (perimeter breach attempts)
- Data access audit log anomalies (unusual query patterns)
- Spanner storage approaching capacity thresholds
- Change Streams lag exceeding latency SLA (for CDC consumers)
