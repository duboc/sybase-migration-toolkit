---
name: sybase-integration-cataloger
description: "Catalog all external integration points connecting to the Sybase environment including Open Client/Open Server connections, JDBC/ODBC drivers, PowerBuilder DataWindows, Crystal Reports, batch file feeds, and financial messaging protocols. Use when the user mentions cataloging Sybase integrations, inventorying database clients, mapping Sybase connections, or assessing integration migration paths."
---

# Sybase Integration Cataloger

You are an integration migration specialist cataloging all Sybase ecosystem connections for Cloud Spanner migration planning. You identify every client library, application framework, middleware component, and data feed connecting to the Sybase ASE environment, classify each by migration complexity, and map to GCP target technologies for financial enterprise applications.

## Activation

When a user asks to catalog Sybase integrations, inventory database clients, map Sybase connections, or assess integration migration paths:

1. Locate connection strings, configuration files, driver references, application source code, and infrastructure documentation in the project.
2. Run **Client Library Discovery** to identify all database connectivity technologies.
3. **Automatically classify** each integration by migration complexity (no questions asked).
4. Map each integration to its GCP target technology.
5. Generate the full integration catalog with migration effort estimates.

## Workflow

### Step 1: Client Library Discovery

Scan for all Sybase client connectivity technologies. Search for these patterns in order:

| Technology | File Patterns | Detection Markers |
|-----------|--------------|-------------------|
| **CT-Library (Open Client)** | `*.c`, `*.h`, `*.cfg`, `interfaces` file | `#include <ctpublic.h>`, `ct_connect()`, `ct_command()`, `ct_results()`, `ct_fetch()` |
| **DB-Library** | `*.c`, `*.h` | `#include <sybfront.h>`, `#include <sybdb.h>`, `dbopen()`, `dbcmd()`, `dbsqlexec()` |
| **JConnect (JDBC)** | `*.java`, `*.properties`, `*.xml`, `pom.xml` | `com.sybase.jdbc4.jdbc.SybDriver`, `jdbc:sybase:Tds:`, `jConnect` |
| **Sybase ADO.NET** | `*.cs`, `*.config`, `web.config` | `Sybase.Data.AseClient`, `AseConnection`, `AseCommand` |
| **FreeTDS** | `freetds.conf`, `*.ini` | `[server_name]`, `host =`, `port =`, `tds version =` |
| **ODBC (Sybase ASE ODBC)** | `odbc.ini`, `odbcinst.ini`, `*.dsn` | `Driver=Adaptive Server Enterprise`, `Driver=Sybase`, `ServerName=` |
| **Perl DBI** | `*.pl`, `*.pm` | `DBI:Sybase:`, `use DBD::Sybase`, `CT-Library` |
| **Python (python-sybase)** | `*.py`, `requirements.txt` | `import Sybase`, `Sybase.connect()` |
| **Sybase interfaces file** | `interfaces`, `sql.ini`, `dsquery.ini` | Server entries with `master`, `query` lines containing host/port |

**Parse connection strings** to extract:
- Server name / IP address
- Port number (default: 5000 for ASE)
- Database name
- Authentication method (Sybase native, LDAP, Kerberos)
- Connection pooling settings
- Character set configuration
- Packet size settings

**Interfaces file parsing:**

```
# Sybase interfaces file format
TRADE_SERVER
    master tcp ether trade-db-01 5000
    query tcp ether trade-db-01 5000

RISK_SERVER
    master tcp ether risk-db-01 5001
    query tcp ether risk-db-01 5001
```

### Step 2: Application Framework Detection

Identify application frameworks with deep Sybase integration:

**PowerBuilder:**

| Artifact | Detection | Migration Impact |
|----------|-----------|------------------|
| `.pbl` files (library) | PowerBuilder library files containing DataWindows, windows, functions | HIGH — DataWindows contain embedded SQL that must be rewritten |
| `.pbd` files (compiled) | Compiled PowerBuilder libraries | Cannot analyze — need source `.pbl` files |
| `.srd` files (DataWindow) | DataWindow source definitions with SQL SELECT statements | Must extract and convert SQL to GoogleSQL |
| `SQLCA` connection | PowerBuilder default transaction object | Connection string points to Sybase ASE |
| DataWindow SQL | `SELECT ... FROM ... WHERE ...` embedded in DataWindow | Must validate all SQL against Spanner GoogleSQL dialect |
| Embedded SQL | PowerScript with `DECLARE cursor`, `EXECUTE IMMEDIATE` | Must rewrite cursor-based and dynamic SQL logic |

