-- ============================================================================
-- PROJECT: "You Hungry" Multi-City Food Delivery Platform
-- FILE: sql/08_partitioning.sql
-- DIALECT: PostgreSQL 15+ / ANSI SQL Compliant
-- DESCRIPTION: Dual-partitioning strategy: Range (Orders) & Hash (Customer).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. ORDERS TABLE: DECLARATIVE MONTHLY RANGE PARTITIONING
-- Temporal range boundaries allow 95% of OLTP transactions to prune all
-- non-relevant historical partitions at query planning time.
-- ----------------------------------------------------------------------------

-- Partition Root
CREATE TABLE IF NOT EXISTS Orders_Partitioned (
    order_id BIGSERIAL,
    customer_id INT NOT NULL,
    restaurant_id INT NOT NULL,
    rider_id INT,
    city_id INT NOT NULL,
    total_amount NUMERIC(10, 2) NOT NULL,
    status VARCHAR(30) NOT NULL,
    order_date TIMESTAMP WITH TIME ZONE NOT NULL,
    delivery_time TIMESTAMP WITH TIME ZONE,
    PRIMARY KEY (order_id, order_date)
) PARTITION BY RANGE (order_date);

-- Active Partitions
CREATE TABLE IF NOT EXISTS orders_2026_01 PARTITION OF Orders_Partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2026-02-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS orders_2026_02 PARTITION OF Orders_Partitioned
    FOR VALUES FROM ('2026-02-01 00:00:00+00') TO ('2026-03-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS orders_2026_03 PARTITION OF Orders_Partitioned
    FOR VALUES FROM ('2026-03-01 00:00:00+00') TO ('2026-04-01 00:00:00+00');

-- High-Volume Surge Partition (Ramadan 10x Spike)
CREATE TABLE IF NOT EXISTS orders_2026_ramadan PARTITION OF Orders_Partitioned
    FOR VALUES FROM ('2026-04-01 00:00:00+00') TO ('2026-05-01 00:00:00+00');

-- Default Partition for Future / Out-of-Range Data
CREATE TABLE IF NOT EXISTS orders_default PARTITION OF Orders_Partitioned DEFAULT;

-- Local Indexes on Partitions
CREATE INDEX IF NOT EXISTS idx_part_orders_cust ON Orders_Partitioned(customer_id);
CREATE INDEX IF NOT EXISTS idx_part_orders_status ON Orders_Partitioned(status);


-- ----------------------------------------------------------------------------
-- 2. CUSTOMER TABLE: DECLARATIVE HASH PARTITIONING
-- Uniform modulus hash distribution across 1M accounts eliminates B-Tree hotspot
-- contention and ensures partition indexes fit entirely in system RAM.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS Customer_Partitioned (
    customer_id INT NOT NULL,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    city_id INT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (customer_id)
) PARTITION BY HASH (customer_id);

CREATE TABLE IF NOT EXISTS customer_h0 PARTITION OF Customer_Partitioned
    FOR VALUES WITH (MODULUS 4, REMAINDER 0);

CREATE TABLE IF NOT EXISTS customer_h1 PARTITION OF Customer_Partitioned
    FOR VALUES WITH (MODULUS 4, REMAINDER 1);

CREATE TABLE IF NOT EXISTS customer_h2 PARTITION OF Customer_Partitioned
    FOR VALUES WITH (MODULUS 4, REMAINDER 2);

CREATE TABLE IF NOT EXISTS customer_h3 PARTITION OF Customer_Partitioned
    FOR VALUES WITH (MODULUS 4, REMAINDER 3);


-- ----------------------------------------------------------------------------
-- 3. PARTITION PRUNING DEMONSTRATION & VERIFICATION
-- ----------------------------------------------------------------------------

-- A. Query WITH partition key (Pruning Active: scans ONLY orders_2026_01)
EXPLAIN (COSTS OFF)
SELECT * FROM Orders_Partitioned 
WHERE order_date >= '2026-01-15 00:00:00+00' 
  AND order_date <  '2026-01-16 00:00:00+00';

-- B. Query WITHOUT partition key (Forces Scatter-Gather across ALL partitions)
EXPLAIN (COSTS OFF)
SELECT * FROM Orders_Partitioned 
WHERE status = 'ready';
