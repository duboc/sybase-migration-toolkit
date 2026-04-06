# Sybase ASE to Cloud Spanner Data Type Mapping

Complete reference for mapping Sybase ASE data types to Google Cloud Spanner (GoogleSQL) equivalents.

## Numeric Types

| Sybase ASE Type | Range/Precision | Spanner Type | Notes |
|----------------|-----------------|-------------|-------|
| `TINYINT` | 0 to 255 | `INT64` | Spanner has no small integer types. INT64 handles all ranges. |
| `SMALLINT` | -32,768 to 32,767 | `INT64` | Same — upcast to INT64. |
| `INT` / `INTEGER` | -2^31 to 2^31-1 | `INT64` | Direct mapping with wider range. |
| `BIGINT` | -2^63 to 2^63-1 | `INT64` | Direct mapping. |
| `UNSIGNED SMALLINT` | 0 to 65,535 | `INT64` | Spanner has no unsigned types. Validate application doesn't depend on unsigned overflow behavior. |
| `UNSIGNED INT` | 0 to 2^32-1 | `INT64` | Same caveat about unsigned semantics. |
| `UNSIGNED BIGINT` | 0 to 2^64-1 | `INT64` | Values > 2^63-1 will overflow. Flag these columns. |
| `FLOAT` | 15-digit precision | `FLOAT64` | Direct mapping. IEEE 754 double precision. |
| `REAL` | 7-digit precision | `FLOAT64` | Upcast from single to double precision. |
| `DOUBLE PRECISION` | 15-digit precision | `FLOAT64` | Direct mapping. |
| `NUMERIC(p,s)` | p: 1-38, s: 0-38 | `NUMERIC` | Spanner NUMERIC: 29 digits before decimal point, 9 digits after. If p-s > 29 or s > 9, flag as precision loss risk. |
| `DECIMAL(p,s)` | Same as NUMERIC | `NUMERIC` | Identical to NUMERIC mapping. |
| `MONEY` | -922,337,203,685,477.5808 to +922... | `NUMERIC` | 4 decimal places. Map to NUMERIC. Verify MONEY arithmetic behavior (implicit rounding rules differ from NUMERIC). |
| `SMALLMONEY` | -214,748.3648 to +214,748.3647 | `NUMERIC` | 4 decimal places. Direct mapping to NUMERIC. |

### Financial Precision Considerations

**MONEY arithmetic in Sybase:**
- Sybase MONEY uses fixed 4-decimal precision with specific rounding rules
- `MONEY * MONEY` produces MONEY (4 decimals) — intermediate precision may be lost
- Spanner NUMERIC uses arbitrary precision arithmetic — results may differ slightly

**Recommendation for financial applications:**
- Map MONEY to `NUMERIC` (no precision specifier in Spanner DDL)
- Validate all financial calculations produce identical results with NUMERIC
- Pay special attention to: interest calculations, FX conversions, fee computations
- Test with boundary values: very large amounts, very small amounts, negative amounts

## String Types

| Sybase ASE Type | Max Length | Spanner Type | Notes |
|----------------|-----------|-------------|-------|
| `CHAR(n)` | 1 to 16,384 | `STRING(n)` | Sybase pads with spaces; Spanner does not. If app depends on padding, add application logic. |
| `VARCHAR(n)` | 1 to 16,384 | `STRING(n)` | Direct mapping. Sybase n is bytes; Spanner n is UTF-8 characters. For ASCII data, equivalent. |
| `NCHAR(n)` | 1 to 8,192 | `STRING(n)` | Spanner STRING is always Unicode. Direct mapping. |
| `NVARCHAR(n)` | 1 to 8,192 | `STRING(n)` | Direct mapping. |
| `UNICHAR(n)` | 1 to 8,192 | `STRING(n)` | Sybase-specific Unicode type. Direct mapping. |
| `UNIVARCHAR(n)` | 1 to 8,192 | `STRING(n)` | Sybase-specific Unicode type. Direct mapping. |
| `TEXT` | 2^31-1 bytes | `STRING(MAX)` | Spanner MAX = 2,621,440 characters. If TEXT columns exceed this, use Cloud Storage. |
| `UNITEXT` | 2^31-1 bytes | `STRING(MAX)` | Unicode text. Same Spanner limit. |

### String Encoding Notes

- Sybase ASE default character set may be iso_1 (ISO 8859-1), utf8, or cp850
- Spanner always uses UTF-8
- Validate character set conversion for non-ASCII data (accented characters, CJK)
- CHAR columns: Sybase right-pads with spaces to declared length; Spanner does not pad. If application comparison logic depends on padding, add `RTRIM()` or application normalization.

## Binary Types

| Sybase ASE Type | Max Length | Spanner Type | Notes |
|----------------|-----------|-------------|-------|
| `BINARY(n)` | 1 to 16,384 | `BYTES(n)` | Direct mapping. |
| `VARBINARY(n)` | 1 to 16,384 | `BYTES(n)` | Direct mapping. |
| `IMAGE` | 2^31-1 bytes | `BYTES(MAX)` | Spanner MAX = 10,485,760 bytes. For larger objects, use Cloud Storage with a reference column. |

## Date/Time Types