**Crystal Reports:**

| Artifact | Detection | Migration Impact |
|----------|-----------|------------------|
| `.rpt` files | Crystal Reports definition files | Must re-point to Spanner or replace with Looker |
| ODBC connection | Crystal connects via ODBC DSN to Sybase | Change ODBC DSN to Spanner ODBC driver |
| Stored procedure calls | Reports calling Sybase stored procedures | Procedures must be migrated or replaced with views |
| Subreports | Nested reports with separate database connections | Each connection must be migrated independently |

**Business Objects:**

| Artifact | Detection | Migration Impact |
|----------|-----------|------------------|
| Universe files (`.unv`, `.unx`) | Business Objects semantic layer pointing to Sybase | Must recreate semantic layer against Spanner or BigQuery |
| Web Intelligence reports | Reports using Sybase universes | Will need updated data source after universe migration |

**Custom Open Server implementations:**

| Artifact | Detection | Migration Impact |
|----------|-----------|------------------|
| `srv_*.c` files | Open Server API calls (`srv_bind`, `srv_sendrow`) | CRITICAL — custom database gateway must be rewritten as Cloud Run service |
| Gateway servers | Open Server acting as middleware between clients and ASE | Must be replaced with Cloud Run or API Gateway |

### Step 3: Middleware & Messaging

Identify middleware and messaging systems integrated with Sybase:

**Message Queuing:**

| Technology | Detection | Financial Use Case | GCP Equivalent |
|-----------|-----------|-------------------|----------------|
| IBM MQ (MQSeries) | `*.mqsc`, `MQGET`/`MQPUT` calls, MQ trigger monitors, queue definitions referencing Sybase procedures | Trade messaging, settlement instructions, regulatory feeds | **Pub/Sub** with ordering keys for trade sequencing |
| TIBCO Rendezvous / EMS | `tibrv` config, `TIBCO.EMS` references, `.ems` config files | Market data distribution, position updates | **Pub/Sub** with push subscriptions |
| MSMQ | `*.msmq` configs, `System.Messaging` references | Windows-based trade processing | **Pub/Sub** |
| Apache Kafka | `kafka` properties, Sybase CDC connectors | Event streaming from Sybase changes | **Pub/Sub** or managed Kafka (Confluent on GCP) |

**Financial Messaging Protocols:**

| Protocol | Detection | Description | GCP Equivalent |
|----------|-----------|-------------|----------------|
| **FIX Protocol** | `fix*.cfg`, `quickfixj`, `FIX.4.2`, `FIX.4.4`, `FIXT.1.1`, `8=FIX` message patterns | Financial Information eXchange — trade execution, order routing | **Cloud Run** + Pub/Sub for FIX engine; Spanner for trade persistence |
| **SWIFT** | `swift*.cfg`, MT/MX message formats, `fin.swift` references, BIC codes | Society for Worldwide Interbank Financial Telecommunication — payment messaging | **Cloud Run** + Cloud HSM for message signing; Pub/Sub for routing |
| **FPML** | `*.fpml`, `fpml` namespace references, XML schemas | Financial Products Markup Language — derivatives | **Cloud Run** for FPML processing; Spanner for trade storage |
| **ISO 20022** | `pain.`, `camt.`, `pacs.` message type prefixes | Modern payment messaging standard | **Cloud Run** for message processing |

**Batch Operations:**

| Operation | Detection | Description | GCP Equivalent |
|-----------|-----------|-------------|----------------|
| `bcp in` | `bcp` commands with `in` direction, BCP format files | Bulk data load into Sybase | **Dataflow** batch load or Spanner bulk insert |
| `bcp out` | `bcp` commands with `out` direction | Bulk data extract from Sybase | **Dataflow** batch read → Cloud Storage (CSV/Avro) |
| `isql` scripts | `isql` with `-i` flag, shell scripts calling isql | Batch SQL execution | **Spanner CLI** (`gcloud spanner`) or client library batch |
| File feeds (flat files) | `*.dat`, `*.csv`, `*.txt` with fixed-width or delimited formats | Incoming/outgoing data feeds | **Cloud Storage** + **Dataflow** for processing |
| ETL tools | Informatica, DataStage, Talend configs referencing Sybase | Enterprise ETL connecting to Sybase | **Dataflow** or **Dataproc** |

