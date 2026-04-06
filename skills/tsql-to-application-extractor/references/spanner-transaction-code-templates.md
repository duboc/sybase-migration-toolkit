# Spanner Transaction Code Templates

This reference provides ready-to-use Java and Python code templates for common Spanner transaction patterns used when extracting Sybase stored procedure logic into Cloud Run microservices.

## Read-Write Transaction with Retry (Java)

```java
import com.google.cloud.spanner.*;

@Service
public class SpannerTransactionService {

    private final DatabaseClient dbClient;

    public SpannerTransactionService(DatabaseClient dbClient) {
        this.dbClient = dbClient;
    }

    /**
     * Read-write transaction with automatic retry on abort.
     * Equivalent to Sybase BEGIN TRAN ... COMMIT pattern.
     *
     * IMPORTANT: The transaction function may be called multiple times
     * due to Spanner's optimistic concurrency control. Ensure the
     * function is idempotent (no side effects outside Spanner).
     */
    public TradeResult bookTradeInTransaction(TradeRequest request) {
        return dbClient.readWriteTransaction().run(transaction -> {

            // 1. Read current state (within transaction = locked)
            Struct account = transaction.readRow(
                "accounts",
                Key.of(request.getEntityId(), request.getAccountId()),
                Arrays.asList("balance", "available_balance", "status"));

            if (account == null) {
                throw new NotFoundException("Account not found: " + request.getAccountId());
            }

            if (!"ACTIVE".equals(account.getString("status"))) {
                throw new IllegalStateException("Account is not active");
            }

            // 2. Business logic validation
            BigDecimal currentBalance = account.getBigDecimal("available_balance");
            BigDecimal tradeAmount = request.getQuantity().multiply(request.getPrice());

            if (request.getSide().equals("BUY") && currentBalance.compareTo(tradeAmount) < 0) {
                throw new InsufficientFundsException(
                    "Insufficient funds: available=" + currentBalance + " required=" + tradeAmount);
            }

            // 3. Generate IDs from sequences
            long orderId = getNextSequenceValue(transaction, "seq_order_id");
            long fillId = getNextSequenceValue(transaction, "seq_fill_id");

            // 4. Buffer mutations (applied atomically on commit)
            List<Mutation> mutations = new ArrayList<>();

            // Insert order
            mutations.add(Mutation.newInsertBuilder("orders")
                .set("order_id").to(orderId)
                .set("account_id").to(request.getAccountId())
                .set("instrument_id").to(request.getInstrumentId())
                .set("side").to(request.getSide())
                .set("quantity").to(request.getQuantity())
                .set("price").to(request.getPrice())
                .set("status").to("FILLED")
                .set("order_date").to(Value.COMMIT_TIMESTAMP)
                .set("created_at").to(Value.COMMIT_TIMESTAMP)
                .build());

            // Insert fill
            mutations.add(Mutation.newInsertBuilder("fills")
                .set("order_id").to(orderId)
                .set("fill_id").to(fillId)
                .set("fill_quantity").to(request.getQuantity())
                .set("fill_price").to(request.getPrice())
                .set("fill_amount").to(tradeAmount)
                .set("created_at").to(Value.COMMIT_TIMESTAMP)
                .build());

            // Update account balance
            BigDecimal newBalance = request.getSide().equals("BUY")
                ? currentBalance.subtract(tradeAmount)
                : currentBalance.add(tradeAmount);

            mutations.add(Mutation.newUpdateBuilder("accounts")
                .set("entity_id").to(request.getEntityId())
                .set("account_id").to(request.getAccountId())
                .set("available_balance").to(newBalance)
                .set("updated_at").to(Value.COMMIT_TIMESTAMP)
                .build());

            // Audit trail
            mutations.add(Mutation.newInsertBuilder("audit_entries")
                .set("audit_id").to(getNextSequenceValue(transaction, "seq_audit_id"))
                .set("entity_type").to("TRADE")
                .set("entity_id").to(orderId)
                .set("action").to("BOOK")
                .set("user_id").to(request.getTraderId())
                .set("spanner_commit_ts").to(Value.COMMIT_TIMESTAMP)
                .build());

            transaction.buffer(mutations);

            return new TradeResult(orderId, fillId, "BOOKED", newBalance);
        });
    }

    private long getNextSequenceValue(TransactionContext tx, String seqName) {
        try (ResultSet rs = tx.executeQuery(
                Statement.of("SELECT GET_NEXT_SEQUENCE_VALUE(SEQUENCE " + seqName + ")"))) {
            rs.next();
            return rs.getLong(0);
        }
    }
}
```

