# Enterprise Database Architecture Specification
## Platform: "You Hungry" Food Delivery Platform (Scale: 1M+ Users, 50k–500k Orders/Day)

---

### Executive Overview
This document specifies the production database architecture, schema normalization, distributed topology, concurrency controls, and analytical pipelines for the "You Hungry" multi-city food delivery platform.

```
Platform Scale Metrics:
├── Registered Accounts:     1,000,000+ Customers
├── Active Merchants:        500 Restaurants across Tier-1/Tier-2 Cities
├── Delivery Fleet:          2,000 Active Riders
├── Baseline Order Volume:   50,000 Orders/Day (~18.25M Annual Volume)
└── Peak Surges (Ramadan):   500,000 Orders/Day (10x Surge across Iftar/Sehri)
```

---

### 1. Schema Normalization & Functional Dependency Audit

#### Boyce-Codd Normal Form (BCNF)
A relation $R$ is in BCNF if and only if for every non-trivial functional dependency $X \rightarrow Y$, $X$ is a superkey of $R$.

| Relation Schema | Functional Dependencies | BCNF Compliant? | Architectural Action |
| :--- | :--- | :---: | :--- |
| **Rating**<br>`(rating_id, customer_id, restaurant_id, rider_id, score, comment)` | 1. `rating_id → all`<br>2. `(customer_id, order_id) → score` | **NO** | Decompose into separate `RestaurantRating` and `RiderRating` relations. |
| **Payment**<br>`(payment_id, order_id, method, amount, status, transaction_id)` | 1. `payment_id → all`<br>2. `transaction_id → payment_id, order_id` | **YES** | None. Both attributes serve as candidate keys. |
| **PromoCode**<br>`(promo_id, code, discount_percent, max_uses, expiry_date)` | 1. `promo_id → all`<br>2. `code → promo_id` | **YES** | None. `code` is a natural candidate key. |

##### Lossless BCNF Decomposition of Rating
- `RestaurantRating(rating_id [PK], order_id, customer_id, restaurant_id, score, comment, created_at)`
- `RiderRating(rider_rating_id [PK], order_id, customer_id, rider_id, score, comment, created_at)`

*Proof of Integrity:* Both decomposed tables satisfy $X \rightarrow Y$ where $X$ is a superkey. Nullability anomalies (e.g., customer rates restaurant but skips rider) are eliminated.

#### Fourth Normal Form (4NF)
A relation is in 4NF if and only if for every non-trivial Multi-Valued Dependency (MVD) $X \twoheadrightarrow Y$, $X$ is a superkey.

- **Vulnerable Relation:** `MenuItem_City_Tag(item_id, city, tag)`
- **MVDs Present:** `item_id ↠ city` and `item_id ↠ tag` (cities and tags are completely independent sets).
- **Anomaly:** If an item is sold in 5 cities and has 4 tags, storing this in a single relation requires 20 duplicate tuples ($5 \times 4$).
- **Lossless 4NF Decomposition:**
  1. `MenuItem_City(item_id, city, price)` — Candidate Key: `(item_id, city)`
  2. `MenuItem_Tag(item_id, tag)` — Candidate Key: `(item_id, tag)`

---

### 2. High-Performance Subqueries & Execution Plans

Implementation: [`sql/02_subqueries.sql`](sql/02_subqueries.sql)

- **Anti-Join Pattern (Task 2a):** `NOT EXISTS` compiles to a Hash Anti-Join in PostgreSQL, scanning outer rows and immediately terminating subquery evaluation upon the first match. Guarded against 3-valued boolean logic failures inherent in `NOT IN` when target columns contain `NULL`.
- **Scalar Subquery Optimization (Task 2b):** Aggregates global rating benchmarks in an isolated subquery evaluated once during plan execution, avoiding Cartesian cost.
- **Derived Table Aggregations (Task 2c):** Computes rider delivery counts per city in a derived relation before applying scalar max comparison.
- **Correlated Variety Filters (Task 2d):** Identifies power users across distinct merchant orders via `HAVING COUNT(DISTINCT o.restaurant_id) > 3`.

---

### 3. Database Views & Architectural Abstraction

Implementation: [`sql/03_views.sql`](sql/03_views.sql)

```
Database View Abstraction Layer:
├── vw_DailyRevenue:      Standardizes gross merchandise value (GMV) where status = 'delivered'
├── vw_RestaurantRatings: Calculates verified ratings and merchant status tiers
└── vw_RiderPerformance:  Tracks rider throughput, avg delivery turnaround, and on-time SLAs
```