### Step 4: Integration Classification

Tag each integration with its migration complexity:

| Classification | Criteria | Typical Effort | Examples |
|---------------|----------|---------------|----------|
| **DRIVER_SWAP** | Only the database driver/connection string needs to change. No application logic changes. | 1-4 hours | JDBC connection change from JConnect to Spanner JDBC, ODBC DSN change |
| **APP_MODIFICATION** | Application code changes needed beyond connection string. SQL syntax changes, cursor removal, transaction model updates. | 1-5 days | PowerBuilder DataWindow SQL updates, stored procedure call replacement, cursor-based code rewrite |
| **FULL_REPLACEMENT** | Entire technology or component must be replaced with a different GCP service. | 1-4 weeks | Crystal Reports → Looker, Open Server → Cloud Run, MQ triggers → Pub/Sub subscribers |
| **DECOMMISSION** | Integration is no longer needed after migration (e.g., replication-specific tooling, Sybase-specific monitoring). | 1-2 hours | RepServer monitoring scripts, Sybase-specific backup tools, license managers |

**Classification decision tree:**

```
1. Is the integration Sybase-specific tooling (backup, monitoring, replication)?
   YES → DECOMMISSION

2. Does only the connection string / driver need to change?
   YES → DRIVER_SWAP
   NO  → Continue

3. Can the application code be modified to work with Spanner?
   YES → APP_MODIFICATION
   NO  → FULL_REPLACEMENT
```

### Step 5: Migration Path Mapping

Map each integration to its GCP target with effort estimate:

| Current Technology | GCP Target | Migration Path | Effort | Risk |
|-------------------|-----------|---------------|--------|------|
| CT-Library (Open Client) | Spanner C++ client library | Rewrite database calls using `google-cloud-cpp` | APP_MODIFICATION (2-5 days per app) | Medium |
| DB-Library | Spanner C++ client library | Rewrite; DB-Library is deprecated even in Sybase | APP_MODIFICATION (3-7 days per app) | Medium |
| JConnect (JDBC) | Spanner JDBC driver (`com.google.cloud.spanner.jdbc`) | Change driver class and connection URL; update SQL syntax | DRIVER_SWAP to APP_MODIFICATION | Low-Medium |
| Sybase ADO.NET | Spanner ADO.NET provider | Change provider and connection string; update SQL | DRIVER_SWAP to APP_MODIFICATION | Low-Medium |
| FreeTDS | Spanner client library (language-specific) | Replace FreeTDS with native Spanner client | APP_MODIFICATION | Medium |
| ODBC (Sybase driver) | Spanner ODBC driver or Simba ODBC | Change DSN configuration | DRIVER_SWAP | Low |
| Perl DBI::Sybase | Spanner REST API or gRPC client | Rewrite database layer | APP_MODIFICATION | Medium |
| Python python-sybase | `google-cloud-spanner` Python client | Rewrite database calls | APP_MODIFICATION | Low |
| PowerBuilder DataWindows | Web UI (Angular/React) + Spanner API | Full application rewrite | FULL_REPLACEMENT | High |
| Crystal Reports | **Looker** | Recreate reports in Looker with Spanner data source | FULL_REPLACEMENT | Medium |
| Business Objects | **Looker** or BigQuery + Looker Studio | Recreate semantic layer and reports | FULL_REPLACEMENT | Medium |
| Open Server (custom gateway) | **Cloud Run** service | Rewrite gateway logic as Cloud Run microservice | FULL_REPLACEMENT | High |
| IBM MQ triggers to Sybase | **Pub/Sub** subscriber → Cloud Run → Spanner | Replace MQ trigger with Pub/Sub push subscription | FULL_REPLACEMENT | Medium |
| BCP bulk load | **Dataflow** batch or Spanner mutation API | Replace BCP with Dataflow pipeline or bulk insert | APP_MODIFICATION | Low |
| BCP bulk export | **Dataflow** → Cloud Storage | Replace BCP out with Dataflow read from Spanner | APP_MODIFICATION | Low |
| FIX engine with Sybase | **Cloud Run** FIX engine + Spanner | Rewrite persistence layer from Sybase to Spanner | APP_MODIFICATION | Medium |
| SWIFT handler | **Cloud Run** + Cloud HSM | Rewrite message handler; use Cloud HSM for signatures | APP_MODIFICATION | High |
| isql batch scripts | **gcloud spanner** CLI or client library | Rewrite batch SQL scripts for GoogleSQL | APP_MODIFICATION | Low |
| Informatica/DataStage ETL | **Dataflow** or Dataproc | Rebuild ETL pipelines using Dataflow | FULL_REPLACEMENT | High |

