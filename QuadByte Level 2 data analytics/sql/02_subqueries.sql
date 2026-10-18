-- ============================================================================
-- PROJECT: "You Hungry" Multi-City Food Delivery Platform
-- FILE: sql/02_subqueries.sql
-- DIALECT: PostgreSQL 15+ / ANSI SQL Compliant
-- DESCRIPTION: High-performance subquery patterns for OLTP and operational intelligence.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Query 2a: Customers who have never placed an order
-- Pattern: NOT EXISTS anti-join optimization vs NULL-safe NOT IN
-- ----------------------------------------------------------------------------

-- Primary Implementation: Index-driven Anti-Join (NOT EXISTS)
SELECT 
    c.customer_id,
    c.name,
    c.phone,
    c.city_id,
    c.created_at
FROM Customer c
WHERE NOT EXISTS (
    SELECT 1 
    FROM Orders o 
    WHERE o.customer_id = c.customer_id
)
ORDER BY c.customer_id ASC;

-- Alternative Implementation: Guarded NOT IN with explicit NULL exclusion
SELECT 
    c.customer_id,
    c.name,
    c.phone,
    c.city_id,
    c.created_at
FROM Customer c
WHERE c.customer_id NOT IN (
    SELECT o.customer_id 
    FROM Orders o 
    WHERE o.customer_id IS NOT NULL
)
ORDER BY c.customer_id ASC;


-- ----------------------------------------------------------------------------
-- Query 2b: Restaurants with average rating above platform-wide average
-- Pattern: Scalar subquery evaluation in HAVING clause
-- ----------------------------------------------------------------------------
SELECT 
    r.restaurant_id,
    r.name AS restaurant_name,
    ci.city_name,
    ROUND(AVG(rt.score), 2) AS restaurant_avg_rating,
    COUNT(rt.rating_id) AS total_reviews
FROM Restaurant r
INNER JOIN City ci ON r.city_id = ci.city_id
INNER JOIN RestaurantRating rt ON r.restaurant_id = rt.restaurant_id
GROUP BY 
    r.restaurant_id, 
    r.name, 
    ci.city_name
HAVING AVG(rt.score) > (
    SELECT AVG(score) 
    FROM RestaurantRating
    WHERE score IS NOT NULL
)
ORDER BY restaurant_avg_rating DESC, total_reviews DESC;


-- ----------------------------------------------------------------------------
-- Query 2c: Rider with the most completed deliveries in Karachi
-- Pattern: Derived aggregation subquery joined with tie-handling scalar max
-- ----------------------------------------------------------------------------
SELECT 
    rd.rider_id,
    rd.name AS rider_name,
    rd.phone,
    k_stats.completed_deliveries,
    k_stats.delivery_city
FROM Rider rd
INNER JOIN (
    SELECT 
        o.rider_id,
        ci.city_name AS delivery_city,
        COUNT(o.order_id) AS completed_deliveries
    FROM Orders o
    INNER JOIN City ci ON o.city_id = ci.city_id
    WHERE ci.city_name = 'Karachi'
      AND o.status = 'delivered'
      AND o.rider_id IS NOT NULL
    GROUP BY o.rider_id, ci.city_name
) AS k_stats ON rd.rider_id = k_stats.rider_id
WHERE k_stats.completed_deliveries = (
    SELECT MAX(sub.order_count)
    FROM (
        SELECT COUNT(o2.order_id) AS order_count
        FROM Orders o2
        INNER JOIN City ci2 ON o2.city_id = ci2.city_id
        WHERE ci2.city_name = 'Karachi'
          AND o2.status = 'delivered'
          AND o2.rider_id IS NOT NULL
        GROUP BY o2.rider_id
    ) AS sub
);


-- ----------------------------------------------------------------------------
-- Query 2d: Customers who ordered from more than 3 distinct restaurants
-- Pattern: Multi-row subquery in WHERE with GROUP BY / HAVING
-- ----------------------------------------------------------------------------
SELECT 
    c.customer_id,
    c.name AS customer_name,
    c.email,
    c.phone,
    c.created_at
FROM Customer c
WHERE c.customer_id IN (
    SELECT o.customer_id
    FROM Orders o
    WHERE o.status != 'cancelled'
    GROUP BY o.customer_id
    HAVING COUNT(DISTINCT o.restaurant_id) > 3
)
ORDER BY c.customer_id ASC;
