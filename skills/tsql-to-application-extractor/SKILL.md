---
name: tsql-to-application-extractor
description: "Extract business logic from Sybase Transact-SQL stored procedures and translate into Cloud Run microservices with Spanner client library integration, OpenAPI specifications, and saga patterns for distributed transactions. Use when the user mentions extracting Sybase stored procedures, converting T-SQL to application code, building Cloud Run services from stored procs, or migrating database logic to microservices."
---

# T-SQL to Application Extractor

You are an application modernization specialist extracting Sybase T-SQL business logic into Cloud Run microservices. You consume sybase-tsql-analyzer output to prioritize stored procedures by complexity and business criticality, then translate T-SQL patterns into Java Spring Boot or Python FastAPI service code with Spanner client library integration. You design saga patterns for distributed transactions, generate OpenAPI 3.0 specifications, and create parallel-run validation frameworks to verify monetary calculation accuracy with zero tolerance for discrepancies.

## Activation

When user asks to extract Sybase stored procedures to application code, convert T-SQL to microservices, build Cloud Run services from stored procs, migrate database logic to application layer, design saga patterns for Sybase transactions, or generate OpenAPI specs from stored procedure signatures.

## Workflow

### Step 1: Extraction Priority

Consume sybase-tsql-analyzer output and prioritize stored procedures for extraction using complexity and business impact scoring.

**Priority classification matrix:**

| Priority | Criteria | Rationale | Extraction Approach |
|----------|---------|-----------|-------------------|
| P1 - Critical | COMPLEX_BUSINESS_LOGIC + HOT execution | Highest risk, highest value | Full service extraction with parallel run |
| P2 - Blocker | ORCHESTRATION procedures spanning databases | Migration blockers (cross-DB transactions) | Saga pattern with Cloud Workflows |
| P3 - Transform | DATA_TRANSFORMATION / ETL procedures | Pipeline candidates | Dataflow jobs or Cloud Run batch |
| P4 - Simple | CRUD_ONLY procedures | Low risk, ORM replacement | Repository pattern (Spring Data / SQLAlchemy) |

**Bounded context grouping (DDD):**

```
FOR EACH stored_procedure SP:
  context = determine_bounded_context(SP)
  -- Based on: tables accessed, business domain, naming convention

Bounded Contexts for Financial Applications:
  - Trading:       sp_book_trade, sp_cancel_order, sp_amend_order
  - Settlement:    sp_settle_trade, sp_match_trades, sp_netting
  - Position:      sp_update_position, sp_calc_pnl, sp_mark_to_market
  - Account:       sp_open_account, sp_close_account, sp_transfer
  - Compliance:    sp_check_limits, sp_aml_screening, sp_regulatory_report
  - Pricing:       sp_calc_price, sp_get_market_data, sp_calc_risk
  - Reconciliation: sp_reconcile_positions, sp_break_resolution
```

**Priority assignment output:**

| # | Procedure | Database | Priority | Context | Complexity | Exec/Day | Tables | Approach |
|---|-----------|----------|----------|---------|-----------|----------|--------|----------|
| 1 | sp_book_trade | trading_db | P1 | Trading | COMPLEX | 50,000 | 8 | Full service + parallel run |
| 2 | sp_settle_trade | clearing_db | P1 | Settlement | COMPLEX | 10,000 | 12 | Saga + parallel run |
| 3 | sp_daily_pnl | position_db | P3 | Position | TRANSFORM | 1 | 15 | Dataflow batch |
| 4 | sp_get_account | accounts_db | P4 | Account | CRUD | 100,000 | 1 | Repository pattern |

### Step 2: T-SQL to Application Translation

Map Sybase T-SQL constructs to application code patterns in Java Spring Boot and Python FastAPI.

**Core T-SQL to application code mapping:**

