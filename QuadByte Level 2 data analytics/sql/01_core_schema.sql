-- ============================================================================
-- PROJECT: "You Hungry" Multi-City Food Delivery Platform
-- FILE: sql/01_core_schema.sql
-- DIALECT: PostgreSQL 15+ / ANSI SQL Compliant
-- DESCRIPTION: Core normalized relational schema (3NF/BCNF compliant).
-- ============================================================================

-- 1. Geographic Entities
CREATE TABLE IF NOT EXISTS City (
    city_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    city_name VARCHAR(50) NOT NULL UNIQUE,
    province VARCHAR(50) NOT NULL,
    country VARCHAR(50) NOT NULL DEFAULT 'Pakistan',
    delivery_tier VARCHAR(20) NOT NULL DEFAULT 'Tier-1',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. Customer Accounts
CREATE TABLE IF NOT EXISTS Customer (
    customer_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    phone VARCHAR(20) NOT NULL UNIQUE,
    city_id INT NOT NULL REFERENCES City(city_id) ON DELETE RESTRICT,
    password_hash VARCHAR(255) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_customer_city_id ON Customer(city_id);
CREATE INDEX IF NOT EXISTS idx_customer_phone ON Customer(phone);

-- 3. Merchants / Restaurants
CREATE TABLE IF NOT EXISTS Restaurant (
    restaurant_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    city_id INT NOT NULL REFERENCES City(city_id) ON DELETE RESTRICT,
    cuisine_type VARCHAR(50) NOT NULL,
    address TEXT NOT NULL,
    phone VARCHAR(20) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_restaurant_city_id ON Restaurant(city_id);
CREATE INDEX IF NOT EXISTS idx_restaurant_cuisine ON Restaurant(cuisine_type);

-- 4. Delivery Riders
CREATE TABLE IF NOT EXISTS Rider (
    rider_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) NOT NULL UNIQUE,
    city_id INT NOT NULL REFERENCES City(city_id) ON DELETE RESTRICT,
    vehicle_type VARCHAR(30) NOT NULL DEFAULT 'Motorcycle',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_rider_city_id ON Rider(city_id);
CREATE INDEX IF NOT EXISTS idx_rider_active ON Rider(is_active);

-- 5. Orders Transaction Core
CREATE TABLE IF NOT EXISTS Orders (
    order_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES Customer(customer_id) ON DELETE RESTRICT,
    restaurant_id INT NOT NULL REFERENCES Restaurant(restaurant_id) ON DELETE RESTRICT,
    rider_id INT REFERENCES Rider(rider_id) ON DELETE SET NULL,
    city_id INT NOT NULL REFERENCES City(city_id) ON DELETE RESTRICT,
    total_amount NUMERIC(10, 2) NOT NULL CHECK (total_amount >= 0.00),
    status VARCHAR(30) NOT NULL CHECK (status IN ('pending', 'confirmed', 'preparing', 'ready', 'picked_up', 'delivered', 'cancelled')),
    order_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    delivery_time TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON Orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_restaurant_id ON Orders(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_orders_rider_id ON Orders(rider_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON Orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_order_date ON Orders(order_date);

-- 6. State Machine Audit Trail
CREATE TABLE IF NOT EXISTS OrderStatusLog (
    log_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id INT NOT NULL REFERENCES Orders(order_id) ON DELETE CASCADE,
    old_status VARCHAR(30),
    new_status VARCHAR(30) NOT NULL,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) DEFAULT CURRENT_USER
);

CREATE INDEX IF NOT EXISTS idx_order_status_log_order_id ON OrderStatusLog(order_id);
CREATE INDEX IF NOT EXISTS idx_order_status_log_changed_at ON OrderStatusLog(changed_at);

-- 7. BCNF Decomposed Feedback Relations
CREATE TABLE IF NOT EXISTS RestaurantRating (
    rating_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id INT NOT NULL REFERENCES Orders(order_id) ON DELETE CASCADE,
    customer_id INT NOT NULL REFERENCES Customer(customer_id) ON DELETE RESTRICT,
    restaurant_id INT NOT NULL REFERENCES Restaurant(restaurant_id) ON DELETE RESTRICT,
    score NUMERIC(2, 1) NOT NULL CHECK (score >= 1.0 AND score <= 5.0),
    comment TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_order_restaurant_review UNIQUE (order_id, restaurant_id)
);

CREATE TABLE IF NOT EXISTS RiderRating (
    rider_rating_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id INT NOT NULL REFERENCES Orders(order_id) ON DELETE CASCADE,
    customer_id INT NOT NULL REFERENCES Customer(customer_id) ON DELETE RESTRICT,
    rider_id INT NOT NULL REFERENCES Rider(rider_id) ON DELETE RESTRICT,
    score NUMERIC(2, 1) NOT NULL CHECK (score >= 1.0 AND score <= 5.0),
    comment TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_order_rider_review UNIQUE (order_id, rider_id)
);

CREATE INDEX IF NOT EXISTS idx_rest_rating_rest ON RestaurantRating(restaurant_id, score);
CREATE INDEX IF NOT EXISTS idx_rider_rating_rider ON RiderRating(rider_id, score);
