-- ============================================================================
-- PROJECT: "You Hungry" Multi-City Food Delivery Platform
-- FILE: sql/04_stored_procedures_triggers.sql
-- DIALECT: PostgreSQL 15+ / ANSI SQL Compliant
-- DESCRIPTION: State machine automation, immutable audit logging & delivery triggers.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Task 4a: Stored Procedure UpdateOrderStatus(order_id, new_status)
-- Features:
-- 1. Input parameter validation.
-- 2. Row locking via SELECT ... FOR UPDATE.
-- 3. Exception raising (ERRCODE = 'P0002') if order does not exist.
-- 4. Idempotency guard for identical state transitions.
-- 5. Atomic state update and immutable audit insertion into OrderStatusLog.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE UpdateOrderStatus(
    IN p_order_id INT,
    IN p_new_status VARCHAR(30)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_old_status VARCHAR(30);
BEGIN
    -- 1. Input parameter validation
    IF p_order_id IS NULL THEN
        RAISE EXCEPTION 'ORDER_ID_INVALID: Parameter p_order_id cannot be NULL.'
            USING ERRCODE = '22023';
    END IF;

    IF p_new_status IS NULL OR TRIM(p_new_status) = '' THEN
        RAISE EXCEPTION 'NEW_STATUS_INVALID: Parameter p_new_status cannot be empty.'
            USING ERRCODE = '22023';
    END IF;

    -- 2. Acquire pessimistic row lock and retrieve existing status
    SELECT status INTO v_old_status
    FROM Orders
    WHERE order_id = p_order_id
    FOR UPDATE;

    -- 3. Check existence
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ORDER_NOT_FOUND: Order ID % does not exist in the platform database.', p_order_id
            USING ERRCODE = 'P0002';
    END IF;

    -- 4. Idempotency check
    IF v_old_status = p_new_status THEN
        RAISE NOTICE 'Order ID % is already in status "%". No state mutation applied.', p_order_id, p_new_status;
        RETURN;
    END IF;

    -- 5. Mutate state
    UPDATE Orders
    SET status = p_new_status,
        updated_at = CURRENT_TIMESTAMP
    WHERE order_id = p_order_id;

    -- 6. Insert audit trail entry
    INSERT INTO OrderStatusLog (
        order_id,
        old_status,
        new_status,
        changed_at,
        changed_by
    ) VALUES (
        p_order_id,
        v_old_status,
        p_new_status,
        CURRENT_TIMESTAMP,
        CURRENT_USER
    );

END;
$$;


-- ----------------------------------------------------------------------------
-- Task 4b: Trigger trg_SetDeliveryTime
-- Purpose: Automatically stamps delivery_time = CURRENT_TIMESTAMP upon transition to 'delivered'.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_SetDeliveryTime()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status != 'delivered') THEN
        NEW.delivery_time := CURRENT_TIMESTAMP;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_SetDeliveryTime ON Orders;

CREATE TRIGGER trg_SetDeliveryTime
BEFORE UPDATE OF status ON Orders
FOR EACH ROW
EXECUTE FUNCTION fn_SetDeliveryTime();