| T-SQL Pattern | Java (Spring Boot) | Python (FastAPI) |
|--------------|-------------------|-----------------|
| `SELECT...FROM...JOIN` | Repository method with `@Query` / SpannerTemplate query | SQLAlchemy query / Spanner Client `execute_sql` |
| `INSERT...VALUES` | `SpannerTemplate.insert()` / `Mutation.newInsertBuilder()` | `transaction.insert()` |
| `INSERT...SELECT` | Service: query + transform + batch insert | Service: query + transform + batch insert |
| `UPDATE...SET...WHERE` | `SpannerTemplate.update()` / `Mutation.newUpdateBuilder()` | `transaction.update()` |
| `DELETE...WHERE` | `SpannerTemplate.delete()` / `Mutation.delete()` | `transaction.delete()` |
| `DECLARE @var` | Local variable | Local variable |
| `DECLARE CURSOR` | `ResultSet` iteration / Stream | Iterator / generator |
| `WHILE/FETCH` | `while (resultSet.next())` | `for row in results:` |
| `IF...ELSE` | `if/else` block | `if/else` block |
| `CASE WHEN` | Ternary / switch expression | Conditional expression / match |
| `BEGIN TRAN...COMMIT` | `@Transactional` / `dbClient.readWriteTransaction()` | `database.run_in_transaction()` |
| `SAVE TRAN` | Compensating action in saga | Compensating action in saga |
| `ROLLBACK TRAN` | Exception → transaction abort | Exception → transaction abort |
| `RAISERROR` | `throw new BusinessException(...)` | `raise HTTPException(...)` |
| `@@identity` | `GET_NEXT_SEQUENCE_VALUE(SEQUENCE seq)` | `next_val = seq.get_next()` |
| `@@rowcount` | Return value from mutation / result set size | Result set length |
| `@@error` | Try-catch exception handling | Try-except exception handling |
| `COMPUTE BY` | Application-level aggregation (stream reduce) | `itertools.groupby` + aggregation |
| `SET ROWCOUNT n` | `LIMIT n` in query / batch size config | `LIMIT n` in query |
| `HOLDLOCK` | Spanner read-write transaction (implicit) | Spanner read-write transaction |
| `sp_procxmode` | Transaction configuration in service layer | Transaction configuration |
| Temp tables (`#temp`) | In-memory collection (`List`, `Map`) | In-memory collection (`list`, `dict`) |
| Global temp (`##temp`) | Redis/Memorystore cache | Redis/Memorystore cache |
| Dynamic SQL (`EXEC(@sql)`) | Query builder (Criteria API / jOOQ) | Query builder (SQLAlchemy) |
| Output parameters | Return DTO / response object | Return Pydantic model |
| Multiple result sets | Multiple DTOs / response wrapper | Multiple response models |

**Example translation -- Trade Booking:**

Sybase T-SQL:
```sql
CREATE PROCEDURE sp_book_trade
    @account_id INT,
    @instrument_id INT,
    @side CHAR(1),
    @quantity NUMERIC(18,4),
    @price MONEY,
    @trader_id INT
AS
BEGIN
    DECLARE @order_id INT
    DECLARE @trade_id INT
    DECLARE @position_qty NUMERIC(18,4)

    BEGIN TRAN trade_booking

    -- Insert order
    INSERT INTO orders (account_id, instrument_id, side, quantity, price, status, order_date)
    VALUES (@account_id, @instrument_id, @side, @quantity, @price, 'NEW', GETDATE())
    SELECT @order_id = @@identity

    IF @@error != 0
    BEGIN
        ROLLBACK TRAN
        RAISERROR 50001 'Order insert failed'
        RETURN -1
    END

    -- Insert fill
    INSERT INTO fills (order_id, fill_quantity, fill_price, fill_date)
    VALUES (@order_id, @quantity, @price, GETDATE())

    -- Update position
    SELECT @position_qty = ISNULL(quantity, 0)
    FROM positions WITH (HOLDLOCK)
    WHERE account_id = @account_id AND instrument_id = @instrument_id

    IF @position_qty IS NULL
        INSERT INTO positions (account_id, instrument_id, quantity, avg_price)
        VALUES (@account_id, @instrument_id,
                CASE @side WHEN 'B' THEN @quantity ELSE -@quantity END,
                @price)
    ELSE
        UPDATE positions
        SET quantity = quantity + CASE @side WHEN 'B' THEN @quantity ELSE -@quantity END,
            avg_price = CASE
                WHEN @side = 'B' THEN (avg_price * quantity + @price * @quantity) / (quantity + @quantity)
                ELSE avg_price END
        WHERE account_id = @account_id AND instrument_id = @instrument_id

    -- Audit trail
    INSERT INTO audit_trail (entity_type, entity_id, action, details, created_by, created_at)
    VALUES ('TRADE', @order_id, 'BOOK', 'Trade booked', @trader_id, GETDATE())

    COMMIT TRAN
    RETURN @order_id
END
```

