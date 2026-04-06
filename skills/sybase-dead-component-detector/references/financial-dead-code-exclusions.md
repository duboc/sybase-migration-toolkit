# Financial Dead Code Exclusion Rules

This reference defines exclusion rules for financial domain code that must NOT be flagged as dead during Sybase migration scope reduction analysis. Financial enterprises have numerous database objects that appear dormant in short observation windows but serve critical compliance, regulatory, or seasonal purposes.

## SOX Audit Code Retention (Sarbanes-Oxley Act)

### Section 302 - Corporate Responsibility for Financial Reports

Objects supporting CEO/CFO certification of financial reports:

- **Retention requirement**: 7 years minimum
- **Execution frequency**: Quarterly (Section 302 certifications) and annually (10-K filing)
- **Detection patterns**:
  - Object names: `*sox*`, `*sarbanes*`, `*302*`, `*certification*`
  - Object body references: "SOX", "Sarbanes", "Section 302", "certification"
  - Tables: `sox_certifications`, `sox_302_attestations`, `internal_control_assessments`
  - Procedures: `sp_sox_302_report`, `sp_generate_certification`, `sp_control_assessment`

### Section 404 - Management Assessment of Internal Controls

Objects supporting internal control over financial reporting (ICFR):

- **Retention requirement**: 7 years minimum
- **Execution frequency**: Annually (with quarterly interim assessments)
- **Detection patterns**:
  - Object names: `*404*`, `*icfr*`, `*internal_control*`, `*material_weakness*`
  - Tables: `control_deficiencies`, `material_weaknesses`, `control_test_results`
  - Procedures: `sp_sox_404_assessment`, `sp_control_testing`, `sp_deficiency_report`

### Audit Trail Preservation

Objects maintaining audit trails required by SOX:

- **Retention requirement**: 7 years minimum from the event date
- **Never flag as dead**: Even if the audit trail has not been queried recently
- **Detection patterns**:
  - Object names: `*audit*`, `*trail*`, `*log*` (in financial context)
  - Tables: `audit_trail`, `transaction_audit`, `change_log`, `access_log`
  - Procedures: `sp_record_audit`, `sp_audit_report`, `sp_audit_query`
  - Triggers: `tr_audit_*` (audit triggers on financial tables)

## Regulatory Reporting Procedures

### Federal Reserve Reporting

- **Frequency**: Quarterly (FR Y-9C, FR Y-14), monthly (some schedules)
- **Detection patterns**: `*fed*`, `*federal_reserve*`, `*fr_y*`, `*call_report*`
- **Examples**: `sp_fed_reserve_report`, `sp_fr_y9c_generate`, `sp_fed_statistical_release`

### OCC (Office of the Comptroller) Reporting

- **Frequency**: Quarterly (Call Reports)
- **Detection patterns**: `*occ*`, `*call_report*`, `*rcr_*`
- **Examples**: `sp_occ_call_report`, `sp_rcri_schedule`, `sp_occ_quarterly`

### FDIC Reporting

- **Frequency**: Quarterly
- **Detection patterns**: `*fdic*`, `*deposit_insurance*`
- **Examples**: `sp_fdic_quarterly`, `sp_deposit_insurance_assessment`

### SEC Reporting

- **Frequency**: Quarterly (10-Q), annually (10-K), event-driven (8-K)
- **Detection patterns**: `*sec_*`, `*10q*`, `*10k*`, `*8k*`, `*edgar*`
- **Examples**: `sp_sec_filing_data`, `sp_10q_extract`, `sp_edgar_submission`

### Basel III/IV Capital Adequacy

- **Frequency**: Quarterly, with daily risk calculations
- **Detection patterns**: `*basel*`, `*capital_adequacy*`, `*rwa*`, `*tier1*`, `*tier2*`
- **Examples**: `sp_basel_rwa_calc`, `sp_capital_ratio`, `sp_leverage_ratio`

### Dodd-Frank Reporting

- **Frequency**: Varies (some daily, some quarterly)
- **Detection patterns**: `*dodd_frank*`, `*swap*`, `*sdr*`, `*volcker*`
- **Examples**: `sp_swap_data_report`, `sp_volcker_compliance`, `sp_sdr_submission`

## Disaster Recovery / Failover Procedures

Objects supporting business continuity must NEVER be flagged as dead:

- **Execution frequency**: Tested semi-annually or annually (appears dead most of the time)
- **Detection patterns**:
  - Object names: `*failover*`, `*dr_*`, `*disaster*`, `*recovery*`, `*warm_standby*`, `*switchover*`
  - Procedures: `sp_failover_switch`, `sp_dr_validation`, `sp_warm_standby_check`, `sp_site_switch`
  - Tables: `dr_configuration`, `failover_log`, `recovery_points`
- **Classification**: PRESERVE with reason "Business continuity critical"

## Seasonal Processing

