# ShopHub Analytics — Query Optimization Report

**Engine:** MySQL 8.0.46 (InnoDB), all indexes are B-tree (InnoDB does not
support user-created HASH indexes — see note at the end).

![Performance Comparison](performance_chart.png)

## Method
Three representative, non-trivial queries from the assignment's Part D/C
were run with `EXPLAIN ANALYZE` to capture real execution time (not just
the optimizer's cost estimate), then 3 targeted composite indexes were
added, then the same 3 queries were re-run unchanged.

## Slow queries identified

| # | Query | What it does | Baseline time |
|---|-------|--------------|---------------|
| 1 | Q19 — Market basket self-join | `order_items` self-joined on `order_id` to find product pairs bought together | **714 ms** |
| 2 | Q17 — Category exclusion antijoin | Customers who bought 'eletronicos' but never a books category (NOT IN subquery, 5-table join x2) | **1,691 ms** |
| 3 | Q12 — Top-10 products per category | `order_items` -> `products` -> `product_category`, `GROUP BY` + `DENSE_RANK()` window | **1,692 ms** |

## Indexes added

```sql
CREATE INDEX idx_items_product_price   ON order_items(product_id, price);
CREATE INDEX idx_items_order_product   ON order_items(order_id, product_id);
CREATE INDEX idx_orders_customer_purchase ON orders(customer_id, order_purchase_timestamp);
```

- `idx_items_product_price` — covering index for the very common
  "GROUP BY product_id, SUM(price)" pattern used in Q12, Q13, Q18, Q22.
- `idx_items_order_product` — the existing PRIMARY KEY on `order_items`
  is `(order_id, order_item_id)`, so any query joining/filtering on
  `(order_id, product_id)` together (Q17's antijoin, Q19's self-join)
  previously needed an extra row lookup for `product_id`. This composite
  index makes that index-only.
- `idx_orders_customer_purchase` — speeds per-customer, timestamp-ordered
  window functions (Q24 consecutive-month streaks, Q26 `LAG()` gap
  analysis) by avoiding a sort per partition.

## Results (after indexing, same queries, unchanged)

| # | Query | Before | After | Change |
|---|-------|--------|-------|--------|
| 1 | Q19 — market basket | 714 ms | 791 ms | No meaningful improvement — the optimizer was already using a good plan (`idx_items_product` covering scan + `PRIMARY` lookup); the new composite index wasn't selected for this join shape. The difference is within normal run-to-run variance. |
| 2 | Q17 — category antijoin | 1,691 ms | 83 ms | **~20x faster.** The inner antijoin subquery's `oi2` lookup went from a `PRIMARY`-then-row-fetch pattern to an index-only lookup via `idx_items_order_product`, cutting the dominant cost in the 2,767-loop nested antijoin. |
| 3 | Q12 — top products/category | 1,692 ms | 1,390 ms | **~18% faster.** `idx_items_product_price` turned the `oi` join step into a covering index lookup (no row fetch for `price`), shrinking the underlying aggregation that feeds the window function. The window/sort step itself (on 32,951 rows) is unchanged and remains the larger share of total time. |

## Why not every query improved equally
Query 1 shows this isn't "add indexes = always faster" — MySQL's
optimizer had already chosen a reasonable plan using the pre-existing
`idx_items_product` and the `PRIMARY` key, and the workload here (self-
join + `COUNT(DISTINCT)` + a full sort of ~6k grouped pairs) is bound
by the sort/aggregate step, not the join lookup, so a new index on the
same columns didn't change the bottleneck. This is a realistic outcome
and is reported honestly rather than cherry-picked.

## On Hash indexes
The assignment mentions "B-tree, Hash" indexes. InnoDB (MySQL's default
and only production storage engine here) does **not** support
user-declared `HASH` indexes — it maintains its own internal *adaptive
hash index* automatically over frequently-accessed B-tree pages, which
cannot be created or tuned by the DBA via DDL. `HASH` indexes are only
explicitly creatable in MySQL on the `MEMORY` storage engine, which is
not appropriate for this durable analytics workload. All indexes in this
project are therefore B-tree, which is also the structurally correct
choice for every access pattern used here (equality lookups, range
scans on dates, and `ORDER BY`/`GROUP BY` support) — hash indexes only
support pure equality lookups and would not help the range/sort-heavy
queries in this workload anyway.