Java Spring Boot equivalent:
```java
@Service
@RequiredArgsConstructor
public class TradeBookingService {

    private final SpannerTemplate spannerTemplate;
    private final DatabaseClient dbClient;

    @Transactional
    public TradeBookingResult bookTrade(TradeBookingRequest request) {
        return dbClient.readWriteTransaction().run(transaction -> {

            // Insert order
            long orderId = getNextSequenceValue("seq_order_id");
            Struct orderRow = Struct.newBuilder()
                .set("order_id").to(orderId)
                .set("account_id").to(request.getAccountId())
                .set("instrument_id").to(request.getInstrumentId())
                .set("side").to(request.getSide())
                .set("quantity").to(request.getQuantity())
                .set("price").to(request.getPrice())
                .set("status").to("NEW")
                .set("order_date").to(Value.COMMIT_TIMESTAMP)
                .build();

            transaction.buffer(
                Mutation.newInsertBuilder("orders")
                    .set("order_id").to(orderId)
                    .set("account_id").to(request.getAccountId())
                    .set("instrument_id").to(request.getInstrumentId())
                    .set("side").to(request.getSide())
                    .set("quantity").to(request.getQuantity())
                    .set("price").to(request.getPrice())
                    .set("status").to("NEW")
                    .set("spanner_commit_ts").to(Value.COMMIT_TIMESTAMP)
                    .build());

            // Insert fill
            long fillId = getNextSequenceValue("seq_fill_id");
            transaction.buffer(
                Mutation.newInsertBuilder("fills")
                    .set("order_id").to(orderId)
                    .set("fill_id").to(fillId)
                    .set("fill_quantity").to(request.getQuantity())
                    .set("fill_price").to(request.getPrice())
                    .set("spanner_commit_ts").to(Value.COMMIT_TIMESTAMP)
                    .build());

            // Read current position (within same transaction = locked)
            Struct position = transaction.readRow(
                "positions",
                Key.of(request.getAccountId(), request.getInstrumentId()),
                Arrays.asList("quantity", "avg_price"));

            BigDecimal signedQty = request.getSide().equals("B")
                ? request.getQuantity()
                : request.getQuantity().negate();

            if (position == null) {
                transaction.buffer(
                    Mutation.newInsertBuilder("positions")
                        .set("account_id").to(request.getAccountId())
                        .set("instrument_id").to(request.getInstrumentId())
                        .set("quantity").to(signedQty)
                        .set("avg_price").to(request.getPrice())
                        .set("spanner_commit_ts").to(Value.COMMIT_TIMESTAMP)
                        .build());
            } else {
                BigDecimal currentQty = position.getBigDecimal("quantity");
                BigDecimal currentAvg = position.getBigDecimal("avg_price");
                BigDecimal newQty = currentQty.add(signedQty);
                BigDecimal newAvg = request.getSide().equals("B")
                    ? currentAvg.multiply(currentQty)
                        .add(request.getPrice().multiply(request.getQuantity()))
                        .divide(currentQty.add(request.getQuantity()), RoundingMode.HALF_UP)
                    : currentAvg;

                transaction.buffer(
                    Mutation.newUpdateBuilder("positions")
                        .set("account_id").to(request.getAccountId())
                        .set("instrument_id").to(request.getInstrumentId())
                        .set("quantity").to(newQty)
                        .set("avg_price").to(newAvg)
                        .set("spanner_commit_ts").to(Value.COMMIT_TIMESTAMP)
                        .build());
            }

            // Audit trail
            transaction.buffer(
                Mutation.newInsertBuilder("audit_trail")
                    .set("audit_id").to(getNextSequenceValue("seq_audit_id"))
                    .set("entity_type").to("TRADE")
                    .set("entity_id").to(orderId)
                    .set("action").to("BOOK")
                    .set("details").to("Trade booked")
                    .set("created_by").to(request.getTraderId())
                    .set("spanner_commit_ts").to(Value.COMMIT_TIMESTAMP)
                    .build());

            return new TradeBookingResult(orderId, fillId, "BOOKED");
        });
    }
}
```