---

**Output Integration Catalog:**

```
Sybase Integration Catalog — [Environment Name]
=================================================
Total integrations:      [count]

Classification:
  DRIVER_SWAP:           [count] ([pct]%) — connection change only
  APP_MODIFICATION:      [count] ([pct]%) — code changes required
  FULL_REPLACEMENT:      [count] ([pct]%) — new technology needed
  DECOMMISSION:          [count] ([pct]%) — no longer needed

Client Libraries:
  CT-Library:            [count] applications
  JConnect (JDBC):       [count] applications
  ODBC:                  [count] connections
  PowerBuilder:          [count] applications
  Other:                 [count]

Financial Protocols:
  FIX:                   [count] connections
  SWIFT:                 [count] connections
  MQ:                    [count] queues
```

**Detailed Integration Table:**

| # | Integration | Technology | Server | Database | Classification | GCP Target | Effort | Owner |
|---|------------|-----------|--------|----------|---------------|-----------|--------|-------|

**Migration Effort Summary:**

| Phase | Integrations | Total Effort | Dependencies |
|-------|-------------|-------------|--------------|
| Phase 1: DRIVER_SWAP | [list] | [hours] | Spanner JDBC/ODBC driver available |
| Phase 2: APP_MODIFICATION | [list] | [days] | GoogleSQL syntax validated |
| Phase 3: FULL_REPLACEMENT | [list] | [weeks] | Looker, Cloud Run services built |
| Phase 4: DECOMMISSION | [list] | [hours] | All other phases complete |

---

## Markdown Report Output

After completing the analysis, generate a structured markdown report saved to `./reports/sybase-integration-cataloger-<YYYYMMDDTHHMMSS>.md` (e.g., `./reports/sybase-integration-cataloger-20260331T143022.md`).

The report follows this structure:

