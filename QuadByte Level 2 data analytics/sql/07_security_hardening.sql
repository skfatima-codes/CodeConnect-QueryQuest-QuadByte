-- ============================================================================
-- PROJECT: "You Hungry" Multi-City Food Delivery Platform
-- FILE: sql/07_security_hardening.sql
-- DIALECT: PostgreSQL 15+ / ANSI SQL Compliant
-- DESCRIPTION: Prepared statements, RBAC matrix, and Row-Level Security (RLS).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. SQL INJECTION IMMUNITY: SERVER-SIDE PREPARED STATEMENTS
-- Parameterized compiled queries treat user arguments strictly as data literals.
-- ----------------------------------------------------------------------------

-- Deallocate if previously prepared in session
DEALLOCATE PREPARE get_customer_by_name;

-- Precompiled execution plan
PREPARE get_customer_by_name(text) AS
SELECT 
    customer_id, 
    name, 
    email, 
    phone, 
    city_id, 
    created_at
FROM Customer
WHERE name = $1;

-- Execution invocation
EXECUTE get_customer_by_name('John Doe');


-- ----------------------------------------------------------------------------
-- 2. ROLE-BASED ACCESS CONTROL (RBAC) PRIVILEGE MATRIX
-- Implements principle of least privilege across backend tiers.
-- ----------------------------------------------------------------------------

-- Role definitions
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'analyst') THEN
        CREATE ROLE analyst WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'admin') THEN
        CREATE ROLE admin WITH LOGIN NOSUPERUSER CREATEDB CREATEROLE NOINHERIT;
    END IF;
END
$$;

-- Revoke default public schema permissions
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO app_user, analyst, admin;

-- A. Backend Microservice Role (app_user)
-- Can read/write live operational data; hard DELETE is explicitly prohibited.
GRANT SELECT, INSERT, UPDATE ON Customer, Restaurant, Rider, Orders, RestaurantRating, RiderRating, OrderStatusLog TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;

-- B. Business Intelligence & Reporting Role (analyst)
-- Read-only access strictly restricted to Views and reporting entities.
GRANT SELECT ON vw_DailyRevenue, vw_RestaurantRatings, vw_RiderPerformance TO analyst;
REVOKE ALL ON Customer, Payment, Orders FROM analyst;

-- C. Administration & DevOps Role (admin)
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO admin;


-- ----------------------------------------------------------------------------
-- 3. ROW-LEVEL SECURITY (RLS) POLICIES
-- Enforces tenant isolation so customers can only inspect their own records.
-- ----------------------------------------------------------------------------
ALTER TABLE Customer ENABLE ROW LEVEL SECURITY;
ALTER TABLE Orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS customer_isolation_policy ON Customer;
CREATE POLICY customer_isolation_policy ON Customer
    FOR ALL
    TO app_user
    USING (customer_id = NULLIF(current_setting('app.current_user_id', true), '')::INT);

DROP POLICY IF EXISTS orders_customer_policy ON Orders;
CREATE POLICY orders_customer_policy ON Orders
    FOR SELECT
    TO app_user
    USING (customer_id = NULLIF(current_setting('app.current_user_id', true), '')::INT);