### Step 3: Spanner Client Integration

Generate service code using Spanner client libraries with proper connection pooling, transaction management, and Cloud Run configuration.

**Spanner client library patterns:**

| Operation | Java (google-cloud-spanner) | Python (google-cloud-spanner) |
|-----------|---------------------------|------------------------------|
| Read-write transaction | `dbClient.readWriteTransaction().run(tx -> { ... })` | `database.run_in_transaction(callback)` |
| Read-only transaction | `dbClient.singleUseReadOnlyTransaction()` | `with database.snapshot() as snapshot:` |
| Stale read (15s) | `dbClient.singleUse(TimestampBound.ofExactStaleness(15, SECONDS))` | `database.snapshot(exact_staleness=timedelta(seconds=15))` |
| Partitioned DML | `dbClient.executePartitionedUpdate(statement)` | `database.execute_partitioned_dml(sql)` |
| Batch mutations | `dbClient.write(Arrays.asList(mutation1, mutation2))` | `with database.batch() as batch:` |
| Sequence read | `SELECT GET_NEXT_SEQUENCE_VALUE(SEQUENCE seq)` | `SELECT GET_NEXT_SEQUENCE_VALUE(SEQUENCE seq)` |
| Commit timestamp | `.set("col").to(Value.COMMIT_TIMESTAMP)` | `spanner.COMMIT_TIMESTAMP` |

**Cloud Run session pool configuration:**

```java
// Java: SpannerOptions for Cloud Run
SpannerOptions options = SpannerOptions.newBuilder()
    .setProjectId(projectId)
    .setSessionPoolOption(
        SessionPoolOptions.newBuilder()
            .setMinSessions(100)        // Min sessions in pool
            .setMaxSessions(400)        // Max sessions (scale with instances)
            .setKeepAliveIntervalMinutes(10)
            .setWriteSessionsFraction(0.5f) // 50% prepared for writes
            .build())
    .build();

// Python: Session pool for Cloud Run
from google.cloud.spanner_v1 import Client
from google.cloud.spanner_v1.pool import PingingPool

client = Client(project=project_id)
instance = client.instance(instance_id)
pool = PingingPool(
    size=100,              # Pool size
    default_timeout=30,    # Seconds
    ping_interval=300      # Keep-alive ping interval
)
database = instance.database(database_id, pool=pool)
```

**Connection configuration for Cloud Run service.yaml:**

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: trade-booking-service
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: "1"
        autoscaling.knative.dev/maxScale: "100"
        run.googleapis.com/cpu-throttling: "false"
    spec:
      containerConcurrency: 80
      timeoutSeconds: 300
      containers:
        - image: gcr.io/${PROJECT}/trade-booking-service:latest
          env:
            - name: SPANNER_PROJECT
              value: ${GCP_PROJECT}
            - name: SPANNER_INSTANCE
              value: ${SPANNER_INSTANCE}
            - name: SPANNER_DATABASE
              value: ${SPANNER_DATABASE}
            - name: SESSION_POOL_MIN
              value: "100"
            - name: SESSION_POOL_MAX
              value: "400"
          resources:
            limits:
              cpu: "2"
              memory: 2Gi
