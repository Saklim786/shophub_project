-- ============================================================
-- ShopHub Analytics Database — Schema Design (3NF)
-- Dataset: Brazilian E-Commerce Public Dataset by Olist
-- Author: Data Engineering Assignment 1
-- ============================================================

DROP DATABASE IF EXISTS shophub_analytics;
CREATE DATABASE shophub_analytics CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE shophub_analytics;

-- ------------------------------------------------------------
-- 1. CUSTOMERS
-- One row per customer transaction identity (customer_id).
-- customer_unique_id links repeat customers across orders.
-- ------------------------------------------------------------
CREATE TABLE customers (
    customer_id            CHAR(32)      NOT NULL,
    customer_unique_id     CHAR(32)      NOT NULL,
    customer_zip_code_prefix VARCHAR(10),
    customer_city           VARCHAR(100),
    customer_state          CHAR(2),
    created_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (customer_id),
    CONSTRAINT chk_cust_state CHECK (customer_state IS NULL OR CHAR_LENGTH(customer_state) = 2)
) ENGINE=InnoDB;

CREATE INDEX idx_customers_unique_id ON customers(customer_unique_id);
CREATE INDEX idx_customers_state ON customers(customer_state);

-- ------------------------------------------------------------
-- 2. SELLERS
-- ------------------------------------------------------------
CREATE TABLE sellers (
    seller_id               CHAR(32)      NOT NULL,
    seller_zip_code_prefix  VARCHAR(10),
    seller_city             VARCHAR(100),
    seller_state             CHAR(2),
    PRIMARY KEY (seller_id),
    CONSTRAINT chk_seller_state CHECK (seller_state IS NULL OR CHAR_LENGTH(seller_state) = 2)
) ENGINE=InnoDB;

CREATE INDEX idx_sellers_state ON sellers(seller_state);

-- ------------------------------------------------------------
-- 3. PRODUCT_CATEGORY (normalized out of products for 3NF)
-- ------------------------------------------------------------
CREATE TABLE product_category (
    category_id        INT AUTO_INCREMENT PRIMARY KEY,
    category_name       VARCHAR(100) NOT NULL UNIQUE
) ENGINE=InnoDB;

-- ------------------------------------------------------------
-- 4. PRODUCTS
-- ------------------------------------------------------------
CREATE TABLE products (
    product_id                 CHAR(32) NOT NULL,
    category_id                 INT,
    product_name_length         INT,
    product_description_length  INT,
    product_photos_qty          INT     DEFAULT 0,
    product_weight_g            DECIMAL(10,2),
    product_length_cm           DECIMAL(10,2),
    product_height_cm           DECIMAL(10,2),
    product_width_cm            DECIMAL(10,2),
    PRIMARY KEY (product_id),
    CONSTRAINT fk_products_category FOREIGN KEY (category_id)
        REFERENCES product_category(category_id) ON DELETE SET NULL,
    CONSTRAINT chk_product_weight CHECK (product_weight_g IS NULL OR product_weight_g >= 0)
) ENGINE=InnoDB;

CREATE INDEX idx_products_category ON products(category_id);

-- ------------------------------------------------------------
-- 5. ORDERS
-- ------------------------------------------------------------
CREATE TABLE orders (
    order_id                       CHAR(32) NOT NULL,
    customer_id                    CHAR(32) NOT NULL,
    order_status                   VARCHAR(20) NOT NULL,
    order_purchase_timestamp        DATETIME NOT NULL,
    order_approved_at               DATETIME NULL,
    order_delivered_carrier_date    DATETIME NULL,
    order_delivered_customer_date   DATETIME NULL,
    order_estimated_delivery_date   DATETIME NOT NULL,
    PRIMARY KEY (order_id),
    CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id)
        REFERENCES customers(customer_id) ON DELETE RESTRICT,
    CONSTRAINT chk_order_status CHECK (order_status IN
        ('created','approved','processing','shipped','delivered','invoiced','canceled','unavailable'))
) ENGINE=InnoDB;

CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_status ON orders(order_status);
CREATE INDEX idx_orders_purchase_ts ON orders(order_purchase_timestamp);

-- ------------------------------------------------------------
-- 6. ORDER_ITEMS
-- ------------------------------------------------------------
CREATE TABLE order_items (
    order_id                CHAR(32) NOT NULL,
    order_item_id            INT NOT NULL,
    product_id               CHAR(32) NOT NULL,
    seller_id                CHAR(32) NOT NULL,
    shipping_limit_date      DATETIME,
    price                    DECIMAL(10,2) NOT NULL,
    freight_value            DECIMAL(10,2) NOT NULL DEFAULT 0,
    PRIMARY KEY (order_id, order_item_id),
    CONSTRAINT fk_items_order FOREIGN KEY (order_id)
        REFERENCES orders(order_id) ON DELETE CASCADE,
    CONSTRAINT fk_items_product FOREIGN KEY (product_id)
        REFERENCES products(product_id) ON DELETE RESTRICT,
    CONSTRAINT fk_items_seller FOREIGN KEY (seller_id)
        REFERENCES sellers(seller_id) ON DELETE RESTRICT,
    CONSTRAINT chk_price_positive CHECK (price >= 0),
    CONSTRAINT chk_freight_nonneg CHECK (freight_value >= 0)
) ENGINE=InnoDB;

CREATE INDEX idx_items_product ON order_items(product_id);
CREATE INDEX idx_items_seller ON order_items(seller_id);