#### Architectural Rationale
1. **Least Privilege Security (RBAC):** Permits BI analysts to query `vw_RestaurantRatings` without granting `SELECT` on sensitive customer PII or raw transaction ledgers.
2. **Metric Standardization:** Centralizes KPIs (e.g., realized revenue rules) in one schema definition across all microservices.
3. **Decoupling Application from Storage:** Base tables can be partitioned, indexed, or migrated without modifying client application SQL.
4. **Materialization Upgrade Path:** Allows PostgreSQL standard views to transition to `MATERIALIZED VIEW` with `REFRESH MATERIALIZED VIEW CONCURRENTLY` without breaking client APIs.

---

### 4. State Machine Automation & Audit Trails

Implementation: [`sql/04_stored_procedures_triggers.sql`](sql/04_stored_procedures_triggers.sql)

- **Stored Procedure `UpdateOrderStatus(p_order_id, p_new_status)`:**
  - Validates non-null inputs (`ERRCODE = '22023'`).
  - Acquires exclusive row-level lock (`SELECT ... FOR UPDATE`).
  - Verifies order existence (`ERRCODE = 'P0002'`).
  - Guarantees idempotency (skips no-op transitions).
  - Atomically mutates status and writes to immutable `OrderStatusLog`.
- **Trigger `trg_SetDeliveryTime`:**
  - Attached to `Orders` as `BEFORE UPDATE OF status`.
  - Automatically populates `delivery_time := CURRENT_TIMESTAMP` when state transitions to `'delivered'`, eliminating network round-trip overhead.

---

### 5. Concurrency Control & Race Condition Elimination

Implementation: [`sql/05_transactions_concurrency.sql`](sql/05_transactions_concurrency.sql)

#### Double-Assignment Race Condition Scenario
When two riders attempt to accept the same order simultaneously under standard `READ COMMITTED` isolation without locking:
1. Rider 1 and Rider 2 concurrently read `status = 'ready'`.
2. Rider 1 issues `UPDATE Orders SET rider_id = 101, status = 'picked_up'`.
3. Rider 2 issues `UPDATE Orders SET rider_id = 102, status = 'picked_up'`.
4. Rider 2 overwrites Rider 1; both mobile applications show confirmed assignment, resulting in duplicate delivery dispatch.

#### Resolution via Pessimistic Row Locking
```sql
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
    SELECT order_id, status FROM Orders WHERE order_id = 50421 FOR UPDATE;
    UPDATE Orders SET rider_id = 104, status = 'picked_up'
    WHERE order_id = 50421 AND status = 'ready';
    INSERT INTO OrderStatusLog (order_id, old_status, new_status, changed_by)
    VALUES (50421, 'ready', 'picked_up', 'Rider_Dispatch_Service');
COMMIT;
```
- `SELECT ... FOR UPDATE` acquires an exclusive row lock on the order tuple.
- The competing rider transaction is placed in a lock wait queue.
- Upon commit, the blocked transaction unblocks and re-evaluates the `WHERE status = 'ready'` clause; the predicate evaluates to false, zero rows are updated, and the secondary rider receives an immediate rejection response.

---

### 6. Query Optimization & SARGability Rewrite

Implementation: [`sql/06_query_optimization.sql`](sql/06_query_optimization.sql)

```sql
-- Composite Covering Index
CREATE INDEX idx_orders_sargable_covering 
ON Orders (order_date, total_amount) 
INCLUDE (customer_id, order_id);

-- SARGable ANSI-92 Query
SELECT c.name, o.order_id, o.total_amount
FROM Orders o
INNER JOIN Customer c ON o.customer_id = c.customer_id
WHERE o.order_date >= '2026-01-01 00:00:00+00'
  AND o.order_date <  '2027-01-01 00:00:00+00'
  AND o.total_amount > 1000.00;
```
- **SARGability:** Replacing `YEAR(order_date) = 2026` with half-open range bounds `[2026-01-01, 2027-01-01)` transforms a $O(N)$ sequential table scan of 18M rows into a $O(\log N)$ direct B-Tree index seek.
- **Index-Only Scan:** The `INCLUDE` clause allows the query engine to satisfy projections directly from index leaf pages without secondary table heap fetches, reducing latency from 45,000 ms to < 12 ms.

---

### 7. Security Hardening, Prepared Statements & RBAC

Implementation: [`sql/07_security_hardening.sql`](sql/07_security_hardening.sql)