| Sybase ASE Type | Precision | Spanner Type | Notes |
|----------------|-----------|-------------|-------|
| `DATETIME` | 1/300th second (~3.33ms) | `TIMESTAMP` | Spanner TIMESTAMP has nanosecond precision, always UTC. Convert timezone-dependent values. |
| `SMALLDATETIME` | 1 minute | `TIMESTAMP` | Upcast precision. Minute-level precision becomes nanosecond-capable. |
| `BIGDATETIME` (ASE 15.5+) | Microsecond | `TIMESTAMP` | Direct mapping with higher precision. |
| `DATE` (ASE 12.5.1+) | Day | `DATE` | Direct mapping. |
| `TIME` (ASE 12.5.1+) | 1/300th second | `STRING(16)` | **No TIME type in Spanner.** Store as STRING formatted `HH:MM:SS.ffffff`. |
| `BIGTIME` (ASE 15.5+) | Microsecond | `STRING(16)` | **No TIME type in Spanner.** Store as STRING formatted `HH:MM:SS.ffffff`. |

### Timestamp Migration Considerations

- **Timezone handling**: Sybase DATETIME stores local time (no timezone info). Spanner TIMESTAMP is always UTC. Must establish timezone conversion rules during migration.
- **Trade timestamps**: Financial applications often need exact timestamp sequencing. Validate that TIMESTAMP precision is sufficient for trade ordering.
- **DATETIME arithmetic**: Sybase uses `DATEADD()`/`DATEDIFF()`; Spanner uses `TIMESTAMP_ADD()`/`TIMESTAMP_DIFF()`. Different function signatures.

## Special Types

| Sybase ASE Type | Purpose | Spanner Type | Notes |
|----------------|---------|-------------|-------|
| `BIT` | Boolean (0/1) | `BOOL` | Direct mapping. Sybase BIT is 0/1; Spanner BOOL is TRUE/FALSE. |
| `TIMESTAMP` (Sybase) | Row version (auto-updated binary) | `BYTES(8)` or omit | **Not a date/time type.** Sybase TIMESTAMP is a row versioning mechanism. Map to BYTES(8) if needed, or use Spanner commit timestamps. |
| `IDENTITY` | Auto-increment column | `INT64` + sequence | Use `BIT_REVERSED_POSITIVE` sequence. See key design guide. |
| User-defined types | `sp_addtype` custom types | Resolve to base | Must resolve chain: UDT → base type → Spanner type. |
| `JAVA` types (ASE 15+) | Java objects in columns | `BYTES` or `STRING` | Serialize Java objects; store as BYTES. Consider redesign. |

### IDENTITY Column Migration

Sybase IDENTITY columns generate sequential integers. In Spanner, sequential keys cause write hotspots.

**Migration pattern:**

```sql
-- Sybase ASE
CREATE TABLE trades (
    trade_id    NUMERIC(12,0) IDENTITY,
    trade_date  DATETIME,
    amount      MONEY
)

-- Spanner (GoogleSQL)
CREATE SEQUENCE trade_seq OPTIONS (
    sequence_kind = 'bit_reversed_positive'
);

CREATE TABLE trades (
    trade_id    INT64 DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE trade_seq)),
    trade_date  TIMESTAMP,
    amount      NUMERIC
) PRIMARY KEY (trade_id);
```

### User-Defined Type Resolution

Sybase UDTs created via `sp_addtype` must be resolved to base types:

```sql
-- Sybase UDT definition
EXEC sp_addtype currency, 'numeric(19,4)', 'NOT NULL'
EXEC sp_addtype account_num, 'varchar(20)', 'NOT NULL'
EXEC sp_addtype trade_status, 'char(1)', 'NOT NULL'

-- Resolution chain
-- currency    → numeric(19,4)  → NUMERIC
-- account_num → varchar(20)    → STRING(20)
-- trade_status → char(1)       → STRING(1)
```

## Type Mapping Decision Tree

```
1. Is it a user-defined type?
   YES → Resolve to base type via sp_addtype, then continue
   NO  → Continue

2. Is it an integer type (TINYINT/SMALLINT/INT/BIGINT)?
   YES → Map to INT64
   NO  → Continue

3. Is it a float type (FLOAT/REAL/DOUBLE)?
   YES → Map to FLOAT64
   NO  → Continue

4. Is it NUMERIC/DECIMAL/MONEY/SMALLMONEY?
   YES → Map to NUMERIC. Flag if precision > 29.9
   NO  → Continue

5. Is it a string type (CHAR/VARCHAR/NCHAR/NVARCHAR/UNICHAR/UNIVARCHAR)?
   YES → Map to STRING(n)
   NO  → Continue

6. Is it TEXT/UNITEXT?
   YES → Map to STRING(MAX). Flag if > 2.6M characters
   NO  → Continue

7. Is it IMAGE/BINARY/VARBINARY?
   YES → Map to BYTES(n) or BYTES(MAX)
   NO  → Continue

8. Is it DATETIME/SMALLDATETIME/BIGDATETIME?
   YES → Map to TIMESTAMP
   NO  → Continue

9. Is it DATE?
   YES → Map to DATE
   NO  → Continue

10. Is it TIME/BIGTIME?
    YES → Map to STRING(16). Flag as HIGH risk.
    NO  → Continue

11. Is it BIT?
    YES → Map to BOOL
    NO  → Continue

12. Is it TIMESTAMP (row version)?
    YES → Map to BYTES(8) or use commit timestamp
    NO  → Flag as unknown type
```