```

### Step 4: Saga Pattern Design

For procedures that span multiple logical databases or require complex orchestration, design saga patterns with compensation actions.

**Saga identification criteria:**

| Criteria | Example | Saga Required |
|---------|---------|--------------|
| Cross-database transaction | sp_settle_trade writes to trading_db + clearing_db + position_db | YES |
| Long-running operation | sp_end_of_day processes millions of records | YES |
| External system integration | sp_send_to_swift calls MQ + updates DB | YES |
| Multi-step business process | sp_trade_lifecycle: order -> fill -> allocate -> settle | YES |
| Single-database CRUD | sp_get_account reads from one table | NO |

**Trade booking saga with compensation:**

```yaml
# Cloud Workflows: Trade Settlement Saga
main:
  params: [trade]
  steps:
    - validate_trade:
        call: http.post
        args:
          url: ${TRADE_VALIDATION_URL}
          body: ${trade}
        result: validation_result

    - check_validation:
        switch:
          - condition: ${validation_result.body.valid == false}
            raise: ${validation_result.body.error}

    - create_settlement:
        try:
          call: http.post
          args:
            url: ${SETTLEMENT_SERVICE_URL}
            body:
              trade_id: ${trade.trade_id}
              settlement_date: ${trade.settlement_date}
              amount: ${trade.amount}
          result: settlement_result
        except:
          as: e
          steps:
            - log_settlement_failure:
                call: sys.log
                args:
                  text: ${"Settlement failed for trade " + trade.trade_id + ": " + e.message}
            - raise_error:
                raise: ${e}

    - update_positions:
        try:
          call: http.post
          args:
            url: ${POSITION_SERVICE_URL}
            body:
              account_id: ${trade.account_id}
              instrument_id: ${trade.instrument_id}
              quantity: ${trade.quantity}
              side: ${trade.side}
          result: position_result
        except:
          as: e
          steps:
            - compensate_settlement:
                call: http.post
                args:
                  url: ${SETTLEMENT_SERVICE_URL}/cancel
                  body:
                    settlement_id: ${settlement_result.body.settlement_id}
                    reason: "Position update failed"
            - raise_error:
                raise: ${e}

    - notify_downstream:
        try:
          call: http.post
          args:
            url: ${NOTIFICATION_SERVICE_URL}
            body:
              event: "TRADE_SETTLED"
              trade_id: ${trade.trade_id}
              settlement_id: ${settlement_result.body.settlement_id}
        except:
          as: e
          steps:
            - log_notification_failure:
                call: sys.log
                args:
                  text: ${"Notification failed (non-critical): " + e.message}
            # Non-critical step: log but don't compensate

    - return_result:
        return:
          status: "SETTLED"
          trade_id: ${trade.trade_id}
          settlement_id: ${settlement_result.body.settlement_id}
```

**Financial saga patterns:**

| Saga | Steps | Compensation Actions |
|------|-------|---------------------|
| Trade booking | 1. Validate order 2. Create order 3. Execute fill 4. Update position 5. Audit | 4→Reverse position 3→Cancel fill 2→Cancel order |
| Payment processing | 1. Validate 2. Debit source 3. Credit target 4. Record | 3→Reverse credit 2→Reverse debit |
| Account transfer | 1. Check balance 2. Debit 3. Credit 4. Notify | 3→Reverse credit 2→Reverse debit |
| Trade settlement | 1. Match 2. Net 3. Settle 4. Update positions 5. Confirm | 4→Reverse 3→Unsettle 2→Unnet |

### Step 5: OpenAPI & Contract Generation

Generate OpenAPI 3.0 specifications for each extracted service.

**OpenAPI specification template:**

```yaml
openapi: 3.0.3
info:
  title: Trade Booking Service API
  description: |
    Extracted from Sybase stored procedure sp_book_trade.
    Handles trade order creation, fill execution, and position updates.
  version: 1.0.0
  contact:
    name: Platform Engineering
servers:
  - url: https://trade-booking-service-{hash}.run.app
    description: Cloud Run production
  - url: http://localhost:8080
    description: Local development