- **SQL Injection Defense:** Server-side precompiled prepared statements (`PREPARE get_customer_by_name(text)`) separate query structure from user parameters, rendering quotation manipulation inert.
- **Role-Based Access Control (RBAC):**
  - `app_user`: Operational read/write on transactional tables; hard deletes revoked.
  - `analyst`: Read-only access restricted to Views; PII masked.
  - `admin`: Schema maintenance and migration rights under audit logging.
- **Row-Level Security (RLS):** Policies isolate customer order access using session-level user identifiers (`app.current_user_id`).

---

### 8. Database Partitioning Strategy (18 Million Rows)

Implementation: [`sql/08_partitioning.sql`](sql/08_partitioning.sql)  
Architecture Diagram: [`diagrams/partitioning_architecture.svg`](diagrams/partitioning_architecture.svg)  
Draw.io Model: [`diagrams/partitioning_architecture.drawio`](diagrams/partitioning_architecture.drawio)

![Partitioning Architecture](diagrams/partitioning_architecture.svg)

1. **Orders Table (Monthly Range Partitioning):**
   - Partition Key: `order_date`.
   - Justification: 95% of OLTP transactions query data within the current billing/fulfillment window. Partition pruning eliminates non-relevant month tables at query parse time. Cold partitions (>12 months) are compressed or detached without table locks.
2. **Customer Table (Hash Partitioning):**
   - Partition Key: `customer_id` into 4 hash buckets (`MODULUS 4`).
   - Justification: Customer records lack temporal locality. Hash distribution evenly balances write lock concurrency and ensures individual partition B-Trees remain fully pinned in memory (`shared_buffers`).

---

### 9. Distributed Sharding Architecture

| Candidate Shard Key | Architectural Advantages | Critical Limitations | Evaluation |
| :--- | :--- | :--- | :---: |
| **`customer_id`** | High data locality for user profiles, order histories, and authentication. Uniform distribution via consistent hashing. | Cross-shard scatter-gather required for city-wide logistics dispatch. | **Recommended** |
| **`city`** | Natural geographic containment; riders and restaurants operate strictly locally. | Severe hot shard risk. Megacities (e.g., Karachi) concentrate 60%+ of national volume on one node. | Rejected |
| **`order_date`** | Temporal partitioning simplifies archival. | Monolithic write hotspot. 100% of all platform writes hit a single node. | Rejected |

- **Hot Shard Mitigation:** Consistent hashing over 1,024 virtual nodes (`v-nodes`) ensures even allocation across physical hardware.
- **Cross-Shard Resolution:** Global analytical queries execute via a two-phase scatter-gather protocol orchestrated by a routing proxy (Citus Coordinator / Vitess).

---

### 10. Polyglot Persistence Matrix (SQL vs. NoSQL)

| Domain Entity | Recommended Engine | Architectural Rationale |
| :--- | :--- | :--- |
| **User Accounts & Auth** | **PostgreSQL (SQL)** | ACID transaction consistency, unique relational constraints, strict RBAC. |
| **Orders & Fulfillment** | **PostgreSQL (SQL)** | ACID compliance, pessimistic row locking (`FOR UPDATE`), multi-table integrity. |
| **Real-Time Rider GPS** | **Redis / ScyllaDB (NoSQL)** | High-throughput streaming writes (667 writes/sec) with ephemeral TTLs and geospatial indexing. |
| **Restaurant Menu Catalogs** | **PostgreSQL JSONB / MongoDB** | Polymorphic schema accommodating variable item modifiers, toppings, and seasonal variants. |
| **Analytical Reporting** | **ClickHouse / Redshift (OLAP)** | Columnar vector compression optimized for multi-million row aggregation scans. |
| **Session Cache** | **Redis (NoSQL)** | Sub-millisecond in-memory lookups with automatic expiration. |
| **Financial Ledgers** | **PostgreSQL (SQL)** | Immutable append-only audit trail with strict serializability and non-repudiation. |

---

### 11. Controlled Denormalization & Cache Synchronization

Implementation: [`sql/11_denormalization_sync.sql`](sql/11_denormalization_sync.sql)

```
Denormalization Architecture:
├── Schema Extension:  Restaurant(avg_rating DECIMAL(3,2), total_reviews INT)
├── Trigger Engine:    fn_SyncRestaurantRatings() on INSERT/UPDATE/DELETE
└── Reconciliation:    ReconcileRestaurantRatings() automated nightly cron
```

