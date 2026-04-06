# Sybase Client Technology Migration Guide

Reference for migrating each Sybase client technology to Cloud Spanner equivalents with effort estimates.

## Client Library Migration Paths

### CT-Library (Open Client) → Spanner C++ Client

**Current technology**: Sybase Open Client CT-Library — C/C++ API for database connectivity.

**Detection patterns:**
```c
#include <ctpublic.h>
#include <cstypes.h>

CS_RETCODE ret;
CS_CONTEXT *ctx;
CS_CONNECTION *conn;
CS_COMMAND *cmd;

// Connection
ct_con_alloc(ctx, &conn);
ct_con_props(conn, CS_SET, CS_SERVERNAME, "TRADE_SERVER", CS_NULLTERM, NULL);
ct_connect(conn, NULL, CS_UNUSED);

// Query execution
ct_command(cmd, CS_LANG_CMD, "SELECT * FROM trades WHERE trade_date = @date", CS_NULLTERM, CS_UNUSED);
ct_send(cmd);
ct_results(cmd, &result_type);
ct_fetch(cmd, CS_UNUSED, CS_UNUSED, CS_UNUSED, &rows_read);
```

**Spanner C++ equivalent:**
```cpp
#include "google/cloud/spanner/client.h"

namespace spanner = google::cloud::spanner;

auto client = spanner::Client(spanner::MakeConnection(
    spanner::Database("project-id", "instance-id", "tradedb")));

auto rows = client.ExecuteQuery(
    spanner::SqlStatement(
        "SELECT * FROM trades WHERE trade_date = @date",
        {{"date", spanner::Value(trade_date)}}));

for (auto const& row : spanner::StreamOf<std::tuple<...>>(rows)) {
    // Process row
}
```

**Migration effort**: 2-5 days per application, depending on query complexity and number of database calls.

**Key differences:**
- CT-Library uses cursor-based result processing; Spanner uses streaming iterators
- CT-Library has explicit connection management; Spanner client handles connection pooling
- CT-Library uses Sybase data types; Spanner uses GoogleSQL types
- Error handling: CT-Library uses return codes; Spanner uses exceptions/StatusOr

### DB-Library → Spanner Client (Any Language)

**Current technology**: Sybase DB-Library — legacy C API (deprecated even in Sybase).

**Detection patterns:**
```c
#include <sybfront.h>
#include <sybdb.h>

DBPROCESS *dbproc;
LOGINREC *login;

login = dblogin();
DBSETLUSER(login, "sa");
DBSETLPWD(login, "password");
dbproc = dbopen(login, "TRADE_SERVER");

dbcmd(dbproc, "SELECT trade_id, amount FROM trades");
dbsqlexec(dbproc);
dbresults(dbproc);
while (dbnextrow(dbproc) != NO_MORE_ROWS) {
    trade_id = dbconvert(...);
}
```

**Migration effort**: 3-7 days per application. DB-Library is deprecated — consider this a good time to modernize the entire application.

**Recommendation**: Rewrite in modern language (Java, Python, Go) with native Spanner client library rather than porting C code.

### JConnect (JDBC) → Spanner JDBC Driver

**Current technology**: Sybase JConnect — JDBC Type 4 driver.

**Detection patterns:**
```java
// Driver class
Class.forName("com.sybase.jdbc4.jdbc.SybDriver");

// Connection URL
String url = "jdbc:sybase:Tds:trade-db-01:5000/tradedb";
Connection conn = DriverManager.getConnection(url, "user", "pass");

// Or in properties/XML
jdbc.driver=com.sybase.jdbc4.jdbc.SybDriver
jdbc.url=jdbc:sybase:Tds:trade-db-01:5000/tradedb
```

**Spanner JDBC equivalent:**
```java
// Driver class (auto-loaded in JDBC 4+)
// com.google.cloud.spanner.jdbc.JdbcDriver

// Connection URL
String url = "jdbc:cloudspanner:/projects/project-id/instances/instance-id/databases/tradedb";
Connection conn = DriverManager.getConnection(url);

// Or with properties
jdbc.driver=com.google.cloud.spanner.jdbc.JdbcDriver
jdbc.url=jdbc:cloudspanner:/projects/project-id/instances/instance-id/databases/tradedb
```

**Migration effort**: 1-4 hours for DRIVER_SWAP if SQL is Spanner-compatible. 1-5 days if SQL requires GoogleSQL modifications.

**Key differences:**
- Auto-commit behavior: Sybase JConnect defaults depend on chained/unchained mode; Spanner JDBC defaults to autocommit
- Batch operations: Spanner has 80,000 mutation limit per transaction
- Stored procedure calls: `{call proc_name(?)}` syntax requires procedures to exist in Spanner (limited support)
- Data types: `java.sql.Types.MONEY` does not exist in Spanner; use `NUMERIC`