paths:
  /api/v1/trades:
    post:
      summary: Book a new trade
      operationId: bookTrade
      tags: [Trading]
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/TradeBookingRequest'
      responses:
        '201':
          description: Trade booked successfully
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/TradeBookingResult'
        '400':
          description: Invalid trade parameters
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ErrorResponse'
        '409':
          description: Duplicate trade or position conflict
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ErrorResponse'
        '500':
          description: Internal server error
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ErrorResponse'

  /api/v1/trades/{tradeId}:
    get:
      summary: Get trade details
      operationId: getTrade
      tags: [Trading]
      parameters:
        - name: tradeId
          in: path
          required: true
          schema:
            type: integer
            format: int64
      responses:
        '200':
          description: Trade details
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/TradeDetails'
        '404':
          description: Trade not found

components:
  schemas:
    TradeBookingRequest:
      type: object
      required: [accountId, instrumentId, side, quantity, price, traderId]
      properties:
        accountId:
          type: integer
          format: int64
          description: "Source: @account_id INT parameter"
        instrumentId:
          type: integer
          format: int64
          description: "Source: @instrument_id INT parameter"
        side:
          type: string
          enum: [B, S]
          description: "Source: @side CHAR(1) -- Buy or Sell"
        quantity:
          type: number
          format: decimal
          description: "Source: @quantity NUMERIC(18,4)"
        price:
          type: number
          format: decimal
          description: "Source: @price MONEY"
        traderId:
          type: integer
          format: int64
          description: "Source: @trader_id INT"

    TradeBookingResult:
      type: object
      properties:
        orderId:
          type: integer
          format: int64
          description: "Source: @@identity from orders INSERT"
        fillId:
          type: integer
          format: int64
        status:
          type: string
          enum: [BOOKED, REJECTED]

    ErrorResponse:
      type: object
      properties:
        code:
          type: string
          description: "Source: RAISERROR error number"
        message:
          type: string
          description: "Source: RAISERROR message"
        details:
          type: object

  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT

security:
  - bearerAuth: []
```

**Endpoint mapping rules from stored procedures:**

| Stored Procedure Pattern | HTTP Method | URL Pattern | Notes |
|-------------------------|------------|------------|-------|
| sp_get_* / sp_read_* / sp_fetch_* | GET | /api/v1/{resource}/{id} | Read operations |
| sp_insert_* / sp_create_* / sp_book_* | POST | /api/v1/{resource} | Create operations |
| sp_update_* / sp_amend_* / sp_modify_* | PUT | /api/v1/{resource}/{id} | Update operations |
| sp_delete_* / sp_cancel_* / sp_remove_* | DELETE | /api/v1/{resource}/{id} | Delete/cancel operations |
| sp_list_* / sp_search_* / sp_find_* | GET | /api/v1/{resource}?filters | List with query params |
| sp_report_* / sp_calc_* | GET | /api/v1/{resource}/reports/{type} | Reporting endpoints |
| sp_batch_* / sp_process_* | POST | /api/v1/{resource}/batch | Batch operations |

### Step 6: Parallel Run Validation

Design a parallel-run framework to validate that the extracted Cloud Run services produce identical results to the Sybase stored procedures.

**Parallel run architecture:**

```
Client Request
    |
    +---> Sybase Stored Procedure (existing)
    |         |
    |         +--> Sybase Result
    |
    +---> Cloud Run Service (new)
              |
              +--> Spanner Result
                      |
                      v
               Comparison Engine
                      |
                      +--> Match: LOG success
                      +--> Mismatch: ALERT + LOG details
```

**Comparison framework:**

```java
@Service
public class ParallelRunComparator {

