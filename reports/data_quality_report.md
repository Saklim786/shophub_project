# ShopHub Analytics — Data Quality Findings Report

**Dataset:** Brazilian E-Commerce Public Dataset by Olist
**Prepared for:** Assignment 1 — SQL Mastery (ShopHub Analytics)

This report documents data quality issues found in the raw CSV files during
loading and cleaning, how each was detected, and how it was handled in
`02_data_cleaning/02_clean_transform.sql`.

---

## 1. Missing source file — `olist_customers_dataset.csv`
The official Olist dataset ships 9 files (8 tables + product category
translation). In this assignment run, **`olist_customers_dataset.csv` was not
provided** with the other 8 files.
- **Impact:** No customer name, true `customer_unique_id` mapping (repeat
  buyers), zip, city, or state.
- **Fix applied:** `customers` was reconstructed from the distinct
  `customer_id` values in `orders`. `customer_unique_id` was set equal to
  `customer_id` as a documented placeholder. `customer_zip_code_prefix`,
  `customer_city`, `customer_state` are `NULL` for all rows.
- **Consequence flagged downstream:** Any query that depends on true repeat-
  customer identity (CLV across a return visitor, "same email different
  name") operates on `customer_id` granularity instead of
  `customer_unique_id`, and is explicitly noted at the query site.

## 2. Character-encoding corruption in two files
`olist_order_reviews_dataset.csv` and `olist_geolocation_dataset.csv` are not
valid UTF‑8 — they mix UTF‑8 and Windows‑1252 (cp1252) byte sequences line by
line (e.g. `"sAM-#o paulo"` instead of `"são paulo"`).
- **Detection:** `bytes.decode('utf-8')` raised `UnicodeDecodeError`; MySQL's
  `LOAD DATA` also rejected the raw file with `Invalid utf8mb4 character
  string`.
- **Fix applied:** Each file was re-decoded line-by-line (UTF‑8 → cp1252 →
  latin1 fallback) and re-encoded as clean UTF‑8 before loading.
- Affected: 262 rows in `order_reviews` had at least one non-UTF‑8 byte.

## 3. Sign-inversion bug in `geolocation` lat/lng (100% of rows)
Every row in the geolocation file has **positive** latitude and longitude
(e.g. `lat=23.54, lng=46.63`), but the paired `geolocation_city`/`state`
columns are explicit Brazilian values (`"sao paulo", "SP"`). True São Paulo
sits at approximately `(-23.54, -46.63)` — Brazil is entirely in the
Southern/Western hemisphere, so both values should be negative.
- **Detection:** Bounding-box sanity check (`lat` should be roughly
  `-35..6`, `lng` roughly `-75..-33`) showed **0 of 1,000,162 rows** inside
  the expected range; manual inspection against `geolocation_state`
  confirmed all 27 valid Brazilian UF codes are present, ruling out
  "wrong country" and confirming a systematic sign error.
- **Fix applied:** Negated both `geolocation_lat` and `geolocation_lng`
  (`-ABS(x)`) on load rather than dropping ~1M rows.

## 4. Inconsistent date/time formats across files
- `orders`: `YYYY-MM-DD HH:MM:SS` (ISO-like)
- `order_reviews`: `DD-MM-YYYY HH:MM` (day-first, no seconds)
- **Detection:** `STR_TO_DATE` with the `orders` format silently produced
  `NULL` for every row of `order_reviews` on a first pass.
- **Fix applied:** Two different `STR_TO_DATE` format masks used per table
  in `02_clean_transform.sql`.

## 5. Duplicate copies of two source files supplied
`olist_geolocation_dataset.csv` and `olist_order_payments_dataset.csv` were
each uploaded twice (once as `..._-_Copy.csv`). Byte-identical.
- **Fix applied:** Duplicate copies excluded from the load; only one copy of
  each file used.

## 6. Free-text / placeholder review content
`review_comment_title` and `review_comment_message` contain the literal
placeholder value `"A"` in a large share of rows instead of real text or a
true `NULL`, suggesting an anonymization or scrubbing step upstream that
replaced free text with a filler character.
- **Fix applied:** Left as-is (not fabricated/imputed) but flagged here since
  any NLP/text-mining work on this column would need to filter these out
  first.

## 7. Missing `product_category_name` (610 products)
610 of 32,951 products (1.9%) have a blank/NULL category.
- **Fix applied:** Mapped to an explicit `'unknown'` category row in
  `product_category` rather than left `NULL`, so aggregate-by-category
  queries don't silently drop these products.

## 8. Missing physical dimensions (2 products)
2 products have `NULL` weight/length/height/width — too small a number to
impute confidently; left `NULL` and documented.

## 9. Payment total vs. order total mismatch (potential fraud / rounding)
**1,075 of 99,441 orders (~1.1%)** have `SUM(payment_value)` that does not
equal `SUM(order_items.price + freight_value)` for that order (see Part B,
Q10). Some are legitimate (partial refunds, split payments across
installments with rounding), but the population is large enough to warrant
a dedicated fraud/reconciliation query — implemented in
`03_queries/part_b_manipulation_retrieval.sql`.

## 10. Orders with no matching payment record
1 order in `orders` has zero rows in `order_payments` — an incomplete
transaction (likely abandoned/failed checkout that still created an order
row). Flagged, not deleted, since it's a legitimate business state.

## 11. Orders marked `delivered` with a NULL delivery date
8 orders have `order_status = 'delivered'` but
`order_delivered_customer_date IS NULL` — a status/data inconsistency
(status updated without the corresponding timestamp field).

## 12. CSV quoting / delimiter edge cases
Several free-text fields (product names historically, review messages) can
contain embedded commas and quotes. All `LOAD DATA` statements explicitly
use `FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'` to avoid
mis-splitting these rows.

---

## Summary Table

| # | Issue | Rows affected | Action |
|---|-------|---------------|--------|
| 1 | Missing customers file | 99,441 (all) | Reconstructed from orders |
| 2 | Encoding corruption | 262+ (reviews), all (geo) | Re-encoded to UTF-8 |
| 3 | Lat/lng sign inversion | 1,000,162 (all) | Sign corrected |
| 4 | Inconsistent date formats | all of order_reviews | Per-table format mask |
| 5 | Duplicate file uploads | 2 files | Deduplicated at load |
| 6 | Placeholder review text | majority of reviews | Flagged, not modified |
| 7 | Missing product category | 610 | Mapped to 'unknown' |
| 8 | Missing product dimensions | 2 | Left NULL, documented |
| 9 | Payment/order total mismatch | 1,075 orders | Query built (Q10) |
| 10 | Orders with no payment row | 1 | Flagged |
| 11 | Delivered status, no delivery date | 8 | Flagged |
| 12 | Embedded commas/quotes in text | n/a | Handled via CSV quoting rules |

12 issues documented (assignment required 10+).
