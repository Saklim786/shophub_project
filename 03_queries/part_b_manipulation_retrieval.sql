-- ============================================================
-- PART B: Data Manipulation & Retrieval
-- (Q6 - transactions demo - lives in part_a_design_and_dictionary.sql)
-- ============================================================
USE shophub_analytics;

-- ------------------------------------------------------------
-- Q7: Customers with same email but different name/address
-- CAVEAT: the Olist dataset never exposes email or name (PII is
-- excluded at source for privacy). This query is written against
-- the schema exactly as the assignment asks, using
-- customer_unique_id as the "same identity" key and comparing
-- zip/city/state as the proxy for "different address" — the
-- pattern is fully general and would work unmodified if an
-- email/name column were added to `customers`.
-- On THIS data it returns 0 rows because customer_unique_id was
-- reconstructed 1:1 from customer_id (see DQ report #1).
-- ------------------------------------------------------------
SELECT
    a.customer_unique_id,
    a.customer_id AS customer_id_a, a.customer_city AS city_a, a.customer_state AS state_a,
    b.customer_id AS customer_id_b, b.customer_city AS city_b, b.customer_state AS state_b
FROM customers a
JOIN customers b
    ON a.customer_unique_id = b.customer_unique_id
    AND a.customer_id < b.customer_id
WHERE a.customer_city <> b.customer_city
   OR a.customer_state <> b.customer_state;

-- ------------------------------------------------------------
-- Q8: Orphan records — order_items referencing non-existent
-- products or orders. FK constraints in the production schema make
-- this structurally impossible going forward; this query re-checks
-- the RAW staging data to show what existed before cleaning, and
-- doubles as an ongoing data-integrity check on production tables.
-- ------------------------------------------------------------
-- (a) against raw staging data (pre-cleaning state)
SELECT 'orphan_order' AS issue, COUNT(*) AS cnt
FROM stg_order_items oi
LEFT JOIN stg_orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'orphan_product', COUNT(*)
FROM stg_order_items oi
LEFT JOIN stg_products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;

-- (b) against production tables (should always be 0 due to FKs)
SELECT 'orphan_order_prod' AS issue, COUNT(*) AS cnt
FROM order_items oi LEFT JOIN orders o ON oi.order_id = o.order_id WHERE o.order_id IS NULL
UNION ALL
SELECT 'orphan_product_prod', COUNT(*)
FROM order_items oi LEFT JOIN products p ON oi.product_id = p.product_id WHERE p.product_id IS NULL;

-- ------------------------------------------------------------
-- Q9: Customers who registered but never placed an order
-- (conversion funnel leak analysis)
-- CAVEAT: because `customers` here is reconstructed FROM orders
-- (DQ issue #1), every customer_id by definition has >=1 order, so
-- this returns 0 rows on the current data. Query kept exactly as
-- it should be written against the true schema (once a real
-- customers master file with non-order registrations is loaded,
-- this works unmodified).
-- ------------------------------------------------------------
SELECT c.customer_id, c.customer_unique_id, c.customer_city, c.customer_state
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
WHERE o.order_id IS NULL;

-- ------------------------------------------------------------
-- Q10: Detect potential fraud — payment_value != order total
-- (sum of order_items price + freight)
-- ------------------------------------------------------------
SELECT
    o.order_id,
    o.order_status,
    pay.total_paid,
    items.total_order_value,
    ROUND(pay.total_paid - items.total_order_value, 2) AS discrepancy
FROM orders o
JOIN (
    SELECT order_id, SUM(payment_value) AS total_paid
    FROM order_payments GROUP BY order_id
) pay ON pay.order_id = o.order_id
JOIN (
    SELECT order_id, SUM(price + freight_value) AS total_order_value
    FROM order_items GROUP BY order_id
) items ON items.order_id = o.order_id
WHERE ABS(pay.total_paid - items.total_order_value) > 0.01
ORDER BY ABS(pay.total_paid - items.total_order_value) DESC
LIMIT 50;