    public ComparisonResult compare(
            SybaseResult sybaseResult,
            SpannerResult spannerResult,
            ComparisonConfig config) {

        ComparisonResult result = new ComparisonResult();

        // Financial amount comparison (ZERO TOLERANCE)
        if (config.isFinancialAmount()) {
            BigDecimal sybaseAmount = sybaseResult.getAmount();
            BigDecimal spannerAmount = spannerResult.getAmount();
            if (sybaseAmount.compareTo(spannerAmount) != 0) {
                result.addMismatch(
                    MismatchType.FINANCIAL_AMOUNT,
                    Severity.CRITICAL,
                    "Amount mismatch: Sybase=" + sybaseAmount
                        + " Spanner=" + spannerAmount
                        + " Delta=" + sybaseAmount.subtract(spannerAmount));
            }
        }

        // Row count comparison
        if (sybaseResult.getRowCount() != spannerResult.getRowCount()) {
            result.addMismatch(
                MismatchType.ROW_COUNT,
                Severity.HIGH,
                "Row count mismatch: Sybase=" + sybaseResult.getRowCount()
                    + " Spanner=" + spannerResult.getRowCount());
        }

        // Column-by-column comparison
        for (String column : config.getCompareColumns()) {
            Object sybaseVal = sybaseResult.getValue(column);
            Object spannerVal = spannerResult.getValue(column);
            if (!Objects.equals(sybaseVal, spannerVal)) {
                result.addMismatch(
                    MismatchType.COLUMN_VALUE,
                    config.getColumnSeverity(column),
                    "Column " + column + " mismatch: Sybase="
                        + sybaseVal + " Spanner=" + spannerVal);
            }
        }

        return result;
    }
}
```

**Parallel run metrics dashboard:**

| Metric | Target | Threshold |
|--------|--------|-----------|
| Financial amount match rate | 100.000% | Zero tolerance |
| Row count match rate | 100.000% | Zero tolerance |
| Non-financial field match rate | 99.99% | Investigate >0.01% mismatch |
| Latency ratio (Spanner / Sybase) | <1.0x | Alert if >2.0x |
| Error rate delta | 0.00% | Alert on any new errors |
| Throughput (requests/sec) | >= Sybase baseline | Alert if <80% of baseline |

**Parallel run phases:**

| Phase | Traffic Split | Duration | Success Criteria |
|-------|-------------|----------|-----------------|
| Shadow | 100% Sybase, mirror to Spanner (read-only) | 2 weeks | 100% financial match |
| Canary | 95% Sybase / 5% Spanner (dual-write) | 1 week | 100% financial match, <2x latency |
| Partial | 50% Sybase / 50% Spanner | 2 weeks | Sustained match rate |
| Primary | 5% Sybase / 95% Spanner | 1 week | Confidence build |
| Cutover | 0% Sybase / 100% Spanner | Permanent | Sybase decommission ready |

## Markdown Report Output

After completing the analysis, generate a structured markdown report saved to `./reports/tsql-to-application-extractor-<YYYYMMDDTHHMMSS>.md`.

The report follows this structure:

```
# T-SQL to Application Extractor Report

**Subject:** [Short descriptive title, e.g., "Stored Procedure Extraction Plan for Trading Platform Modernization"]
**Status:** [Draft | In Progress | Complete | Requires Review]
**Date:** [YYYY-MM-DD]
**Author:** [Gemini CLI / User]
**Topic:** [One-sentence summary of extraction scope]

---

## 1. Analysis Summary
### Scope
- Number of stored procedures analyzed
- Number of bounded contexts identified
- Number of Cloud Run services to generate
- Number of saga patterns designed
- Number of OpenAPI specifications generated

### Key Findings
- P1 critical procedures requiring full extraction with parallel run
- P2 orchestration procedures requiring saga patterns
- P3 transformation procedures suitable for Dataflow
- P4 CRUD procedures replaceable with ORM patterns

## 2. Detailed Analysis
### Primary Finding
- Dominant extraction pattern and recommended approach
### Technical Deep Dive
- T-SQL to application code mapping details
- Spanner client integration patterns used
- Saga pattern designs for cross-database transactions
- OpenAPI specification coverage
### Historical Context
- Business logic evolution in stored procedures
- Integration dependencies requiring saga patterns
### Contributing Factors
- Stored procedure complexity distribution
- Cross-database transaction patterns
- External system integration requirements

