-- ============================================================
-- PART D: Mastering Joins
-- ============================================================
USE shophub_analytics;

-- ------------------------------------------------------------
-- Q16: Customer 360-degree view joining 5+ tables
-- (customers, orders, order_items, products, reviews)
-- ------------------------------------------------------------
SELECT
    c.customer_id,
    c.customer_state,
    o.order_id,
    o.order_status,
    o.order_purchase_timestamp,
    p.product_id,
    pc.category_name,
    oi.price,
    oi.freight_value,
    r.review_score,
    r.review_comment_message
FROM customers c
JOIN orders o        ON o.customer_id = c.customer_id
JOIN order_items oi   ON oi.order_id = o.order_id
JOIN products p        ON p.product_id = oi.product_id
LEFT JOIN product_category pc ON pc.category_id = p.category_id
LEFT JOIN order_reviews r      ON r.order_id = o.order_id
ORDER BY o.order_purchase_timestamp DESC
LIMIT 100;

-- ------------------------------------------------------------
-- Q17: Customers who bought from 'electronics' but never from
-- 'books'-equivalent category.
-- NOTE: Olist's real category taxonomy does not include an
-- exact "electronics" or "books" category name; the closest
-- equivalents are 'eletronicos' and 'livros_interesse_geral'
-- (+ 'livros_tecnicos', 'livros_importados'). Used here so the
-- query returns meaningful results against this dataset.
-- ------------------------------------------------------------
SELECT DISTINCT c.customer_id
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
JOIN products p ON p.product_id = oi.product_id
JOIN product_category pc ON pc.category_id = p.category_id
WHERE pc.category_name = 'eletronicos'
AND c.customer_id NOT IN (
    SELECT c2.customer_id
    FROM customers c2
    JOIN orders o2 ON o2.customer_id = c2.customer_id
    JOIN order_items oi2 ON oi2.order_id = o2.order_id
    JOIN products p2 ON p2.product_id = oi2.product_id
    JOIN product_category pc2 ON pc2.category_id = p2.category_id
    WHERE pc2.category_name IN ('livros_interesse_geral','livros_tecnicos','livros_importados')
);

-- ------------------------------------------------------------
-- Q18: Sellers and their best-selling product in each category
-- they sell (by revenue)
-- ------------------------------------------------------------
WITH seller_category_product_revenue AS (
    SELECT
        s.seller_id,
        pc.category_name,
        p.product_id,
        SUM(oi.price) AS revenue,
        ROW_NUMBER() OVER (
            PARTITION BY s.seller_id, pc.category_name
            ORDER BY SUM(oi.price) DESC
        ) AS rn
    FROM sellers s
    JOIN order_items oi ON oi.seller_id = s.seller_id
    JOIN products p ON p.product_id = oi.product_id
    JOIN product_category pc ON pc.category_id = p.category_id
    GROUP BY s.seller_id, pc.category_name, p.product_id
)
SELECT seller_id, category_name, product_id, revenue
FROM seller_category_product_revenue
WHERE rn = 1
ORDER BY seller_id, category_name;

-- ------------------------------------------------------------
-- Q19: Products frequently bought together (market basket
-- analysis via self-join on order_items)
-- ------------------------------------------------------------
SELECT
    a.product_id AS product_a,
    b.product_id AS product_b,
    COUNT(DISTINCT a.order_id) AS times_bought_together
FROM order_items a
JOIN order_items b
    ON a.order_id = b.order_id
    AND a.product_id < b.product_id   -- avoid duplicate pairs / self-pairing
GROUP BY a.product_id, b.product_id
HAVING COUNT(DISTINCT a.order_id) >= 2
ORDER BY times_bought_together DESC
LIMIT 50;

-- ------------------------------------------------------------
-- Q20: Orders with shipping delays
-- (actual delivery later than the estimated delivery date)
-- ------------------------------------------------------------
SELECT
    o.order_id,
    c.customer_id, c.customer_state,
    s.seller_id, s.seller_state,
    o.order_estimated_delivery_date,
    o.order_delivered_customer_date,
    DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) AS days_late
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
JOIN sellers s ON s.seller_id = oi.seller_id
WHERE o.order_delivered_customer_date IS NOT NULL
  AND o.order_delivered_customer_date > o.order_estimated_delivery_date
GROUP BY o.order_id, c.customer_id, c.customer_state, s.seller_id, s.seller_state,
         o.order_estimated_delivery_date, o.order_delivered_customer_date
ORDER BY days_late DESC
LIMIT 50;