-- ------------------------------------------------------------
-- 7. ORDER_PAYMENTS
-- ------------------------------------------------------------
CREATE TABLE order_payments (
    order_id                CHAR(32) NOT NULL,
    payment_sequential       INT NOT NULL,
    payment_type              VARCHAR(20) NOT NULL,
    payment_installments       INT NOT NULL DEFAULT 1,
    payment_value              DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (order_id, payment_sequential),
    CONSTRAINT fk_payments_order FOREIGN KEY (order_id)
        REFERENCES orders(order_id) ON DELETE CASCADE,
    CONSTRAINT chk_payment_value CHECK (payment_value >= 0),
    CONSTRAINT chk_installments CHECK (payment_installments >= 0)
) ENGINE=InnoDB;

CREATE INDEX idx_payments_order ON order_payments(order_id);
CREATE INDEX idx_payments_type ON order_payments(payment_type);

-- ------------------------------------------------------------
-- 8. ORDER_REVIEWS
-- ------------------------------------------------------------
CREATE TABLE order_reviews (
    review_id                     CHAR(32) NOT NULL,
    order_id                       CHAR(32) NOT NULL,
    review_score                    TINYINT NOT NULL,
    review_comment_title             VARCHAR(255),
    review_comment_message            TEXT,
    review_creation_date               DATETIME,
    review_answer_timestamp            DATETIME,
    PRIMARY KEY (review_id, order_id),
    CONSTRAINT fk_reviews_order FOREIGN KEY (order_id)
        REFERENCES orders(order_id) ON DELETE CASCADE,
    CONSTRAINT chk_review_score CHECK (review_score BETWEEN 1 AND 5)
) ENGINE=InnoDB;

CREATE INDEX idx_reviews_order ON order_reviews(order_id);
CREATE INDEX idx_reviews_score ON order_reviews(review_score);

-- ------------------------------------------------------------
-- 9. GEOLOCATION
-- (kept denormalized/raw per Olist source grain: many rows per zip
--  prefix representing distinct lat/lng samples)
-- ------------------------------------------------------------
CREATE TABLE geolocation (
    geo_id                      BIGINT AUTO_INCREMENT PRIMARY KEY,
    geolocation_zip_code_prefix  VARCHAR(10) NOT NULL,
    geolocation_lat               DECIMAL(10,6),
    geolocation_lng               DECIMAL(10,6),
    geolocation_city               VARCHAR(100),
    geolocation_state               CHAR(2)
) ENGINE=InnoDB;

CREATE INDEX idx_geo_zip ON geolocation(geolocation_zip_code_prefix);
CREATE INDEX idx_geo_state ON geolocation(geolocation_state);

-- ------------------------------------------------------------
-- Staging tables (raw load target before cleaning transformations)
-- ------------------------------------------------------------
CREATE TABLE stg_customers (
    customer_id VARCHAR(64), customer_unique_id VARCHAR(64),
    customer_zip_code_prefix VARCHAR(20), customer_city VARCHAR(150), customer_state VARCHAR(10)
) ENGINE=InnoDB;

CREATE TABLE stg_orders (
    order_id VARCHAR(64), customer_id VARCHAR(64), order_status VARCHAR(50),
    order_purchase_timestamp VARCHAR(50), order_approved_at VARCHAR(50),
    order_delivered_carrier_date VARCHAR(50), order_delivered_customer_date VARCHAR(50),
    order_estimated_delivery_date VARCHAR(50)
) ENGINE=InnoDB;

CREATE TABLE stg_order_items (
    order_id VARCHAR(64), order_item_id VARCHAR(20), product_id VARCHAR(64),
    seller_id VARCHAR(64), shipping_limit_date VARCHAR(50), price VARCHAR(30), freight_value VARCHAR(30)
) ENGINE=InnoDB;

CREATE TABLE stg_products (
    product_id VARCHAR(64), product_category_name VARCHAR(150),
    product_name_lenght VARCHAR(20), product_description_lenght VARCHAR(20),
    product_photos_qty VARCHAR(20), product_weight_g VARCHAR(20),
    product_length_cm VARCHAR(20), product_height_cm VARCHAR(20), product_width_cm VARCHAR(20)
) ENGINE=InnoDB;

CREATE TABLE stg_sellers (
    seller_id VARCHAR(64), seller_zip_code_prefix VARCHAR(20), seller_city VARCHAR(150), seller_state VARCHAR(10)
) ENGINE=InnoDB;

CREATE TABLE stg_order_payments (
    order_id VARCHAR(64), payment_sequential VARCHAR(20), payment_type VARCHAR(50),
    payment_installments VARCHAR(20), payment_value VARCHAR(30)
) ENGINE=InnoDB;

CREATE TABLE stg_order_reviews (
    review_id VARCHAR(64), order_id VARCHAR(64), review_score VARCHAR(10),
    review_comment_title VARCHAR(255), review_comment_message TEXT,
    review_creation_date VARCHAR(50), review_answer_timestamp VARCHAR(50)
) ENGINE=InnoDB;

CREATE TABLE stg_geolocation (
    geolocation_zip_code_prefix VARCHAR(20), geolocation_lat VARCHAR(30),
    geolocation_lng VARCHAR(30), geolocation_city VARCHAR(150), geolocation_state VARCHAR(10)
) ENGINE=InnoDB;
