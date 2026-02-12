-- ============================================================
-- SECTION 1: STORAGE INTEGRATION (connect Snowflake to AWS S3)
-- ============================================================

CREATE STORAGE INTEGRATION s3_int
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::872964974583:role/daniel.ironhack26'
  STORAGE_ALLOWED_LOCATIONS = ('s3://ironhack-ecommerce/');

-- retrieve IAM user ARN and external ID for trust policy configuration
DESC INTEGRATION s3_int;


-- ============================================================
-- SECTION 2: SNOWPIPE DATABASE, FILE FORMAT & STAGE
-- ============================================================

CREATE DATABASE snowpipe_db;
USE DATABASE snowpipe_db;
USE SCHEMA public;

-- define how Snowflake reads incoming CSV files
CREATE OR REPLACE FILE FORMAT my_csv_format
  TYPE = 'CSV'
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  NULL_IF = ('NULL', '');

-- create stage pointing to S3 bucket
CREATE STAGE my_s3_stage
  STORAGE_INTEGRATION = s3_int
  URL = 's3://ironhack-ecommerce/'
  FILE_FORMAT = my_csv_format;

-- verify connection to S3
LIST @my_s3_stage;


-- ============================================================
-- SECTION 3: RAW DATABASE & OLTP TABLES
-- ============================================================

CREATE DATABASE raw;
CREATE SCHEMA raw.oltp;
USE SCHEMA raw.oltp;

CREATE TABLE IF NOT EXISTS client (
  client_id INTEGER,
  client_name STRING,
  email STRING,
  phone_number STRING,
  address STRING,
  type_id INTEGER,
  status_id INTEGER,
  registration_date TIMESTAMP
);

CREATE TABLE IF NOT EXISTS client_status (
  client_status_id INTEGER,
  status_name STRING
);

CREATE TABLE IF NOT EXISTS client_type (
  client_type_id INTEGER,
  type_name STRING
);

CREATE TABLE IF NOT EXISTS orders (
  order_id INTEGER,
  client_id INTEGER,
  payment_id INTEGER,
  order_date DATE,
  status STRING,
  total_amount DECIMAL(10,2)
);

CREATE TABLE IF NOT EXISTS order_product (
  order_product_id INTEGER,
  order_id INTEGER,
  product_id INTEGER,
  quantity DECIMAL(10,1),
  price_unit DECIMAL(10,2)
);

CREATE TABLE IF NOT EXISTS product (
  product_id INTEGER,
  product_name STRING,
  category STRING,
  price DECIMAL(10,2)
);

CREATE TABLE IF NOT EXISTS payment_method (
  payment_id INTEGER,
  payment_method STRING
);


-- ============================================================
-- SECTION 4: SNOWPIPES (auto-ingest from S3 into RAW.OLTP)
-- ============================================================

USE DATABASE snowpipe_db;
USE SCHEMA public;

CREATE OR REPLACE PIPE client_pipe
  AUTO_INGEST = TRUE AS
  COPY INTO raw.oltp.client
    FROM @my_s3_stage/client/
    FILE_FORMAT = my_csv_format
    PATTERN = '.*client__.*';

CREATE OR REPLACE PIPE client_status_pipe
  AUTO_INGEST = TRUE AS
  COPY INTO raw.oltp.client_status
    FROM @my_s3_stage/client_status/
    FILE_FORMAT = my_csv_format
    PATTERN = '.*client_status__.*';

CREATE OR REPLACE PIPE client_type_pipe
  AUTO_INGEST = TRUE AS
  COPY INTO raw.oltp.client_type
    FROM @my_s3_stage/client_type/
    FILE_FORMAT = my_csv_format
    PATTERN = '.*client_type__.*';

CREATE OR REPLACE PIPE orders_pipe
  AUTO_INGEST = TRUE AS
  COPY INTO raw.oltp.orders
    FROM @my_s3_stage/orders/
    FILE_FORMAT = my_csv_format
    PATTERN = '.*orders__.*';

CREATE OR REPLACE PIPE order_product_pipe
  AUTO_INGEST = TRUE AS
  COPY INTO raw.oltp.order_product
    FROM @my_s3_stage/order_product/
    FILE_FORMAT = my_csv_format
    PATTERN = '.*order_product__.*';

CREATE OR REPLACE PIPE product_pipe
  AUTO_INGEST = TRUE AS
  COPY INTO raw.oltp.product
    FROM @my_s3_stage/product/
    FILE_FORMAT = my_csv_format
    PATTERN = '.*product__.*';

CREATE OR REPLACE PIPE payment_method_pipe
  AUTO_INGEST = TRUE AS
  COPY INTO raw.oltp.payment_method
    FROM @my_s3_stage/payment_method/
    FILE_FORMAT = my_csv_format
    PATTERN = '.*payment_method__.*';

-- retrieve SQS ARNs for S3 event notification setup
SHOW PIPES;


-- ============================================================
-- SECTION 5: DEBUGGING & VALIDATION
-- ============================================================

-- check pipe status
SELECT SYSTEM$PIPE_STATUS('snowpipe_db.public.client_pipe');

-- trigger refresh for existing files in S3
ALTER PIPE client_pipe REFRESH;
ALTER PIPE client_status_pipe REFRESH;
ALTER PIPE client_type_pipe REFRESH;
ALTER PIPE orders_pipe REFRESH;
ALTER PIPE order_product_pipe REFRESH;
ALTER PIPE product_pipe REFRESH;
ALTER PIPE payment_method_pipe REFRESH;

-- verify row counts in raw tables
SELECT 'client' AS table_name, COUNT(*) AS row_count FROM raw.oltp.client
UNION ALL
SELECT 'client_status', COUNT(*) FROM raw.oltp.client_status
UNION ALL
SELECT 'client_type', COUNT(*) FROM raw.oltp.client_type
UNION ALL
SELECT 'orders', COUNT(*) FROM raw.oltp.orders
UNION ALL
SELECT 'order_product', COUNT(*) FROM raw.oltp.order_product
UNION ALL
SELECT 'product', COUNT(*) FROM raw.oltp.product
UNION ALL
SELECT 'payment_method', COUNT(*) FROM raw.oltp.payment_method;

-- verify row counts in star schema (after dbt run)
SELECT 'dim_client' AS table_name, COUNT(*) AS row_count FROM prep.hand_on_output.dim_client
UNION ALL
SELECT 'dim_product', COUNT(*) FROM prep.hand_on_output.dim_product
UNION ALL
SELECT 'dim_payment', COUNT(*) FROM prep.hand_on_output.dim_payment
UNION ALL
SELECT 'fact_orders', COUNT(*) FROM prep.hand_on_output.fact_orders;

-- verify data mart tables (after dbt run)
SELECT * FROM prep.hand_on_output.mart_monthly_sales;
SELECT * FROM prep.hand_on_output.mart_sales_by_category;
SELECT * FROM prep.hand_on_output.mart_sales_by_client_type;