## Read-Only Transaction (Java)

```java
/**
 * Read-only transaction for consistent multi-table reads.
 * Equivalent to Sybase SET TRANSACTION ISOLATION LEVEL READ COMMITTED
 * with multiple SELECT statements.
 */
public PortfolioSnapshot getPortfolioSnapshot(long portfolioId) {
    try (ReadOnlyTransaction txn = dbClient.readOnlyTransaction()) {

        // All reads see a consistent snapshot
        Struct portfolio = txn.readRow(
            "portfolios",
            Key.of(portfolioId),
            Arrays.asList("portfolio_name", "base_currency", "status"));

        ResultSet positions = txn.executeQuery(
            Statement.newBuilder(
                "SELECT instrument_id, quantity, market_value, unrealized_pnl "
                + "FROM positions WHERE portfolio_id = @pid")
                .bind("pid").to(portfolioId)
                .build());

        List<PositionRow> positionList = new ArrayList<>();
        while (positions.next()) {
            positionList.add(new PositionRow(
                positions.getLong("instrument_id"),
                positions.getBigDecimal("quantity"),
                positions.getBigDecimal("market_value"),
                positions.getBigDecimal("unrealized_pnl")));
        }

        return new PortfolioSnapshot(portfolio, positionList);
    }
}
```

## Read-Only Transaction (Python)

```python
def get_portfolio_snapshot(database, portfolio_id):
    """
    Read-only transaction for consistent multi-table reads.
    All reads see the same consistent snapshot.
    """
    with database.snapshot() as snapshot:
        # Read portfolio header
        portfolio = snapshot.read(
            "portfolios",
            columns=["portfolio_name", "base_currency", "status"],
            keyset=spanner.KeySet(keys=[(portfolio_id,)])
        )
        portfolio_row = list(portfolio)[0]

        # Read all positions (consistent with portfolio read)
        positions = snapshot.execute_sql(
            "SELECT instrument_id, quantity, market_value, unrealized_pnl "
            "FROM positions WHERE portfolio_id = @pid",
            params={"pid": portfolio_id},
            param_types={"pid": spanner.param_types.INT64}
        )
        position_list = [
            {
                "instrument_id": row[0],
                "quantity": row[1],
                "market_value": row[2],
                "unrealized_pnl": row[3]
            }
            for row in positions
        ]

    return {
        "portfolio_name": portfolio_row[0],
        "currency": portfolio_row[1],
        "status": portfolio_row[2],
        "positions": position_list
    }
```

## Partitioned DML (Bulk Operations)

```java
/**
 * Partitioned DML for large-scale data modifications.
 * Equivalent to Sybase bulk UPDATE/DELETE operations.
 *
 * Characteristics:
 * - Runs across multiple partitions in parallel
 * - No transaction size limits
 * - Lower latency for large operations
 * - NOT atomic (partial completion possible)
 * - Best for: archival, cleanup, bulk status updates
 */
public long archiveOldTrades(LocalDate cutoffDate) {
    return dbClient.executePartitionedUpdate(
        Statement.newBuilder(
            "UPDATE trades SET status = 'ARCHIVED' "
            + "WHERE trade_date < @cutoff AND status = 'SETTLED'")
            .bind("cutoff").to(cutoffDate.toString())
            .build());
}

public long purgeExpiredSessions() {
    return dbClient.executePartitionedUpdate(
        Statement.of("DELETE FROM user_sessions WHERE expires_at < CURRENT_TIMESTAMP()"));
}
```

```python
def archive_old_trades(database, cutoff_date):
    """Partitioned DML for large bulk updates."""
    row_count = database.execute_partitioned_dml(
        "UPDATE trades SET status = 'ARCHIVED' "
        "WHERE trade_date < @cutoff AND status = 'SETTLED'",
        params={"cutoff": cutoff_date},
        param_types={"cutoff": spanner.param_types.DATE}
    )
    return row_count
```

## Saga Pattern with Cloud Workflows YAML

