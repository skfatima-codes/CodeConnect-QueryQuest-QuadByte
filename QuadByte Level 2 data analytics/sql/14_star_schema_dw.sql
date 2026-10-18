-- ============================================================================
-- PROJECT: "You Hungry" Multi-City Food Delivery Platform
-- FILE: sql/14_star_schema_dw.sql
-- DIALECT: PostgreSQL 15+ / ANSI SQL Compliant
-- DESCRIPTION: OLAP Star Schema DDL & executive analytics query.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. DIMENSION TABLES
-- ----------------------------------------------------------------------------

-- A. DimCity
CREATE TABLE IF NOT EXISTS DimCity (
    city_key INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    city_id INT NOT NULL,
    city_name VARCHAR(50) NOT NULL,
    province VARCHAR(50) NOT NULL,
    country VARCHAR(50) NOT NULL DEFAULT 'Pakistan',
    delivery_tier VARCHAR(20) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- B. DimDate
CREATE TABLE IF NOT EXISTS DimDate (
    date_key INT PRIMARY KEY, -- Integer format: YYYYMMDD
    full_date DATE NOT NULL UNIQUE,
    day_of_week INT NOT NULL,
    day_name VARCHAR(15) NOT NULL,
    month INT NOT NULL,
    month_name VARCHAR(15) NOT NULL,
    quarter INT NOT NULL,
    year INT NOT NULL,
    is_weekend BOOLEAN NOT NULL,
    is_ramadan_eid BOOLEAN NOT NULL DEFAULT FALSE
);

-- C. DimRestaurant
CREATE TABLE IF NOT EXISTS DimRestaurant (
    restaurant_key INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    restaurant_id INT NOT NULL,
    name VARCHAR(100) NOT NULL,
    cuisine_type VARCHAR(50) NOT NULL,
    city_name VARCHAR(50) NOT NULL,
    rating_tier VARCHAR(20) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- D. DimCustomer
CREATE TABLE IF NOT EXISTS DimCustomer (
    customer_key INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id INT NOT NULL,
    name VARCHAR(100) NOT NULL,
    signup_date DATE NOT NULL,
    city_name VARCHAR(50) NOT NULL,
    spending_tier VARCHAR(20) NOT NULL
);


-- ----------------------------------------------------------------------------
-- 2. CENTRAL FACT TABLE: FactOrders
-- Grain: One record per individual completed order line transaction.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS FactOrders (
    order_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    date_key INT NOT NULL REFERENCES DimDate(date_key),
    city_key INT NOT NULL REFERENCES DimCity(city_key),
    restaurant_key INT NOT NULL REFERENCES DimRestaurant(restaurant_key),
    customer_key INT NOT NULL REFERENCES DimCustomer(customer_key),
    rider_key INT,
    
    -- Degenerate dimension (OLTP source pointer)
    order_id INT NOT NULL,
    
    -- Additive numerical measures
    order_amount NUMERIC(10, 2) NOT NULL,
    discount_amount NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    delivery_fee NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    tip_amount NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    delivery_time_minutes NUMERIC(6, 2),
    is_delivered BOOLEAN NOT NULL DEFAULT TRUE,
    is_cancelled BOOLEAN NOT NULL DEFAULT FALSE
);

-- Foreign key indexes for star join acceleration
CREATE INDEX IF NOT EXISTS idx_fact_date ON FactOrders(date_key);
CREATE INDEX IF NOT EXISTS idx_fact_city ON FactOrders(city_key);
CREATE INDEX IF NOT EXISTS idx_fact_restaurant ON FactOrders(restaurant_key);
CREATE INDEX IF NOT EXISTS idx_fact_customer ON FactOrders(customer_key);


-- ----------------------------------------------------------------------------
-- 3. EXECUTIVE ANALYTICAL DASHBOARD QUERY
-- Query: "Orders per city per month for the last 2 years"
-- Target Latency: < 45 ms on 36M rows
-- ----------------------------------------------------------------------------
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
GROUP BY 
    c.city_name, 
    d.year, 
    d.month, 
    d.month_name
ORDER BY 
    c.city_name, 
    d.year DESC, 
    d.month DESC;