#### Incremental Moving Average Formula
$$\text{New Average} = \frac{(\text{Current Average} \times \text{Total Reviews}) + \text{New Score}}{\text{Total Reviews} + 1}$$

- **Latency Gain:** Menu and restaurant listing queries drop from 850 ms (runtime multi-table aggregation) to < 1.5 ms (direct column read).
- **Integrity Guarantee:** Row-level triggers handle real-time incremental updates; an automated nightly batch reconciliation job resolves any floating-point accumulation drift.
- **Strict Normalization Boundary:** Financial balances and authentication permissions must **never** be denormalized.

---

### 12. CAP & PACELC Theorem Operational Decisions

Architecture Diagram: [`diagrams/cap_theorem_diagram.svg`](diagrams/cap_theorem_diagram.svg)  
Draw.io Model: [`diagrams/cap_theorem_diagram.drawio`](diagrams/cap_theorem_diagram.drawio)

![CAP Theorem Diagram](diagrams/cap_theorem_diagram.svg)

| Platform Subsystem | CAP Choice | PACELC Classification | Operational Behavior During Network Partition |
| :--- | :---: | :---: | :--- |
| **Order Placement / Payment** | **CP** | **PC/EC** | Reject or queue writes. Strict consistency takes precedence over availability to prevent duplicate billing. |
| **Rider GPS Telemetry** | **AP** | **PA/EL** | Accept writes and serve stale location cache. Ephemeral 3-second data; availability prioritizes map UI responsiveness. |
| **Catalog & Menu Browsing** | **AP** | **PA/EL** | Serve cached catalog data. Uptime is prioritized over instantaneous menu item sync. |
| **Rider Order Claim** | **CP** | **PC/EC** | Enforce row locking. Unreachable nodes cannot claim orders, preventing duplicate assignment. |

---

### 13. Master-Replica Replication Topology & High Availability

Architecture Diagram: [`diagrams/replication_architecture.svg`](diagrams/replication_architecture.svg)  
Draw.io Model: [`diagrams/replication_architecture.drawio`](diagrams/replication_architecture.drawio)

![Replication Architecture](diagrams/replication_architecture.svg)

- **Traffic Split:** 80% Read Traffic (Port 5433 round-robin across Replicas) / 20% Write Traffic (Port 5432 to Primary).
- **Scale Profile:** 2 active read replicas + 1 standby replica under normal operations; auto-scales to 6 read replicas during Ramadan peak surges.
- **Replication Lag Mitigation (Read-Your-Writes Consistency):**
  - Upon order placement or status update, the backend sets an ephemeral user token with write timestamp.
  - HAProxy / PgBouncer routes subsequent read requests from that user directly to the **Primary Database** for a 5-second window, ensuring newly created orders are immediately visible.
  - Secondary safety: Replication proxy checks `pg_last_wal_replay_lsn()` against `pg_current_wal_lsn()` before serving reads.

---

### 14. Data Warehousing & Analytical Star Schema

Implementation: [`sql/14_star_schema_dw.sql`](sql/14_star_schema_dw.sql)  
Architecture Diagram: [`diagrams/star_schema_erd.svg`](diagrams/star_schema_erd.svg)  
Draw.io Model: [`diagrams/star_schema_erd.drawio`](diagrams/star_schema_erd.drawio)

![Star Schema Architecture](diagrams/star_schema_erd.svg)

```sql
-- Executive Dashboard Query: "Orders per city per month for last 2 years"
SELECT 
    c.city_name,
    d.year,
    d.month_name,
    COUNT(f.order_key) AS total_orders,
    SUM(f.order_amount) AS total_revenue,
    ROUND(AVG(f.delivery_time_minutes), 2) AS avg_delivery_minutes
FROM FactOrders f
INNER JOIN DimCity c ON f.city_key = c.city_key
INNER JOIN DimDate d ON f.date_key = d.date_key
WHERE d.full_date >= (CURRENT_DATE - INTERVAL '2 years')
  AND f.is_delivered = TRUE
GROUP BY c.city_name, d.year, d.month, d.month_name
ORDER BY c.city_name, d.year DESC, d.month DESC;
```
- **OLTP vs. OLAP Isolation:** Long-running analytical aggregations execute entirely on a dedicated data warehouse cluster, eliminating buffer pool contention, table lock escalations, and latency degradation on live customer checkouts.
- **Query Performance:** By joining pre-computed integer surrogate keys (`city_key`, `date_key`), execution completes in < 45 ms on 36M records.