```yaml
# Cloud Workflows: Trade Settlement Saga
# Replaces Sybase cross-database transaction:
#   BEGIN TRAN
#     UPDATE trading_db..trades SET status = 'SETTLING'
#     INSERT clearing_db..settlements ...
#     UPDATE position_db..positions ...
#   COMMIT TRAN

main:
  params: [input]
  steps:
    - init:
        assign:
          - saga_id: ${sys.get_env("GOOGLE_CLOUD_WORKFLOW_EXECUTION_ID")}
          - trade_id: ${input.trade_id}
          - base_url: ${sys.get_env("CLOUD_RUN_BASE_URL")}

    # Step 1: Update trade status
    - update_trade_status:
        try:
          call: http.post
          args:
            url: ${base_url + "/api/v1/trades/" + string(trade_id) + "/status"}
            auth:
              type: OIDC
            body:
              status: "SETTLING"
              saga_id: ${saga_id}
          result: trade_result
        except:
          as: e
          steps:
            - log_trade_error:
                call: sys.log
                args:
                  severity: ERROR
                  text: ${"Trade status update failed: " + json.encode_to_string(e)}
            - fail_saga:
                raise:
                  code: "TRADE_UPDATE_FAILED"
                  message: ${e.message}

    # Step 2: Create settlement record
    - create_settlement:
        try:
          call: http.post
          args:
            url: ${base_url + "/api/v1/settlements"}
            auth:
              type: OIDC
            body:
              trade_id: ${trade_id}
              settlement_date: ${input.settlement_date}
              amount: ${input.amount}
              currency: ${input.currency}
              saga_id: ${saga_id}
          result: settlement_result
        except:
          as: e
          steps:
            # Compensate Step 1
            - compensate_trade:
                call: http.post
                args:
                  url: ${base_url + "/api/v1/trades/" + string(trade_id) + "/status"}
                  auth:
                    type: OIDC
                  body:
                    status: "PENDING"
                    saga_id: ${saga_id}
                    reason: "Settlement creation failed, reverting"
            - fail_saga_2:
                raise:
                  code: "SETTLEMENT_FAILED"
                  message: ${e.message}

    # Step 3: Update positions
    - update_positions:
        try:
          call: http.post
          args:
            url: ${base_url + "/api/v1/positions/update"}
            auth:
              type: OIDC
            body:
              portfolio_id: ${input.portfolio_id}
              instrument_id: ${input.instrument_id}
              quantity_delta: ${input.quantity}
              side: ${input.side}
              saga_id: ${saga_id}
          result: position_result
        except:
          as: e
          steps:
            # Compensate Step 2
            - compensate_settlement:
                call: http.post
                args:
                  url: ${base_url + "/api/v1/settlements/" + string(settlement_result.body.settlement_id) + "/cancel"}
                  auth:
                    type: OIDC
                  body:
                    reason: "Position update failed"
                    saga_id: ${saga_id}
            # Compensate Step 1
            - compensate_trade_2:
                call: http.post
                args:
                  url: ${base_url + "/api/v1/trades/" + string(trade_id) + "/status"}
                  auth:
                    type: OIDC
                  body:
                    status: "PENDING"
                    saga_id: ${saga_id}
                    reason: "Position update failed, reverting"
            - fail_saga_3:
                raise:
                  code: "POSITION_UPDATE_FAILED"
                  message: ${e.message}

    # Success
    - return_result:
        return:
          status: "SETTLED"
          saga_id: ${saga_id}
          trade_id: ${trade_id}
          settlement_id: ${settlement_result.body.settlement_id}
```

## Commit Timestamp Reads

```java
/**
 * Read the commit timestamp of a recently written row.
 * Useful for returning the exact server-side timestamp to the client.
 */
public Timestamp getCommitTimestamp(long orderId) {
    try (ResultSet rs = dbClient.singleUse().executeQuery(
            Statement.newBuilder(
                "SELECT spanner_commit_ts FROM orders WHERE order_id = @id")
                .bind("id").to(orderId)
                .build())) {
        if (rs.next()) {
            return rs.getTimestamp("spanner_commit_ts");
        }
        throw new NotFoundException("Order not found: " + orderId);
    }
}
```

## Batch Mutations (Replacing BCP Bulk Operations)