### ODBC → Spanner ODBC (Simba)

**Current technology**: Sybase ASE ODBC driver.

**Detection patterns:**
```ini
# odbc.ini
[TradeDB]
Driver=Adaptive Server Enterprise
Server=trade-db-01
Port=5000
Database=tradedb
UseCursor=1

# Or Windows DSN
Driver={Adaptive Server Enterprise}
Server=TRADE_SERVER
```

**Spanner ODBC equivalent:**
```ini
# odbc.ini
[TradeDB]
Driver=Google Cloud Spanner ODBC Driver
ProjectId=project-id
InstanceId=instance-id
DatabaseId=tradedb
```

**Migration effort**: 1-2 hours for DSN change. Test all SQL queries for GoogleSQL compatibility.

### FreeTDS → Spanner Client Library

**Current technology**: FreeTDS — open-source TDS protocol implementation.

**Detection patterns:**
```ini
# freetds.conf
[TRADE_SERVER]
    host = trade-db-01
    port = 5000
    tds version = 5.0
    client charset = UTF-8
```

**Migration effort**: 2-5 days. FreeTDS applications must be rewritten to use native Spanner client libraries for the respective language (Python, Perl, PHP, etc.).

### PowerBuilder → Web Application

**Current technology**: PowerBuilder with DataWindows connected to Sybase ASE.

**Migration path**: Full application rewrite to web-based UI framework.

| PowerBuilder Component | Web Equivalent | Notes |
|----------------------|---------------|-------|
| DataWindow | Angular/React data grid + REST API | DataWindow SQL must be converted to Spanner queries via API |
| Window | Web page / SPA route | UI layout recreation |
| PowerScript | TypeScript / JavaScript | Business logic rewrite |
| SQLCA transaction | Spanner client in backend API | Transaction management in API layer |
| DataWindow reports | Looker or web-based reporting | Replace print-oriented DataWindows |
| UserObject | Angular/React component | Reusable UI component |

**Migration effort**: 2-8 weeks per application depending on complexity.

### Crystal Reports → Looker

**Current technology**: Crystal Reports connected via ODBC to Sybase ASE.

| Crystal Feature | Looker Equivalent | Notes |
|----------------|------------------|-------|
| .rpt report file | LookML model + Explore | Declarative report definition |
| ODBC data source | Spanner or BigQuery connection | Native Looker connections |
| Stored procedure data | Spanner query or BigQuery view | Replace procedure calls with direct queries |
| Subreports | Looker merged results | Cross-model queries |
| Report scheduling | Looker scheduled deliveries | Email, Slack, Cloud Storage delivery |
| Parameter prompts | Looker filter UI | Interactive filtering |

**Migration effort**: 1-3 days per report for simple reports; 1-2 weeks for complex reports with subreports and conditional formatting.

## Effort Estimation Matrix

| Technology | DRIVER_SWAP | APP_MODIFICATION | FULL_REPLACEMENT |
|-----------|------------|-----------------|-----------------|
| CT-Library | N/A | 2-5 days/app | N/A |
| DB-Library | N/A | 3-7 days/app | Recommend full rewrite |
| JConnect (JDBC) | 1-4 hours | 1-5 days/app | N/A |
| ADO.NET | 1-4 hours | 1-5 days/app | N/A |
| FreeTDS | N/A | 2-5 days/app | N/A |
| ODBC | 1-2 hours | 1-2 days/app | N/A |
| PowerBuilder | N/A | N/A | 2-8 weeks/app |
| Crystal Reports | N/A | N/A | 1-3 days/report |
| Business Objects | N/A | N/A | 1-4 weeks |
| Open Server | N/A | N/A | 2-6 weeks |

## Authentication Migration

| Sybase Auth Method | Spanner Auth Method | Migration Notes |
|-------------------|--------------------|-----------------|
| Sybase native (syslogins) | IAM service accounts | Create service accounts per application; grant Spanner roles |
| LDAP authentication | Google Cloud Identity / Workforce Identity Federation | Federate existing LDAP with Google Cloud Identity |
| Kerberos (network auth) | Workload Identity Federation | Use WIF for on-prem to GCP authentication |
| Application-embedded credentials | Secret Manager | Store credentials in Secret Manager; reference from application |

## Connection Pooling Migration

| Sybase Setting | Spanner Client Equivalent | Default |
|---------------|--------------------------|---------|
| Max connections | `maxSessions` (Spanner session pool) | 400 |
| Min connections | `minSessions` | 100 |
| Connection timeout | `createSessionTimeout` | 60s |
| Idle timeout | `keepAliveIntervalMinutes` | 10 min |
| Connection lifetime | Managed by Spanner client | Automatic |