## 3. Impact Analysis
| Area | Impact | Severity | Details |
|------|--------|----------|---------|
| Service count | [N] Cloud Run services | HIGH | New operational surface |
| Saga complexity | [N] saga workflows | HIGH | Distributed transaction replacement |
| API surface | [N] OpenAPI endpoints | MEDIUM | New API management requirement |
| Parallel run | [N] procedures in parallel run | HIGH | Validation before cutover |

## 4. Affected Components
- Per-procedure extraction plan with target service
- Saga pattern definitions
- OpenAPI specifications
- Parallel run configurations

## 5. Reference Material
- T-SQL to code mapping reference
- Spanner client library patterns
- Cloud Workflows saga templates
- Parallel run framework code

## 6. Recommendations
### Option A (Recommended)
- Extract P1 procedures first with parallel run validation
- Design sagas for P2 orchestration procedures
- Convert P4 CRUD to repository pattern
### Option B
- Strangler fig pattern: wrap stored procedures in Cloud Run proxies first
- Incrementally extract logic from proxy to native service

## 7. Dependencies & Prerequisites
- sybase-tsql-analyzer output for procedure classification
- Spanner target schema (from sybase-to-spanner-schema-designer)
- Cloud Run project setup with Spanner IAM
- Cloud Workflows enabled for saga patterns
- Parallel run infrastructure (traffic splitting)

## 8. Verification Criteria
- All P1 procedures have parallel run validation with 100% financial match
- All P2 procedures have saga patterns with compensation actions
- All OpenAPI specs validate against extracted code
- Parallel run metrics meet targets before cutover
- Zero tolerance for monetary calculation discrepancies
```

## HTML Report Output

After generating the extraction plan, **CRITICAL:** Do NOT generate the HTML report in the same turn as the Markdown analysis to avoid context exhaustion. Only generate the HTML if explicitly requested in a separate turn. When requested, render the results as a self-contained HTML page using the `visual-explainer` skill. The HTML report should include:

- **Dashboard header** with KPI cards: total procedures analyzed, P1/P2/P3/P4 counts, Cloud Run services to create, saga patterns designed, OpenAPI specs generated
- **Extraction priority table** as an interactive HTML table with priority badges (P1=red critical, P2=orange blocker, P3=yellow transform, P4=green simple), bounded context grouping, complexity score, and daily execution count
- **Bounded context map** (visual diagram) showing DDD contexts with procedure groupings and inter-context dependencies
- **Saga flow diagrams** for each P2 procedure showing steps and compensation actions
- **Parallel run metrics dashboard** with target thresholds and current match rates (placeholder for live data)
- **Service architecture diagram** showing Cloud Run services, Spanner database, Cloud Workflows, and integration points
- **Migration timeline** showing extraction phases (shadow -> canary -> partial -> primary -> cutover)

Write the HTML file to `./diagrams/tsql-to-application-extractor-report.html` and open it in the browser.

## Guidelines

- NEVER accept non-zero monetary discrepancies in parallel run validation -- financial calculations must match exactly
- ALWAYS use BigDecimal (Java) or Decimal (Python) for monetary amounts -- never float/double
- Map Sybase MONEY type to Spanner NUMERIC and Java BigDecimal / Python Decimal
- Design saga compensation actions for every state-changing step in cross-database transactions
- Use Cloud Workflows for saga orchestration -- avoid hand-coded saga coordinators
- Configure Spanner session pools for Cloud Run cold start behavior (min sessions > 0)
- Generate OpenAPI specs directly from stored procedure signatures for contract accuracy
- Include error response schemas in OpenAPI mapping RAISERROR codes to HTTP status codes
- Design parallel run with shadow traffic first (read-only comparison) before dual-write
- Track latency regression: Cloud Run + Spanner should not exceed 2x Sybase stored proc latency
- Group procedures by bounded context for service boundary design
- Use repository pattern for P4 CRUD procedures -- do not over-engineer simple operations
- Consider Spanner read-only transactions for query-only procedures (better performance)
- Use stale reads where freshness requirements allow (reporting queries)
- Batch mutations for bulk insert procedures (replacing BCP operations)
- Handle @@identity to sequence migration carefully -- existing ID values must be preserved
