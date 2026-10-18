-- ============================================================================
-- PROJECT: "You Hungry" Multi-City Food Delivery Platform
-- FILE: sql/03_views.sql
-- DIALECT: PostgreSQL 15+ / ANSI SQL Compliant
-- DESCRIPTION: Database views for standardized business intelligence & security.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- View 3a: vw_DailyRevenue
-- Purpose: Aggregates daily platform GMV, completed order count, and AOV.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_DailyRevenue AS
SELECT 
    CAST(o.order_date AS DATE) AS order_date,
    COUNT(o.order_id) AS total_orders,
    ROUND(SUM(o.total_amount), 2) AS total_revenue,
    ROUND(AVG(o.total_amount), 2) AS avg_order_value
FROM Orders o
WHERE o.status = 'delivered'
GROUP BY CAST(o.order_date AS DATE)
ORDER BY order_date DESC;

COMMENT ON VIEW vw_DailyRevenue IS 'Daily financial aggregation of gross merchandise value and fulfilled order volume.';


-- ----------------------------------------------------------------------------
-- View 3b: vw_RestaurantRatings
-- Purpose: Summarizes customer feedback, average scores, and review density.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_RestaurantRatings AS
SELECT 
    r.restaurant_id,
    r.name AS restaurant_name,
    ci.city_name AS city,
    COALESCE(ROUND(AVG(rt.score), 2), 0.00) AS average_rating,
    COUNT(rt.rating_id) AS total_reviews,
    CASE 
        WHEN COUNT(rt.rating_id) >= 100 AND AVG(rt.score) >= 4.5 THEN 'Top Rated Merchant'
        WHEN COUNT(rt.rating_id) >= 50  AND AVG(rt.score) >= 4.0 THEN 'Popular'
        WHEN COUNT(rt.rating_id) < 10 THEN 'New Merchant'
        ELSE 'Standard'
    END AS merchant_status
FROM Restaurant r
INNER JOIN City ci ON r.city_id = ci.city_id
LEFT JOIN RestaurantRating rt ON r.restaurant_id = rt.restaurant_id
GROUP BY 
    r.restaurant_id, 
    r.name, 
    ci.city_name;

COMMENT ON VIEW vw_RestaurantRatings IS 'Analytical review summaries and performance tiering per restaurant partner.';


-- ----------------------------------------------------------------------------
-- View 3c: vw_RiderPerformance
-- Purpose: Evaluates rider logistics, delivery speed, and SLA compliance.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_RiderPerformance AS
SELECT 
    rd.rider_id,
    rd.name AS rider_name,
    rd.phone,
    COUNT(o.order_id) AS total_deliveries,
    COALESCE(
        ROUND(
            AVG(EXTRACT(EPOCH FROM (o.delivery_time - o.created_at)) / 60.0)::numeric, 1
        ), 
        0.0
    ) AS avg_delivery_time_minutes,
    COUNT(CASE WHEN EXTRACT(EPOCH FROM (o.delivery_time - o.created_at)) / 60.0 <= 30.0 THEN 1 END) AS on_time_deliveries
FROM Rider rd
LEFT JOIN Orders o ON rd.rider_id = o.rider_id AND o.status = 'delivered'
GROUP BY 
    rd.rider_id, 
    rd.name, 
    rd.phone;

COMMENT ON VIEW vw_RiderPerformance IS 'Operational logistics metrics evaluating rider speed, completed volume, and SLA compliance.';
