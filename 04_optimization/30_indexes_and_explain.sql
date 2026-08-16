-- ============================================================
-- Q30: Identify 3 slowest queries, optimize with indexes,
-- show before/after execution time (EXPLAIN ANALYZE)
-- ============================================================
USE shophub_analytics;

-- Baseline timings captured BEFORE these indexes were added
-- (see reports/optimization_report.md for the full before/after
-- EXPLAIN ANALYZE plans):
--   Query 1 (Q19 market basket self-join):        ~714 ms
--   Query 2 (Q17 category-exclusion antijoin):    ~1691 ms
--   Query 3 (Q12 top-N products per category):    ~1692 ms

-- ------------------------------------------------------------
-- New indexes (B-tree, MySQL/InnoDB default)
-- ------------------------------------------------------------

-- 1. Covering composite index for product-level revenue aggregation
--    (used heavily by Q12, Q13, Q18, Q22 which all GROUP BY
--    product_id and SUM(price)). Lets the optimizer satisfy the
--    join+aggregate entirely from the index without a row lookup.
CREATE INDEX idx_items_product_price ON order_items(product_id, price);

-- 2. Composite index on (order_id, product_id) for order_items.
--    The existing PRIMARY KEY is (order_id, order_item_id), so a
--    lookup that needs to match on order_id THEN filter/compare on
--    product_id (Q17's antijoin, Q19's self-join) still needs a row
--    lookup for product_id. This composite makes both parts
--    index-only.
CREATE INDEX idx_items_order_product ON order_items(order_id, product_id);

-- 3. Composite index on orders(customer_id, order_purchase_timestamp)
--    for the per-customer LAG()/window-function queries (Q24, Q26)
--    and the correlated per-state aggregates (Q21) - avoids a sort
--    step per customer partition.
CREATE INDEX idx_orders_customer_purchase ON orders(customer_id, order_purchase_timestamp);

-- ------------------------------------------------------------
-- Re-run the same 3 queries AFTER indexing
-- ------------------------------------------------------------

-- Query 1: Market basket self-join (Q19)
EXPLAIN ANALYZE
SELECT a.product_id, b.product_id, COUNT(DISTINCT a.order_id) c
FROM order_items a
JOIN order_items b ON a.order_id = b.order_id AND a.product_id < b.product_id
GROUP BY a.product_id, b.product_id
HAVING c >= 2
ORDER BY c DESC LIMIT 50;

-- Query 2: Category exclusion antijoin (Q17)
EXPLAIN ANALYZE
SELECT DISTINCT c.customer_id
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
JOIN products p ON p.product_id = oi.product_id
JOIN product_category pc ON pc.category_id = p.category_id
WHERE pc.category_name = 'eletronicos'
AND c.customer_id NOT IN (
    SELECT c2.customer_id FROM customers c2
    JOIN orders o2 ON o2.customer_id = c2.customer_id
    JOIN order_items oi2 ON oi2.order_id = o2.order_id
    JOIN products p2 ON p2.product_id = oi2.product_id
    JOIN product_category pc2 ON pc2.category_id = p2.category_id
    WHERE pc2.category_name IN ('livros_interesse_geral','livros_tecnicos','livros_importados')
);

-- Query 3: Top-10 products per category (Q12)
EXPLAIN ANALYZE
WITH product_revenue AS (
    SELECT pc.category_name, p.product_id, SUM(oi.price) AS product_revenue
    FROM order_items oi
    JOIN products p ON p.product_id = oi.product_id
    JOIN product_category pc ON pc.category_id = p.category_id
    GROUP BY pc.category_name, p.product_id
),
ranked AS (
    SELECT category_name, product_id, product_revenue,
        DENSE_RANK() OVER (PARTITION BY category_name ORDER BY product_revenue DESC) AS rnk
    FROM product_revenue
)
SELECT * FROM ranked WHERE rnk <= 10 ORDER BY category_name, rnk;

-- ------------------------------------------------------------
-- Index inventory (Hash indexes are InnoDB-internal adaptive hash
-- only, not user-creatable in MySQL/InnoDB - noted in optimization
-- report; all user indexes here are B-tree, the correct structure
-- for range scans, ORDER BY, and the equality+range lookups used
-- throughout this workload).
-- ------------------------------------------------------------
SELECT TABLE_NAME, INDEX_NAME, COLUMN_NAME, SEQ_IN_INDEX
FROM INFORMATION_SCHEMA.STATISTICS
WHERE TABLE_SCHEMA = 'shophub_analytics'
  AND TABLE_NAME NOT LIKE 'stg_%'
ORDER BY TABLE_NAME, INDEX_NAME, SEQ_IN_INDEX;
