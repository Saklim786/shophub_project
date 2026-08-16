-- ============================================================
-- 02_clean_transform.sql
-- Transform raw staging data -> cleaned, typed, normalized
-- production tables. Implements Assignment Part A/B requirements.
-- ============================================================
USE shophub_analytics;

SET SQL_MODE = 'STRICT_TRANS_TABLES,NO_ZERO_DATE';

-- ------------------------------------------------------------
-- (Q4) STEP 1: Build CUSTOMERS from distinct customer_id in orders.
-- NOTE: olist_customers_dataset.csv was not supplied in this run
-- (see Data Quality Report, Issue #1). We reconstruct the customer
-- master list from orders.customer_id, the only customer key
-- available end-to-end. customer_unique_id is set equal to
-- customer_id as a documented placeholder (Olist's real file maps
-- many customer_id -> one customer_unique_id for repeat buyers,
-- which cannot be recovered without the source file).
-- The de-dup pattern below is written generically so it will work
-- unmodified once/if the true customer_unique_id mapping is loaded.
-- ------------------------------------------------------------
INSERT INTO customers (customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state)
SELECT DISTINCT
    TRIM(customer_id),
    TRIM(customer_id)          AS customer_unique_id_placeholder,
    NULL, NULL, NULL
FROM stg_orders
WHERE customer_id IS NOT NULL AND TRIM(customer_id) <> '';

-- Q4: Detect & remove duplicate customers, keep most recent record.
-- (Generic pattern - operates on customer_unique_id; a duplicate here
--  means the SAME unique_id appears with conflicting attributes.)
-- Kept for demonstration; on this reconstructed data it returns 0 rows
-- because customer_unique_id == customer_id (1:1) as noted above.
DELETE c1 FROM customers c1
INNER JOIN customers c2
    ON c1.customer_unique_id = c2.customer_unique_id
    AND c1.customer_id < c2.customer_id;   -- keep the lexicographically-last / most-recent row

-- ------------------------------------------------------------
-- STEP 2: PRODUCT_CATEGORY + PRODUCTS
-- Clean: trim, lower-case, NULL/blank category -> 'unknown'
-- ------------------------------------------------------------
INSERT INTO product_category (category_name)
SELECT DISTINCT
    LOWER(TRIM(COALESCE(NULLIF(TRIM(product_category_name), ''), 'unknown')))
FROM stg_products;

INSERT INTO products (product_id, category_id, product_name_length, product_description_length,
                       product_photos_qty, product_weight_g, product_length_cm, product_height_cm, product_width_cm)
SELECT
    TRIM(p.product_id),
    pc.category_id,
    NULLIF(p.product_name_lenght,'')+0,
    NULLIF(p.product_description_lenght,'')+0,
    COALESCE(NULLIF(p.product_photos_qty,'')+0, 0),
    NULLIF(p.product_weight_g,'')+0,
    NULLIF(p.product_length_cm,'')+0,
    NULLIF(p.product_height_cm,'')+0,
    NULLIF(p.product_width_cm,'')+0
FROM stg_products p
JOIN product_category pc
    ON pc.category_name = LOWER(TRIM(COALESCE(NULLIF(TRIM(p.product_category_name), ''), 'unknown')))
WHERE p.product_id IS NOT NULL AND TRIM(p.product_id) <> '';

-- ------------------------------------------------------------
-- STEP 3: SELLERS
-- ------------------------------------------------------------
INSERT INTO sellers (seller_id, seller_zip_code_prefix, seller_city, seller_state)
SELECT DISTINCT
    TRIM(seller_id),
    NULLIF(TRIM(seller_zip_code_prefix), ''),
    NULLIF(TRIM(LOWER(seller_city)), ''),
    NULLIF(UPPER(TRIM(seller_state)), '')
FROM stg_sellers
WHERE seller_id IS NOT NULL AND TRIM(seller_id) <> '';

-- ------------------------------------------------------------
-- STEP 4: ORDERS
-- stg timestamps are 'YYYY-MM-DD HH:MM:SS' strings -> STR_TO_DATE
-- Only insert orders whose customer_id exists in customers (referential integrity)
-- ------------------------------------------------------------
INSERT INTO orders (order_id, customer_id, order_status, order_purchase_timestamp,
                     order_approved_at, order_delivered_carrier_date,
                     order_delivered_customer_date, order_estimated_delivery_date)
SELECT
    TRIM(o.order_id),
    TRIM(o.customer_id),
    LOWER(TRIM(o.order_status)),
    STR_TO_DATE(o.order_purchase_timestamp, '%Y-%m-%d %H:%i:%s'),
    STR_TO_DATE(NULLIF(o.order_approved_at,''), '%Y-%m-%d %H:%i:%s'),
    STR_TO_DATE(NULLIF(o.order_delivered_carrier_date,''), '%Y-%m-%d %H:%i:%s'),
    STR_TO_DATE(NULLIF(o.order_delivered_customer_date,''), '%Y-%m-%d %H:%i:%s'),
    STR_TO_DATE(o.order_estimated_delivery_date, '%Y-%m-%d %H:%i:%s')
FROM stg_orders o
JOIN customers c ON c.customer_id = TRIM(o.customer_id)
WHERE o.order_id IS NOT NULL AND TRIM(o.order_id) <> '';

-- ------------------------------------------------------------
-- STEP 5: ORDER_ITEMS
-- Only insert items whose order_id, product_id, seller_id all exist (drop orphans)
-- ------------------------------------------------------------
INSERT INTO order_items (order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value)
SELECT
    TRIM(oi.order_id), CAST(oi.order_item_id AS UNSIGNED), TRIM(oi.product_id), TRIM(oi.seller_id),
    STR_TO_DATE(oi.shipping_limit_date, '%Y-%m-%d %H:%i:%s'),
    CAST(oi.price AS DECIMAL(10,2)),
    CAST(oi.freight_value AS DECIMAL(10,2))
FROM stg_order_items oi
JOIN orders o ON o.order_id = TRIM(oi.order_id)
JOIN products p ON p.product_id = TRIM(oi.product_id)
JOIN sellers s ON s.seller_id = TRIM(oi.seller_id);

-- ------------------------------------------------------------
-- STEP 6: ORDER_PAYMENTS
-- ------------------------------------------------------------
INSERT INTO order_payments (order_id, payment_sequential, payment_type, payment_installments, payment_value)
SELECT
    TRIM(op.order_id), CAST(op.payment_sequential AS UNSIGNED),
    LOWER(TRIM(op.payment_type)), CAST(op.payment_installments AS UNSIGNED),
    CAST(op.payment_value AS DECIMAL(10,2))
FROM stg_order_payments op
JOIN orders o ON o.order_id = TRIM(op.order_id);

-- ------------------------------------------------------------
-- STEP 7: ORDER_REVIEWS
-- Date format here is DD-MM-YYYY HH:MM (different from orders!) -
-- documented Data Quality Issue #2 (format inconsistency across files).
-- ------------------------------------------------------------
INSERT INTO order_reviews (review_id, order_id, review_score, review_comment_title,
                            review_comment_message, review_creation_date, review_answer_timestamp)
SELECT
    TRIM(r.review_id), TRIM(r.order_id), CAST(r.review_score AS UNSIGNED),
    NULLIF(TRIM(r.review_comment_title), ''),
    NULLIF(TRIM(r.review_comment_message), ''),
    STR_TO_DATE(r.review_creation_date, '%d-%m-%Y %H:%i'),
    STR_TO_DATE(r.review_answer_timestamp, '%d-%m-%Y %H:%i')
FROM stg_order_reviews r
JOIN orders o ON o.order_id = TRIM(r.order_id)
WHERE r.review_score REGEXP '^[0-9]+$'
  AND CAST(r.review_score AS UNSIGNED) BETWEEN 1 AND 5;

-- ------------------------------------------------------------
-- STEP 8: GEOLOCATION
-- Data Quality Issue #7 (see report): 100% of rows in the supplied
-- geolocation file carry POSITIVE lat/lng (e.g. 23.54, 46.63 for a
-- row whose city/state are explicitly "sao paulo, SP"). True Sao
-- Paulo is at approx (-23.54, -46.63) - Southern & Western
-- hemisphere. Every geolocation_state value in the file is a valid
-- Brazilian UF code, confirming this is genuine Brazil data with a
-- sign-inversion bug upstream (not a different region / not random
-- garbage). We correct it deterministically by negating both lat
-- and lng, rather than dropping ~1M otherwise-usable rows.
-- ------------------------------------------------------------
INSERT INTO geolocation (geolocation_zip_code_prefix, geolocation_lat, geolocation_lng,
                          geolocation_city, geolocation_state)
SELECT
    TRIM(geolocation_zip_code_prefix),
    -ABS(CAST(geolocation_lat AS DECIMAL(10,6))),
    -ABS(CAST(geolocation_lng AS DECIMAL(10,6))),
    NULLIF(TRIM(LOWER(geolocation_city)), ''),
    NULLIF(UPPER(TRIM(geolocation_state)), '')
FROM stg_geolocation
WHERE geolocation_lat REGEXP '^-?[0-9]+\\.?[0-9]*$'
  AND geolocation_lng REGEXP '^-?[0-9]+\\.?[0-9]*$'
  AND CAST(geolocation_lat AS DECIMAL(10,6)) BETWEEN -90 AND 90
  AND CAST(geolocation_lng AS DECIMAL(10,6)) BETWEEN -180 AND 180;

-- ------------------------------------------------------------
-- Row-count summary
-- ------------------------------------------------------------
SELECT 'customers' AS tbl, COUNT(*) AS rows_loaded FROM customers
UNION ALL SELECT 'product_category', COUNT(*) FROM product_category
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews
UNION ALL SELECT 'geolocation', COUNT(*) FROM geolocation;
