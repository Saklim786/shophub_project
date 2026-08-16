-- ============================================================
-- PART C: Complex Aggregations
-- ============================================================
USE shophub_analytics;

-- ------------------------------------------------------------
-- Q11: Monthly revenue with Month-over-Month (MoM) growth %
-- Revenue = SUM(order_items.price) for delivered orders, by the
-- month the order was purchased. First month has no prior month
-- to compare against -> MoM = NULL (edge case handled explicitly).
-- ------------------------------------------------------------
WITH monthly_revenue AS (
    SELECT
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS revenue_month,
        SUM(oi.price) AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status NOT IN ('canceled','unavailable')
    GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
)
SELECT
    revenue_month,
    revenue,
    LAG(revenue) OVER (ORDER BY revenue_month) AS prev_month_revenue,
    CASE
        WHEN LAG(revenue) OVER (ORDER BY revenue_month) IS NULL THEN NULL  -- first month edge case
        WHEN LAG(revenue) OVER (ORDER BY revenue_month) = 0 THEN NULL      -- avoid div/0
        ELSE ROUND(
            (revenue - LAG(revenue) OVER (ORDER BY revenue_month))
            / LAG(revenue) OVER (ORDER BY revenue_month) * 100, 2)
    END AS mom_growth_pct
FROM monthly_revenue
ORDER BY revenue_month;

-- ------------------------------------------------------------
-- Q12: Top 10 products by revenue in each category (DENSE_RANK)
-- ------------------------------------------------------------
WITH product_revenue AS (
    SELECT
        pc.category_name,
        p.product_id,
        SUM(oi.price) AS product_revenue
    FROM order_items oi
    JOIN products p ON p.product_id = oi.product_id
    JOIN product_category pc ON pc.category_id = p.category_id
    GROUP BY pc.category_name, p.product_id
),
ranked AS (
    SELECT
        category_name, product_id, product_revenue,
        DENSE_RANK() OVER (PARTITION BY category_name ORDER BY product_revenue DESC) AS rnk
    FROM product_revenue
)
SELECT category_name, product_id, product_revenue, rnk
FROM ranked
WHERE rnk <= 10
ORDER BY category_name, rnk;

-- ------------------------------------------------------------
-- Q13: Customer Lifetime Value (CLV) = SUM(payment_value) per
-- customer, bucketed Bronze / Silver / Gold
-- ------------------------------------------------------------
WITH clv AS (
    SELECT
        c.customer_id,
        c.customer_unique_id,
        SUM(op.payment_value) AS lifetime_value
    FROM customers c
    JOIN orders o ON o.customer_id = c.customer_id
    JOIN order_payments op ON op.order_id = o.order_id
    GROUP BY c.customer_id, c.customer_unique_id
)
SELECT
    customer_id,
    customer_unique_id,
    lifetime_value,
    CASE
        WHEN lifetime_value >= 1000 THEN 'Gold'
        WHEN lifetime_value >= 300  THEN 'Silver'
        ELSE 'Bronze'
    END AS clv_tier
FROM clv
ORDER BY lifetime_value DESC;

-- ------------------------------------------------------------
-- Q14: Sales report with daily / weekly / monthly subtotals
-- using ROLLUP
-- ------------------------------------------------------------
SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS sales_month,
    YEARWEEK(o.order_purchase_timestamp, 3)           AS sales_week,
    DATE(o.order_purchase_timestamp)                  AS sales_day,
    ROUND(SUM(oi.price), 2)                            AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_purchase_timestamp >= '2018-01-01' AND o.order_purchase_timestamp < '2018-02-01'
GROUP BY sales_month, sales_week, sales_day WITH ROLLUP
ORDER BY sales_month, sales_week, sales_day;

-- ------------------------------------------------------------
-- Q15: Seasonal patterns — which categories sell best in which
-- months (top category per month by revenue)
-- ------------------------------------------------------------
WITH monthly_category_revenue AS (
    SELECT
        MONTH(o.order_purchase_timestamp) AS order_month,
        pc.category_name,
        SUM(oi.price) AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN products p ON p.product_id = oi.product_id
    JOIN product_category pc ON pc.category_id = p.category_id
    GROUP BY MONTH(o.order_purchase_timestamp), pc.category_name
),
ranked_months AS (
    SELECT *,
        RANK() OVER (PARTITION BY order_month ORDER BY revenue DESC) AS rnk
    FROM monthly_category_revenue
)
SELECT order_month, category_name, revenue
FROM ranked_months
WHERE rnk = 1
ORDER BY order_month;
