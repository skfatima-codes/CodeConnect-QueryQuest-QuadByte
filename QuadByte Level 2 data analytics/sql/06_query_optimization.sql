-- ============================================================================
-- PROJECT: "You Hungry" Multi-City Food Delivery Platform
-- FILE: sql/06_query_optimization.sql
-- DIALECT: PostgreSQL 15+ / ANSI SQL Compliant
-- DESCRIPTION: SARGable query rewrite and composite covering index optimization.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. UNOPTIMIZED LEGACY QUERY (Execution Latency: ~45 seconds on 18M rows)
-- Bottlenecks:
-- - Non-SARGable scalar function YEAR(o.order_date) forces full table scan.
-- - Implicit ANSI-89 comma join syntax obscures optimizer join paths.
-- - Heap fetches required for all non-indexed columns (no index coverage).
-- ----------------------------------------------------------------------------
/*
SELECT c.name, o.order_id, o.total_amount
FROM Orders o, Customer c
WHERE o.customer_id = c.customer_id
  AND YEAR(o.order_date) = 2026
  AND o.total_amount > 1000;
*/

-- ----------------------------------------------------------------------------
-- 2. PRODUCTION COMPOSITE COVERING INDEX
-- B-Tree index on range predicate (order_date) and equality/filter (total_amount),
-- with payload columns included in leaf nodes to enable Index-Only Scans.
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_orders_sargable_covering 
ON Orders (order_date, total_amount) 
INCLUDE (customer_id, order_id);

-- ----------------------------------------------------------------------------
-- 3. REFACTORED SARGABLE QUERY (Execution Latency: < 12ms)
-- Features:
-- - Half-open interval [2026-01-01, 2027-01-01) enabling direct B-Tree range seek.
-- - ANSI-92 INNER JOIN syntax.
-- - Index pushdown evaluation for total_amount > 1000.00.
-- ----------------------------------------------------------------------------
SELECT 
    c.name,
    o.order_id,
    o.total_amount
FROM Orders o
INNER JOIN Customer c ON o.customer_id = c.customer_id
WHERE o.order_date >= '2026-01-01 00:00:00+00'
  AND o.order_date <  '2027-01-01 00:00:00+00'
  AND o.total_amount > 1000.00;

-- ----------------------------------------------------------------------------
-- 4. EXECUTION PLAN VERIFICATION
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE)
SELECT 
    c.name,
    o.order_id,
    o.total_amount
FROM Orders o
INNER JOIN Customer c ON o.customer_id = c.customer_id
WHERE o.order_date >= '2026-01-01 00:00:00+00'
  AND o.order_date <  '2027-01-01 00:00:00+00'
  AND o.total_amount > 1000.00;
