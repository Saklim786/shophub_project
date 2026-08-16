-- ============================================================
-- PART A: Database Design & Data Quality
-- Q1 (ERD)  -> see ERD/erd_diagram.md (also rendered as image)
-- Q2 (10+ DQ issues) -> see reports/data_quality_report.md
-- Q3 (CREATE TABLE w/ types, PK/FK, constraints) -> 01_schema/schema.sql
-- Q4 (dedup customers keeping most recent) -> 02_data_cleaning/02_clean_transform.sql
-- Q5 (data dictionary) -> see below
-- ============================================================
USE shophub_analytics;

-- ------------------------------------------------------------
-- Q5: Data dictionary — generated directly from INFORMATION_SCHEMA
-- so it always reflects the live schema (also exported as
-- reports/data_dictionary.csv for the written deliverable).
-- ------------------------------------------------------------
SELECT
    c.TABLE_NAME,
    c.COLUMN_NAME,
    c.COLUMN_TYPE,
    c.IS_NULLABLE,
    c.COLUMN_KEY,
    c.COLUMN_DEFAULT,
    CASE c.TABLE_NAME
        WHEN 'customers' THEN 'Customer identity used on an order (see DQ report #1 for unique_id caveat)'
        WHEN 'sellers' THEN 'Marketplace seller who fulfills order_items'
        WHEN 'product_category' THEN 'Normalized product category lookup (3NF)'
        WHEN 'products' THEN 'Product catalog with physical dimensions for freight calc'
        WHEN 'orders' THEN 'One row per customer order, with full delivery lifecycle timestamps'
        WHEN 'order_items' THEN 'Line items within an order; one row per product/seller combo'
        WHEN 'order_payments' THEN 'One or more payment transactions applied to an order'
        WHEN 'order_reviews' THEN 'Customer review/rating left for a delivered order'
        WHEN 'geolocation' THEN 'Zip-prefix level lat/lng samples for Brazil (corrected sign, see DQ report #3)'
    END AS business_meaning
FROM INFORMATION_SCHEMA.COLUMNS c
WHERE c.TABLE_SCHEMA = 'shophub_analytics'
  AND c.TABLE_NAME NOT LIKE 'stg_%'
ORDER BY c.TABLE_NAME, c.ORDINAL_POSITION;

-- ------------------------------------------------------------
-- Q6 (Part B): Transactions — COMMIT / ROLLBACK demo
-- Simulates inserting a new cleaned order with a deliberate error
-- scenario (FK violation on a bad product_id) to show ROLLBACK,
-- then a successful insert to show COMMIT.
-- ------------------------------------------------------------

-- Scenario 1: FAILURE -> ROLLBACK (bad seller_id that doesn't exist)
START TRANSACTION;
INSERT INTO orders (order_id, customer_id, order_status, order_purchase_timestamp, order_estimated_delivery_date)
VALUES ('demo_txn_order_001', (SELECT customer_id FROM customers LIMIT 1), 'created', NOW(), NOW());

-- This next insert intentionally references a seller_id that does not exist.
-- In a real error-handling wrapper (procedure), the app catches the FK error,
-- and issues ROLLBACK. Demonstrated here explicitly:
-- INSERT INTO order_items (order_id, order_item_id, product_id, seller_id, price, freight_value)
-- VALUES ('demo_txn_order_001', 1, (SELECT product_id FROM products LIMIT 1), 'NONEXISTENT_SELLER_ID', 10, 1);
-- => would raise error 1452 (foreign key constraint fails)
ROLLBACK;

SELECT COUNT(*) AS should_be_zero FROM orders WHERE order_id = 'demo_txn_order_001';

-- Scenario 2: SUCCESS -> COMMIT
START TRANSACTION;
INSERT INTO orders (order_id, customer_id, order_status, order_purchase_timestamp, order_estimated_delivery_date)
VALUES ('demo_txn_order_002', (SELECT customer_id FROM customers LIMIT 1), 'created', NOW(), NOW());
INSERT INTO order_items (order_id, order_item_id, product_id, seller_id, price, freight_value)
VALUES ('demo_txn_order_002', 1, (SELECT product_id FROM products LIMIT 1), (SELECT seller_id FROM sellers LIMIT 1), 99.90, 12.50);
COMMIT;

SELECT COUNT(*) AS should_be_one FROM orders WHERE order_id = 'demo_txn_order_002';

-- cleanup demo rows so they don't pollute analytics queries below
DELETE FROM order_items WHERE order_id = 'demo_txn_order_002';
DELETE FROM orders WHERE order_id = 'demo_txn_order_002';