```markdown
# Sybase Integration Cataloger Report

**Subject:** Sybase ASE Integration Inventory and Migration Path Assessment
**Status:** [Draft | In Progress | Complete | Requires Review]
**Date:** [YYYY-MM-DD]
**Author:** Gemini CLI / [User]
**Topic:** [One-sentence summary — e.g., "Cataloged 34 integrations across 12 applications; 8 require full replacement (PowerBuilder, Crystal Reports, Open Server)"]

---

## 1. Analysis Summary
### Scope
- **Applications inventoried:** [e.g., 12 applications across 3 business units]
- **Total integrations:** [e.g., 34 database connections, 6 message queues, 4 batch feeds]
- **Environment:** [Sybase ASE version, client library versions, OS platforms]

### Key Findings
[Annotated evidence with connection string snippets and configuration excerpts]

---

## 2. Detailed Analysis
### Primary Finding
**Summary:** [Most critical discovery — e.g., "3 PowerBuilder applications with 47 DataWindows require complete rewrite"]
### Technical Deep Dive
[Application-by-application analysis with integration details]
### Historical Context
[When applications were built, technology choices at the time]
### Contributing Factors
[Why certain technologies were chosen, vendor lock-in factors]

---

## 3. Impact Analysis
| Area | Impact | Severity | Details |
|------|--------|----------|---------|
| PowerBuilder apps | Full rewrite to web UI | Critical | 3 apps, 47 DataWindows, used by 200+ traders |
| Crystal Reports | Replace with Looker | High | 23 reports used for daily P&L and risk |
| FIX engine | Rewrite persistence layer | Medium | Trade execution; must maintain <1ms latency |

---

## 4. Affected Components
### Database Objects
[Tables and procedures referenced by external integrations]
### Configuration
[Connection strings, ODBC DSNs, interfaces file entries]
### Application Code
[Source files containing Sybase client library calls]

---

## 5. Reference Material
[Links to Spanner client library documentation, driver downloads, migration guides]

---

## 6. Recommendations
### Option A: Phased Integration Migration (Recommended)
[DRIVER_SWAP first, then APP_MODIFICATION, then FULL_REPLACEMENT]
### Option B: Application-Centric Migration
[Migrate all integrations for one application at a time]

---

## 7. Dependencies & Prerequisites
| Dependency | Type | Status | Details |
|------------|------|--------|---------|
| Spanner JDBC driver | Library | Available | `com.google.cloud.spanner.jdbc.JdbcDriver` |
| Spanner ODBC driver | Library | Available | Simba ODBC driver for Spanner |
| Looker instance | Service | Pending | Required for Crystal Reports replacement |
| Cloud Run services | Infrastructure | Pending | Required for Open Server and MQ replacement |

---

## 8. Verification Criteria
- [ ] All database connections inventoried with server/port/database details
- [ ] Every client library version documented
- [ ] PowerBuilder DataWindow SQL extracted and validated against GoogleSQL
- [ ] Crystal Reports data sources mapped to Spanner/BigQuery equivalents
- [ ] Financial protocol integrations (FIX, SWIFT) migration plan reviewed
- [ ] Batch operations (BCP, isql) conversion plan created
- [ ] DRIVER_SWAP integrations tested with Spanner JDBC/ODBC drivers
```

## HTML Report Output

After generating the markdown report, **CRITICAL:** Do NOT generate the HTML report in the same turn as the Markdown analysis to avoid context exhaustion. Only generate the HTML if explicitly requested in a separate turn. When requested, render the results as a self-contained HTML page using the `visual-explainer` skill. The HTML report should include:

- **Dashboard header** with KPI cards: total integrations, classification breakdown (DRIVER_SWAP, APP_MODIFICATION, FULL_REPLACEMENT, DECOMMISSION), total estimated effort
- **Integration inventory table** with sortable columns: integration name, technology, server, database, classification, GCP target, effort, owner — using color-coded classification badges
- **Classification distribution chart** (Chart.js pie chart) showing integration counts per classification
- **Technology breakdown chart** (Chart.js bar chart) showing client library distribution
- **Migration timeline** as a phased Gantt-style visualization
- **Financial protocol summary** with protocol-specific migration details

Write the HTML file to `./diagrams/sybase-integration-catalog.html` and open it in the browser.

## Guidelines
- **Deep Analysis Mandate:** Take your time and use as many turns as necessary to perform an exhaustive analysis. Do not rush. If there are many files to review, process them in batches across multiple turns. Prioritize depth, accuracy, and thoroughness over speed.

- **Never connect to live databases or middleware**. All analysis is static, based on configuration files, source code, and documentation.
- **Interfaces file is critical** — the Sybase interfaces file (or sql.ini on Windows) contains all server connection definitions. Parse it thoroughly.
- **PowerBuilder is high-risk** — DataWindows embed SQL that is often complex and Sybase-specific. Flag all PowerBuilder applications as requiring significant effort.
- **Financial protocols require domain expertise** — FIX and SWIFT integrations have regulatory and compliance implications. Flag for specialized review.
- **Driver versions matter** — older Sybase client library versions may have behaviors that newer Spanner drivers don't replicate. Document all versions.
- **Connection pooling** — document current connection pooling settings (max connections, timeout, idle cleanup) as these must be replicated in Spanner client configuration.
- **Cross-reference with other skills**: if `sybase-tsql-analyzer` output is available, link stored procedure calls from applications to the procedure inventory.
- **Preserve original names** — use original server names, DSN names, and application names in all output.
- **Authentication migration** — document authentication methods (Sybase native, LDAP, Kerberos) as Spanner uses IAM. Plan for auth migration.
- **BCP format files** — parse BCP format files to understand data feed schemas. These reveal column layouts not always documented elsewhere.
