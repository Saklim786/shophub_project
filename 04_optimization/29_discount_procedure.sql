-- ============================================================
-- PART G: Stored Procedures & Optimization
-- Q29: Dynamic discount stored procedure
-- ============================================================
USE shophub_analytics;

DROP PROCEDURE IF EXISTS calculate_order_discount;

DELIMITER $$

CREATE PROCEDURE calculate_order_discount(
    IN  p_customer_id   CHAR(32),
    IN  p_order_value    DECIMAL(10,2),
    IN  p_as_of_order_id  CHAR(32),   -- the order being discounted; excluded from history count
    OUT p_discount_pct     DECIMAL(5,2),
    OUT p_discount_amount   DECIMAL(10,2),
    OUT p_final_amount       DECIMAL(10,2),
    OUT p_discount_reason      VARCHAR(50)
)
BEGIN
    DECLARE v_prior_order_count INT DEFAULT 0;
    DECLARE v_is_new_customer   BOOLEAN DEFAULT FALSE;

    -- Count this customer's orders placed BEFORE the order under evaluation
    -- (orders strictly before p_as_of_order_id's purchase timestamp; if the
    -- order doesn't exist yet, count ALL of the customer's existing orders).
    SELECT COUNT(*) INTO v_prior_order_count
    FROM orders o
    WHERE o.customer_id = p_customer_id
      AND o.order_id <> p_as_of_order_id
      AND (
            o.order_purchase_timestamp < (
                SELECT order_purchase_timestamp FROM orders WHERE order_id = p_as_of_order_id
            )
            OR NOT EXISTS (SELECT 1 FROM orders WHERE order_id = p_as_of_order_id)
          );

    SET v_is_new_customer = (v_prior_order_count = 0);

    -- Apply ONE discount rule only, in priority order:
    -- 1) New customer (first order): 15%
    -- 2) Order value > $500: 10%
    -- 3) Loyal customer (5+ previous orders): 5%
    IF v_is_new_customer THEN
        SET p_discount_pct = 15.00;
        SET p_discount_reason = 'NEW_CUSTOMER';
    ELSEIF p_order_value > 500 THEN
        SET p_discount_pct = 10.00;
        SET p_discount_reason = 'HIGH_VALUE_ORDER';
    ELSEIF v_prior_order_count >= 5 THEN
        SET p_discount_pct = 5.00;
        SET p_discount_reason = 'LOYAL_CUSTOMER';
    ELSE
        SET p_discount_pct = 0.00;
        SET p_discount_reason = 'NO_DISCOUNT';
    END IF;

    SET p_discount_amount = ROUND(p_order_value * p_discount_pct / 100, 2);
    SET p_final_amount = p_order_value - p_discount_amount;
END$$

DELIMITER ;

-- ------------------------------------------------------------
-- Demo calls
-- ------------------------------------------------------------
-- Case 1: brand new customer (0 prior orders) -> expect 15%
SET @cust := (SELECT customer_id FROM customers LIMIT 1);
CALL calculate_order_discount(@cust, 200.00, 'NON_EXISTENT_ORDER_ID', @pct, @amt, @final, @reason);
SELECT @pct AS discount_pct, @amt AS discount_amount, @final AS final_amount, @reason AS reason;

-- Case 2: high-value order ($750), existing customer -> expect 10%
-- (uses a real customer+order pair so "prior order count" logic runs against real history)
SET @ord := (SELECT order_id FROM orders LIMIT 1);
SET @cust2 := (SELECT customer_id FROM orders WHERE order_id = @ord);
CALL calculate_order_discount(@cust2, 750.00, @ord, @pct2, @amt2, @final2, @reason2);
SELECT @pct2 AS discount_pct, @amt2 AS discount_amount, @final2 AS final_amount, @reason2 AS reason;

-- Case 3: order value under $500, not new, not loyal -> expect 0%
CALL calculate_order_discount(@cust2, 120.00, @ord, @pct3, @amt3, @final3, @reason3);
SELECT @pct3 AS discount_pct, @amt3 AS discount_amount, @final3 AS final_amount, @reason3 AS reason;
