-- ============================================================================
-- PROJECT: "You Hungry" Multi-City Food Delivery Platform
-- FILE: sql/05_transactions_concurrency.sql
-- DIALECT: PostgreSQL 15+ / ANSI SQL Compliant
-- DESCRIPTION: Concurrency control & row-level pessimistic locking patterns.
-- ============================================================================

-- ============================================================================
-- PATTERN 1: Raw Atomic Transaction Block (Application / ORM Tier)
-- Demonstrates row locking via SELECT ... FOR UPDATE under READ COMMITTED.
-- ============================================================================

BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;

    -- Step 1: Acquire exclusive row lock on target order
    SELECT 
        order_id,
        restaurant_id,
        rider_id,
        status,
        total_amount
    FROM Orders
    WHERE order_id = 50421
    FOR UPDATE;

    -- Step 2: Conditionally mutate order state only if currently 'ready'
    UPDATE Orders
    SET 
        rider_id = 104,
        status = 'picked_up',
        updated_at = CURRENT_TIMESTAMP
    WHERE order_id = 50421
      AND status = 'ready';

    -- Step 3: Insert state change into audit log
    INSERT INTO OrderStatusLog (order_id, old_status, new_status, changed_by)
    VALUES (50421, 'ready', 'picked_up', 'Rider_Dispatch_Service');

COMMIT;


-- ============================================================================
-- PATTERN 2: Production Stored Procedure (Engine Dispatch)
-- Encapsulates atomic rider assignment with timeouts and exception handling.
-- ============================================================================

CREATE OR REPLACE PROCEDURE AssignRiderToOrder(
    IN p_order_id INT,
    IN p_rider_id INT,
    OUT p_success BOOLEAN,
    OUT p_message VARCHAR(255)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_status VARCHAR(30);
    v_current_rider INT;
BEGIN
    SET LOCAL lock_timeout = '3s';

    -- Acquire row lock
    SELECT status, rider_id 
    INTO v_current_status, v_current_rider
    FROM Orders
    WHERE order_id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        p_success := FALSE;
        p_message := FORMAT('Order ID %s does not exist.', p_order_id);
        RETURN;
    END IF;

    IF v_current_status != 'ready' THEN
        p_success := FALSE;
        p_message := FORMAT('Order ID %s is not available for pickup (Status: %s, Rider: %s).', 
                            p_order_id, v_current_status, COALESCE(v_current_rider::TEXT, 'None'));
        RETURN;
    END IF;

    UPDATE Orders
    SET 
        rider_id = p_rider_id,
        status = 'picked_up',
        updated_at = CURRENT_TIMESTAMP
    WHERE order_id = p_order_id;

    INSERT INTO OrderStatusLog (
        order_id,
        old_status,
        new_status,
        changed_by
    ) VALUES (
        p_order_id,
        'ready',
        'picked_up',
        FORMAT('Rider_ID_%s', p_rider_id)
    );

    p_success := TRUE;
    p_message := FORMAT('Order ID %s successfully assigned to Rider ID %s.', p_order_id, p_rider_id);

EXCEPTION
    WHEN lock_not_available THEN
        p_success := FALSE;
        p_message := 'Order is currently locked by another concurrent dispatch transaction. Please retry.';
    WHEN OTHERS THEN
        p_success := FALSE;
        p_message := FORMAT('Internal dispatch error: %s', SQLERRM);
END;
$$;