### Year-End Processing (December-January)

- **Detection patterns**: `*year_end*`, `*annual*`, `*eoy*`, `*yearend*`, `*fiscal_year*`
- **Examples**: `sp_year_end_close`, `sp_annual_accrual`, `sp_eoy_reconciliation`
- **Observation window**: Must observe at least 13 months before classifying

### Quarter-End Close (Every 3 months)

- **Detection patterns**: `*quarter*`, `*qtr*`, `*q1*`-`*q4*`, `*quarterly*`
- **Examples**: `sp_quarter_end_close`, `sp_qtr_reconciliation`, `sp_quarterly_pnl`
- **Observation window**: Must observe at least 4 months before classifying

### Month-End Processing (Monthly)

- **Detection patterns**: `*month_end*`, `*eom*`, `*monthly*`, `*monthend*`
- **Examples**: `sp_month_end_close`, `sp_monthly_interest_calc`, `sp_eom_reconciliation`
- **Observation window**: Must observe at least 2 months before classifying

### Tax Season Processing (January-April)

- **Detection patterns**: `*tax*`, `*1099*`, `*w2*`, `*w9*`, `*1042*`, `*tax_year*`
- **Examples**: `sp_generate_1099`, `sp_tax_lot_accounting`, `sp_cost_basis_calc`
- **Observation window**: Must include January-April period

## FATCA / CRS Reporting (International Tax Compliance)

- **Frequency**: Annual (filed by March 31 / September 30 depending on jurisdiction)
- **Detection patterns**: `*fatca*`, `*crs*`, `*aeoi*`, `*foreign_account*`, `*reportable_account*`
- **Examples**: `sp_fatca_report`, `sp_crs_due_diligence`, `sp_aeoi_xml_generate`
- **Retention requirement**: 5 years minimum (IRS requirement)

## Decommissioned Instrument Procedures

Procedures for financial instruments that are no longer actively traded but may still require:

- **Historical position reconstruction** for regulatory examination
- **Tax lot accounting** for held-to-maturity securities
- **Audit trail queries** for past transactions

Detection patterns:
- Object names referencing specific instrument types: `*cdo*`, `*cds*`, `*mbs*`, `*swap*`
- Objects with comments indicating "legacy" or "deprecated" but with financial data references
- **Classification**: PRESERVE if any financial data references exist

## Stress Testing / CCAR / DFAST

- **Frequency**: Semi-annual (CCAR) or annual (DFAST)
- **Detection patterns**: `*stress_test*`, `*ccar*`, `*dfast*`, `*scenario*`, `*adverse*`
- **Examples**: `sp_run_stress_test`, `sp_ccar_scenarios`, `sp_dfast_projections`
- **Classification**: PRESERVE (regulatory requirement)

## Compliance Archival Code

Objects managing data lifecycle and retention policies:

- **Detection patterns**: `*archive*`, `*retention*`, `*purge*`, `*lifecycle*`
- **Examples**: `sp_archive_to_retention`, `sp_purge_after_retention`, `sp_lifecycle_manage`
- **Note**: These procedures may run infrequently (annually) but are critical for data governance
- **Classification**: PRESERVE with reason "Data lifecycle management"

## Exclusion Rule Priority

When multiple exclusion rules match, apply the highest priority:

| Priority | Category | Action |
|----------|---------|--------|
| 1 | SOX audit code | PRESERVE - 7 year retention mandatory |
| 2 | Regulatory reporting | PRESERVE - mandatory filing requirement |
| 3 | Disaster recovery | PRESERVE - business continuity critical |
| 4 | Compliance archival | PRESERVE - data lifecycle requirement |
| 5 | Stress testing (CCAR/DFAST) | PRESERVE - regulatory requirement |
| 6 | FATCA/CRS | PRESERVE - international tax compliance |
| 7 | Year-end processing | SEASONAL - verify with 13-month window |
| 8 | Quarter-end processing | SEASONAL - verify with 4-month window |
| 9 | Month-end processing | SEASONAL - verify with 2-month window |
| 10 | Tax season processing | SEASONAL - verify includes Jan-Apr |
| 11 | Decommissioned instruments | PRESERVE if financial data references exist |

## False Positive Mitigation

Common false positives in financial dead code detection:

1. **Test environment procedures**: Objects with `*test*`, `*dev*`, `*qa*` in production databases -- verify these are truly production objects, not misdeployed test code
2. **One-time migration scripts**: Objects like `sp_migrate_*`, `sp_convert_*` -- these may be genuinely dead after a past migration
3. **Debugging procedures**: Objects like `sp_debug_*`, `sp_trace_*` -- may be kept for production troubleshooting
4. **Backup procedures**: Objects like `sp_backup_*` -- may supplement rather than replace enterprise backup
5. **Legacy product code**: Procedures for products no longer offered but with existing customer positions -- PRESERVE until all positions are closed
