# "You Hungry" Platform — Database Architecture & Engineering

Enterprise PostgreSQL database architecture, schema normalization, distributed replication topology, and concurrency control for the "You Hungry" food delivery platform (1M+ accounts, 50k–500k orders/day).

---

## Architecture Summary
Complete technical audit, mathematical proofs, trade-off matrices, and execution metrics are documented in [`ARCHITECTURE.md`](ARCHITECTURE.md).

---

## Directory Manifest

### 1. Database Engineering Modules (`sql/`)
All SQL scripts are compliant with PostgreSQL 15+ and ANSI SQL standards:

| File | Module Description |
| :--- | :--- |
| [`sql/01_core_schema.sql`](sql/01_core_schema.sql) | Normalized relational DDL (3NF/BCNF) with constraints, foreign keys, and indexes. |
| [`sql/02_subqueries.sql`](sql/02_subqueries.sql) | Anti-joins (`NOT EXISTS`), scalar aggregations, and correlated subqueries. |
| [`sql/03_views.sql`](sql/03_views.sql) | Standardized reporting views (`vw_DailyRevenue`, `vw_RestaurantRatings`, `vw_RiderPerformance`). |
| [`sql/04_stored_procedures_triggers.sql`](sql/04_stored_procedures_triggers.sql) | State transition procedure (`UpdateOrderStatus`) and automatic delivery timestamp trigger. |
| [`sql/05_transactions_concurrency.sql`](sql/05_transactions_concurrency.sql) | Concurrency control & pessimistic row locking (`FOR UPDATE`) resolving race conditions. |
| [`sql/06_query_optimization.sql`](sql/06_query_optimization.sql) | SARGable range refactoring and composite covering index definitions. |
| [`sql/07_security_hardening.sql`](sql/07_security_hardening.sql) | Prepared statements, RBAC role matrices (`app_user`, `analyst`, `admin`), and RLS policies. |
| [`sql/08_partitioning.sql`](sql/08_partitioning.sql) | Monthly Range Partitioning (`Orders`) and 4-way Hash Partitioning (`Customer`). |
| [`sql/11_denormalization_sync.sql`](sql/11_denormalization_sync.sql) | Controlled denormalization with incremental triggers and nightly reconciliation. |
| [`sql/14_star_schema_dw.sql`](sql/14_star_schema_dw.sql) | OLAP dimensional star schema (`FactOrders` + dimension tables) and analytical query. |

---

### 2. Architecture Visualizations (`diagrams/`)
All diagrams are provided in both standalone vector SVG and editable Draw.io XML (`.drawio`) formats:

| Architectural Visualization | Vector SVG File | Draw.io XML Model |
| :--- | :--- | :--- |
| **Dual Partitioning Strategy** | [`diagrams/partitioning_architecture.svg`](diagrams/partitioning_architecture.svg) | [`diagrams/partitioning_architecture.drawio`](diagrams/partitioning_architecture.drawio) |
| **Master-Replica Replication Topology** | [`diagrams/replication_architecture.svg`](diagrams/replication_architecture.svg) | [`diagrams/replication_architecture.drawio`](diagrams/replication_architecture.drawio) |
| **CAP & PACELC Operational Matrix** | [`diagrams/cap_theorem_diagram.svg`](diagrams/cap_theorem_diagram.svg) | [`diagrams/cap_theorem_diagram.drawio`](diagrams/cap_theorem_diagram.drawio) |
| **Analytical Star Schema ERD** | [`diagrams/star_schema_erd.svg`](diagrams/star_schema_erd.svg) | [`diagrams/star_schema_erd.drawio`](diagrams/star_schema_erd.drawio) |

---

## Database Deployment & Verification

Deploy schema and modules to a PostgreSQL instance using `psql`:

```bash
# 1. Initialize core relational tables
psql -U postgres -d you_hungry -f sql/01_core_schema.sql

# 2. Deploy views and business intelligence layers
psql -U postgres -d you_hungry -f sql/03_views.sql

# 3. Compile state machine procedures and triggers
psql -U postgres -d you_hungry -f sql/04_stored_procedures_triggers.sql
psql -U postgres -d you_hungry -f sql/05_transactions_concurrency.sql

# 4. Apply indexing, security hardening, and RBAC
psql -U postgres -d you_hungry -f sql/06_query_optimization.sql
psql -U postgres -d you_hungry -f sql/07_security_hardening.sql

# 5. Enable partitioning and denormalization synchronization
psql -U postgres -d you_hungry -f sql/08_partitioning.sql
psql -U postgres -d you_hungry -f sql/11_denormalization_sync.sql
psql -U postgres -d you_hungry -f sql/14_star_schema_dw.sql
```
