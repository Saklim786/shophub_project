-- ============================================================
-- PART F: Advanced Window Functions
-- ============================================================
USE shophub_analytics;

-- ------------------------------------------------------------
-- Q25: 7-day moving average of daily order count
-- ------------------------------------------------------------
WITH daily_orders AS (
    SELECT DATE(order_purchase_timestamp) AS order_date, COUNT(*) AS order_count
    FROM orders
    GROUP BY DATE(order_purchase_timestamp)
)
SELECT
    order_date,
    order_count,
    ROUND(AVG(order_count) OVER (
        ORDER BY order_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS moving_avg_7day
FROM daily_orders
ORDER BY order_date;

-- ------------------------------------------------------------
-- Q26: Gap (in days) between consecutive orders per customer
-- (LAG())
-- ------------------------------------------------------------
WITH customer_orders AS (
    SELECT customer_id, order_id, order_purchase_timestamp
    FROM orders
)
SELECT
    customer_id,
    order_id,
    order_purchase_timestamp,
    LAG(order_purchase_timestamp) OVER (
        PARTITION BY customer_id ORDER BY order_purchase_timestamp
    ) AS previous_order_ts,
    DATEDIFF(
        order_purchase_timestamp,
        LAG(order_purchase_timestamp) OVER (PARTITION BY customer_id ORDER BY order_purchase_timestamp)
    ) AS days_since_previous_order
FROM customer_orders
ORDER BY customer_id, order_purchase_timestamp;

-- NOTE: because `customers` is reconstructed 1:1 from orders (DQ
-- report #1), every customer_id has exactly ONE order here, so
-- days_since_previous_order is NULL for all rows. The query is
-- exactly what's needed once true customer_unique_id-level repeat
-- purchase history is available.

-- ------------------------------------------------------------
-- Q27: Rank sellers by revenue within each state, top 3 per state
-- ------------------------------------------------------------
WITH seller_state_revenue AS (
    SELECT
        s.seller_id,
        s.seller_state,
        SUM(oi.price) AS revenue,
        RANK() OVER (PARTITION BY s.seller_state ORDER BY SUM(oi.price) DESC) AS state_rank
    FROM sellers s
    JOIN order_items oi ON oi.seller_id = s.seller_id
    GROUP BY s.seller_id, s.seller_state
)
SELECT seller_id, seller_state, revenue, state_rank
FROM seller_state_revenue
WHERE state_rank <= 3
ORDER BY seller_state, state_rank;

-- ------------------------------------------------------------
-- Q28: Running total of revenue by date with % of grand total
-- ------------------------------------------------------------
WITH daily_revenue AS (
    SELECT DATE(o.order_purchase_timestamp) AS order_date, SUM(oi.price) AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    GROUP BY DATE(o.order_purchase_timestamp)
)
SELECT
    order_date,
    revenue,
    SUM(revenue) OVER (ORDER BY order_date ROWS UNBOUNDED PRECEDING) AS running_total,
    ROUND(
        SUM(revenue) OVER (ORDER BY order_date ROWS UNBOUNDED PRECEDING)
        / SUM(revenue) OVER () * 100
    , 2) AS pct_of_grand_total
FROM daily_revenue
ORDER BY order_date;