```java
/**
 * Batch mutation for bulk data loading.
 * Replaces Sybase BCP IN operations.
 *
 * Spanner limits: ~80,000 mutations or 100MB per commit.
 * For larger loads, chunk into multiple commits.
 */
public void bulkLoadTrades(List<TradeRecord> records) {
    final int BATCH_SIZE = 10_000;  // Mutations per commit

    List<List<TradeRecord>> batches = Lists.partition(records, BATCH_SIZE);

    for (List<TradeRecord> batch : batches) {
        List<Mutation> mutations = batch.stream()
            .map(record -> Mutation.newInsertBuilder("trades")
                .set("trade_id").to(record.getTradeId())
                .set("account_id").to(record.getAccountId())
                .set("instrument_id").to(record.getInstrumentId())
                .set("side").to(record.getSide())
                .set("quantity").to(record.getQuantity())
                .set("price").to(record.getPrice())
                .set("amount").to(record.getAmount())
                .set("trade_date").to(record.getTradeDate().toString())
                .set("status").to(record.getStatus())
                .set("spanner_commit_ts").to(Value.COMMIT_TIMESTAMP)
                .build())
            .collect(Collectors.toList());

        dbClient.write(mutations);
        log.info("Loaded batch of {} records", batch.size());
    }
}
```

```python
def bulk_load_trades(database, records):
    """
    Batch mutation for bulk data loading.
    Replaces Sybase BCP IN operations.
    """
    BATCH_SIZE = 10_000

    for i in range(0, len(records), BATCH_SIZE):
        chunk = records[i:i + BATCH_SIZE]
        with database.batch() as batch:
            batch.insert(
                "trades",
                columns=[
                    "trade_id", "account_id", "instrument_id",
                    "side", "quantity", "price", "amount",
                    "trade_date", "status", "spanner_commit_ts"
                ],
                values=[
                    (
                        r.trade_id, r.account_id, r.instrument_id,
                        r.side, r.quantity, r.price, r.amount,
                        r.trade_date, r.status, spanner.COMMIT_TIMESTAMP
                    )
                    for r in chunk
                ]
            )
        print(f"Loaded batch of {len(chunk)} records")
```

## Cloud Run Dockerfile Template

```dockerfile
# Multi-stage build for Java Spring Boot service
FROM eclipse-temurin:21-jdk-alpine AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN ./mvnw clean package -DskipTests

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# Copy built JAR
COPY --from=build /app/target/*.jar app.jar

# Cloud Run sets PORT environment variable
ENV PORT=8080
EXPOSE ${PORT}

# JVM configuration for Cloud Run
ENV JAVA_OPTS="-XX:+UseG1GC \
  -XX:MaxRAMPercentage=75.0 \
  -XX:+UseContainerSupport \
  -Djava.security.egd=file:/dev/./urandom"

ENTRYPOINT ["sh", "-c", "java ${JAVA_OPTS} -jar app.jar --server.port=${PORT}"]
```

## Cloud Run service.yaml Template

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: trade-service
  annotations:
    run.googleapis.com/description: "Trade booking microservice (extracted from sp_book_trade)"
    run.googleapis.com/ingress: internal-and-cloud-load-balancing
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: "1"    # Avoid cold starts
        autoscaling.knative.dev/maxScale: "100"
        run.googleapis.com/cpu-throttling: "false" # Always-on CPU
        run.googleapis.com/startup-cpu-boost: "true"
    spec:
      containerConcurrency: 80    # Requests per container
      timeoutSeconds: 300
      serviceAccountName: trade-service@${PROJECT_ID}.iam.gserviceaccount.com
      containers:
        - image: gcr.io/${PROJECT_ID}/trade-service:latest
          ports:
            - containerPort: 8080
          env:
            - name: SPANNER_PROJECT
              value: ${PROJECT_ID}
            - name: SPANNER_INSTANCE
              value: trading-instance
            - name: SPANNER_DATABASE
              value: trading-db
            - name: SESSION_POOL_MIN
              value: "100"
            - name: SESSION_POOL_MAX
              value: "400"
            - name: LOG_LEVEL
              value: INFO
          resources:
            limits:
              cpu: "2"
              memory: 2Gi
          startupProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
            failureThreshold: 12
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            periodSeconds: 15
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            periodSeconds: 10
```
