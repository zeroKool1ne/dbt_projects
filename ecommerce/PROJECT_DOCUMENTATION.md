# E-Commerce Data Warehouse — End-to-End Pipeline Documentation

## Table of Contents

1. [The Big Picture](#1-the-big-picture)
2. [OLTP — The Data Source](#2-oltp--the-data-source)
3. [AWS S3 + Snowpipe — Ingestion](#3-aws-s3--snowpipe--ingestion)
4. [Snowflake — The Data Warehouse](#4-snowflake--the-data-warehouse)
5. [dbt — The Transformation Tool](#5-dbt--the-transformation-tool)
6. [Staging Layer](#6-staging-layer)
7. [Star Schema (OLAP)](#7-star-schema-olap)
8. [Data Marts](#8-data-marts)
9. [CUBE — Multi-Dimensional Aggregation](#9-cube--multi-dimensional-aggregation)
10. [Data Anonymization (GDPR)](#10-data-anonymization-gdpr)
11. [ETL vs ELT](#11-etl-vs-elt)
12. [Medallion Architecture](#12-medallion-architecture)
13. [Data Governance](#13-data-governance)
14. [Streamlit Dashboard](#14-streamlit-dashboard)
15. [Project Structure](#15-project-structure)

---

## 1. The Big Picture

This project builds an **end-to-end data pipeline** for an e-commerce company. Raw transactional data (OLTP) is ingested into a cloud data warehouse (Snowflake) and transformed into reporting-ready tables using dbt.

```
OLTP (operational system)                   OLAP (analytical system)
"Customer #42 ordered product X"    →       "Revenue per month by category"
Many small write operations                 Few large read operations
7 normalized tables                         Star schema + mart tables
```

### The Complete Data Flow

```
CSV files → AWS S3 → Snowpipe → RAW.OLTP → dbt staging → Star Schema → Data Marts
   E          L          L          ↑            T              T            T
                                 Bronze        Silver          Gold         Gold
```

---

## 2. OLTP — The Data Source

**OLTP = Online Transaction Processing.** This is how every application works behind the scenes. The database is **normalized** — data is not stored redundantly.

### The 7 Source Tables

```
client (200 rows)
├── type_id    → references client_type (5 types: Standard, VIP, Premium, New, Inactive)
└── status_id  → references client_status (5 statuses: Active, Inactive, Suspended, Pending, Deactivated)

orders (200 rows)
├── client_id  → references client
└── payment_id → references payment_method (4 methods: credit_card, coupon, bank_transfer, gift_card)

order_product (300 rows — which product in which order)
├── order_id   → references orders
└── product_id → references product (60 products)
```

### Why Normalized?

Imagine "credit_card" is stored in each of the 200 orders. If the name changes, you'd have to update 200 rows. With normalization, you change it once in `payment_method`. This is great for operational systems — but bad for analytics, because every question requires 5 JOINs.

---

## 3. AWS S3 + Snowpipe — Ingestion

### Storage Integration — Trust Relationship

```sql
CREATE STORAGE INTEGRATION s3_int
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::...:role/daniel.ironhack26'
  STORAGE_ALLOWED_LOCATIONS = ('s3://ironhack-ecommerce/');
```

This is like an **ID card**: Snowflake is allowed to access your S3 bucket, but ONLY this specific one. The `STORAGE_AWS_ROLE_ARN` points to an AWS IAM Role that grants the necessary permissions (GetObject, PutObject, ListBucket, etc.).

### File Format — How to Read CSVs

```sql
CREATE OR REPLACE FILE FORMAT my_csv_format
  TYPE = 'CSV'
  FIELD_DELIMITER = ','    -- columns separated by comma
  SKIP_HEADER = 1          -- first row = column names, skip it
  NULL_IF = ('NULL', '');  -- treat empty fields and "NULL" as NULL
```

### Stage — The Bridge Between S3 and Snowflake

```sql
CREATE STAGE my_s3_stage
  STORAGE_INTEGRATION = s3_int
  URL = 's3://ironhack-ecommerce/'
  FILE_FORMAT = my_csv_format;
```

A **Stage** is a pointer from Snowflake to your S3 bucket. Snowflake can see and read files through it without downloading them.

### Snowpipe — Automatic Loading

```sql
CREATE OR REPLACE PIPE orders_pipe
  AUTO_INGEST = TRUE AS
  COPY INTO raw.oltp.orders
    FROM @my_s3_stage/orders/
    FILE_FORMAT = my_csv_format
    PATTERN = '.*orders__.*';
```

**How AUTO_INGEST works:**

1. You upload a CSV to the S3 folder `orders/`
2. S3 sends an **Event Notification** to an SQS Queue (Amazon's messaging service)
3. Snowpipe listens to this queue and says: "New file detected!"
4. Snowpipe automatically runs `COPY INTO`
5. Data lands in `raw.oltp.orders`

This happens **without any manual intervention** — fully automatic, within seconds.

**PATTERN = `'.*orders__.*'`** is a regex: `.*` means "any characters". So: any file containing `orders__` in its name gets loaded (e.g. `orders__2025_22_03_13_55.csv`), but NOT `order_product__...csv`.

---

## 4. Snowflake — The Data Warehouse

Snowflake is a **cloud-based OLAP data warehouse** with a 3-level hierarchy:

```
DATABASE → SCHEMA → TABLE

RAW (database)
└── OLTP (schema)
    ├── client
    ├── client_status
    ├── orders
    └── ...

PREP (database)
├── HAND_ON (schema)          ← staging views
│   ├── stg_client
│   ├── stg_orders
│   └── ...
└── HAND_ON_OUTPUT (schema)   ← star schema + marts
    ├── dim_client
    ├── fact_orders
    ├── mart_monthly_sales
    └── ...

SNOWPIPE_DB (database)
└── PUBLIC (schema)
    ├── my_s3_stage
    ├── my_csv_format
    └── *_pipe (7 pipes)
```

### Key Snowflake Concepts

- **Virtual Warehouse** (`COMPUTE_WH`): The compute power. Snowflake separates storage from compute — you can scale them independently.
- **Database**: Top-level container for organizing data.
- **Schema**: Groups related tables within a database.
- **Stage**: External pointer to cloud storage (S3, Azure Blob, GCS).

---

## 5. dbt — The Transformation Tool

**dbt = Data Build Tool.** It makes SQL modular, testable, and version-controllable. Instead of writing one giant SQL script, you have small `.sql` files that build on each other.

dbt only does transformations — it does NOT load data. It is the **"T" in ELT**.

### `profiles.yml` — The Snowflake Connection

```yaml
ecommerce:
  outputs:
    dev:
      database: PREP           # default database for dbt output
      warehouse: COMPUTE_WH   # Snowflake's compute power
      type: snowflake
```

When you run `dbt run`, dbt connects to this Snowflake instance and executes SQL.

### `dbt_project.yml` — Main Configuration

```yaml
models:
  ecommerce:
    03_hands_on:
      +database: prep
      +schema: hand_on
      +materialized: table      # store as real table by default
    04_hands_on_output:
      +database: prep
      +schema: hand_on_output
      +materialized: table
```

**`+materialized: table` vs `view`:**
- **Table**: Data is physically copied and stored. Fast to read, uses storage.
- **View**: Just a saved query. No storage, but recalculated on every access.

### `macros/get_custom_schema.sql` — Schema Naming Override

```sql
{% macro generate_schema_name(custom_schema_name, node) %}
    {{ custom_schema_name }}
{% endmacro %}
```

Normally dbt appends the schema name to the default schema (e.g. `ecommerce_hand_on`). This macro overrides that: when you say `+schema: hand_on`, the schema is literally `hand_on` — not `ecommerce_hand_on`.

### `source.yml` — Source Definition

```yaml
sources:
  - name: ecommerce
    database: RAW
    schema: OLTP
    tables:
      - name: client     # → RAW.OLTP.CLIENT
      - name: orders     # → RAW.OLTP.ORDERS
```

This tells dbt: "Raw data lives in `RAW.OLTP`". When you write `{{ source('ecommerce', 'orders') }}` in SQL, dbt automatically replaces it with `RAW.OLTP.ORDERS`.

**Why not just write `RAW.OLTP.ORDERS` directly?**
1. If the database name changes, you change it in one place — not in 10 SQL files
2. dbt can track **lineage** — it knows which model uses which source
3. You can define **freshness tests** on sources (is the data up to date?)

### `source()` vs `ref()`

- `source('ecommerce', 'orders')` → points to **raw data** (RAW.OLTP)
- `ref('stg_client')` → points to **another dbt model**

dbt uses `ref()` to build the **Dependency Graph (DAG)**:
```
source.client → stg_client ──┐
source.client_status → stg_client_status ──┤→ dim_client
source.client_type → stg_client_type ──┘
```

---

## 6. Staging Layer

**Location:** `models/03_hands_on/` → `PREP.HAND_ON`

The staging models are the **first transformation layer**. They take raw data and make it clean, consistent, and documented.

### Example: `stg_orders.sql`

```sql
{{
    config(
        alias='stg_orders',
        materialized='view',    -- overrides the table setting from dbt_project.yml
        tags=['hand_on']
    )
}}

with source as (
    select * from {{ source('ecommerce', 'orders') }}
    -- dbt replaces this with: RAW.OLTP.ORDERS
),

renamed as (
    select
        order_id,
        client_id,
        payment_id,
        order_date,
        status,
        total_amount
    from source
)

select * from renamed
```

**What happens here:**
1. `source` CTE: Fetches all data from the raw table
2. `renamed` CTE: Explicitly selects columns (in complex projects you'd rename, cast types, etc.)
3. Final SELECT: Returns the result

**Why `materialized='view'`?** Staging data is just a pass-through. A view stores nothing — it's just a saved query. When someone queries `stg_orders`, the query runs live on `RAW.OLTP.ORDERS`. This saves storage.

**The CTE pattern (`with ... as`):** CTEs (Common Table Expressions) are like temporary tables within a query. The `source → renamed → select` pattern is a **dbt convention** — every staging model follows this structure.

### Staging Tests (`schema.yml`)

```yaml
models:
  - name: stg_orders
    columns:
      - name: order_id
        data_tests:
          - unique      # no duplicate order_ids
          - not_null    # no empty order_ids
```

When you run `dbt test`, dbt generates a SQL query for each test. For `unique`:

```sql
SELECT order_id, COUNT(*)
FROM prep.hand_on.stg_orders
GROUP BY order_id
HAVING COUNT(*) > 1
```

If the result has 0 rows → test passed. This is **Data Governance**: automated data quality checks.

---

## 7. Star Schema (OLAP)

**Location:** `models/04_hands_on_output/` → `PREP.HAND_ON_OUTPUT`

### Why Star Schema?

In OLTP you need **5 JOINs** to answer: *"How much did VIP customer John Doe spend on Electronics via credit card?"*

In a Star Schema you need **max 3 JOINs** — and they're all simple (Fact → Dimension):

```
        dim_client              dim_product
             \                    /
              \                  /
               fact_orders ────
              /
             /
        dim_payment
```

**Fact Table** = measurements, numbers, transactions (what happened?)
**Dimension Tables** = context (who, what, how?)

### `dim_client.sql` — A Dimension Table

```sql
final as (
    select
        c.client_id,
        c.client_name,
        -- anonymized fields (GDPR / data governance)
        concat(left(c.email, 1), '***@', split_part(c.email, '@', 2)) as email,
        concat('(***) ***-', right(c.phone_number, 4)) as phone_number,
        concat(left(c.address, 3), '***') as address,
        ct.type_name,        -- instead of type_id, now shows "VIP", "Standard", etc.
        cs.status_name,      -- instead of status_id, now shows "Active", "Inactive", etc.
        c.registration_date
    from client c
    left join client_type ct on c.type_id = ct.client_type_id
    left join client_status cs on c.status_id = cs.client_status_id
)
```

**This is denormalization:** Instead of 3 tables (client + client_type + client_status) you now have **1 table** with all info. The analyst sees `type_name = 'VIP'` directly instead of `type_id = 2`.

**Sensitive data is anonymized** in this layer (see [Section 10: Data Anonymization](#10-data-anonymization-gdpr)).

### `fact_orders.sql` — The Fact Table

```sql
final as (
    select
        op.order_product_id,     -- PK: one row per product per order
        o.order_id,
        o.client_id,             -- FK → dim_client
        op.product_id,           -- FK → dim_product
        o.payment_id,            -- FK → dim_payment
        o.order_date,
        o.status,
        op.quantity,             -- measure: how much was bought
        op.price_unit,           -- measure: unit price
        o.total_amount           -- measure: total order amount
    from orders o
    inner join order_product op on o.order_id = op.order_id
)
```

**Why `inner join`?** Every order has at least one product. INNER JOIN means: only rows where there's a match on both sides.

**Granularity:** The fact table has 300 rows (not 200 like `orders`), because one order can have multiple products. The granularity is **one row per product per order**.

### Relationship Tests

```yaml
- name: client_id
  data_tests:
    - relationships:
        to: ref('dim_client')
        field: client_id
```

This checks: **Does every `client_id` in `fact_orders` also exist in `dim_client`?** This is a foreign key integrity check.

---

## 8. Data Marts

**Location:** `models/04_hands_on_output/mart_*.sql` → `PREP.HAND_ON_OUTPUT`

Data marts are **pre-aggregated tables ready for dashboards**. No SQL knowledge needed — just `SELECT *`.

### `mart_monthly_sales.sql`

```sql
select
    date_trunc('month', order_date) as month,
    -- '2024-06-15' becomes '2024-06-01' (first day of month)
    count(distinct order_id) as total_orders,
    -- DISTINCT because one order can have multiple rows (one per product)
    sum(quantity) as total_units_sold,
    sum(price_unit * quantity) as total_revenue,
    round(sum(price_unit * quantity) / count(distinct order_id), 2) as avg_order_value
from fact
group by 1
order by 1
```

### `mart_sales_by_category.sql`

Aggregated by **product category**. Requires a JOIN to the dimension:

```sql
from fact f
inner join product p on f.product_id = p.product_id
group by p.category
```

### `mart_sales_by_client_type.sql`

Aggregated by **client type** (Standard, VIP, Premium, etc.). Same pattern with a JOIN to `dim_client`.

### `mart_sales_by_client.sql`

Aggregated per **individual client** — shows each client's total orders, revenue, first and last order date. Used for the "Top 10 Clients" chart in the dashboard.

---

## 9. CUBE — Multi-Dimensional Aggregation

CUBE is a SQL `GROUP BY` extension that automatically generates **all possible subtotal combinations**.

### Normal GROUP BY vs CUBE

```sql
-- Normal GROUP BY: only individual combinations
GROUP BY category, month
-- Result: Electronics + Jan, Electronics + Feb, Clothing + Jan, ...

-- GROUP BY CUBE: individual combinations + ALL subtotals
GROUP BY CUBE(category, month)
-- Result:
-- Electronics + Jan           ← individual combination
-- Electronics + Feb           ← individual combination
-- Clothing + Jan              ← individual combination
-- Clothing + Feb              ← individual combination
-- Electronics + ALL MONTHS    ← subtotal per category
-- Clothing + ALL MONTHS       ← subtotal per category
-- ALL CATEGORIES + Jan        ← subtotal per month
-- ALL CATEGORIES + Feb        ← subtotal per month
-- ALL CATEGORIES + ALL MONTHS ← grand total
```

Without CUBE you'd need 4 separate queries combined with `UNION ALL`. CUBE does it in a single query.

**How NULL works in CUBE:** When CUBE calculates a subtotal, it sets the "aggregated" column to `NULL`. We replace these with readable labels:

```sql
coalesce(category, 'ALL CATEGORIES') as category
-- NULL → 'ALL CATEGORIES'
```

This is a core **OLAP concept** — BI tools like Tableau use this internally for pivot tables and drill-down analysis.

### `mart_cube_category_month.sql`

Revenue broken down by **product category x month**, including subtotals for each category, each month, and a grand total.

```sql
group by cube(p.category, date_trunc('month', f.order_date))
```

### `mart_cube_payment_status.sql`

Revenue broken down by **payment method x order status**, including subtotals for each payment method, each status, and a grand total.

```sql
group by cube(pm.payment_method, f.status)
```

---

## 10. Data Anonymization (GDPR)

The `dim_client` table contains **personally identifiable information (PII)**. To comply with data protection regulations (GDPR/DSGVO), sensitive fields are masked in the analytical layer.

### What Gets Anonymized

| Field | Before | After | SQL Function |
|---|---|---|---|
| **Email** | `john.doe@example.com` | `j***@example.com` | `concat(left(email, 1), '***@', split_part(email, '@', 2))` |
| **Phone** | `(555) 123-4567` | `(***) ***-4567` | `concat('(***) ***-', right(phone_number, 4))` |
| **Address** | `123 Elm St` | `123***` | `concat(left(address, 3), '***')` |

### How Each Function Works

**Email masking:**
- `left(email, 1)` → takes the first character: `j`
- `'***@'` → static masking string
- `split_part(email, '@', 2)` → takes everything after the @: `example.com`
- Result: `j***@example.com`

**Phone masking:**
- `right(phone_number, 4)` → takes the last 4 characters: `4567`
- Result: `(***) ***-4567`

**Address masking:**
- `left(address, 3)` → takes the first 3 characters: `123`
- Result: `123***`

### Why Anonymize in the Analytical Layer?

The raw data in `RAW.OLTP.CLIENT` remains **unchanged** (Bronze layer). But in the analytical layer (`dim_client`), which analysts and dashboards access, sensitive data is masked. A business analyst needs the client type and purchase behavior — but not the actual email address or phone number.

---

## 11. ETL vs ELT

```
ETL (traditional):
Source → [Extract] → [Transform on dedicated server] → [Load into warehouse]
                      ↑ bottleneck: own server needed

ELT (this project):
Source → [Extract + Load directly into warehouse] → [Transform IN the warehouse]
          S3 + Snowpipe                               dbt (uses Snowflake's compute)
```

**This project uses ELT:**
- **E+L:** CSVs → S3 → Snowpipe → `RAW.OLTP` (data arrives raw)
- **T:** dbt transforms inside Snowflake into `PREP`

The advantage: Snowflake can compute massively in parallel. Instead of running an expensive transform server, you use Snowflake's power.

---

## 12. Medallion Architecture

The project follows the **Medallion Architecture** pattern with three layers:

```
BRONZE = RAW.OLTP                    (raw data, 1:1 copy of CSV)
SILVER = PREP.HAND_ON               (staging: cleaned, explicitly named)
GOLD   = PREP.HAND_ON_OUTPUT        (star schema + marts: ready for analysts)
```

Each layer has more structure and less chaos than the previous one.

---

## 13. Data Governance

| Aspect | Where in this project |
|---|---|
| **Data quality** | `schema.yml`: unique, not_null, relationships tests |
| **Lineage** | `source()` + `ref()` — dbt knows the complete data flow |
| **Documentation** | `description` fields in schema.yml |
| **Access control** | `RAW` (raw data, read-only) vs `PREP` (dbt writes here) |
| **Naming conventions** | `stg_` = staging, `dim_` = dimension, `fact_` = fact, `mart_` = mart |
| **PII anonymization** | `dim_client`: email, phone, address are masked (see [Section 10](#10-data-anonymization-gdpr)) |

Run `dbt docs generate && dbt docs serve` to see the full lineage graph and documentation in your browser.

---

## 14. Streamlit Dashboard

The project includes a **Streamlit dashboard** (`dashboard.py`) that connects directly to Snowflake and visualizes the data mart tables.

### Features

- **4 KPI cards**: Total Revenue, Total Orders, Unique Clients, Units Sold
- **Monthly Sales bar chart**: Revenue trend over time
- **Revenue by Category pie chart**: Product category distribution
- **Revenue by Client Type bar chart**: Spending by client segment
- **CUBE Analysis heatmap**: Category x Month revenue matrix
- **CUBE Analysis grouped bars**: Payment Method x Order Status breakdown
- **Top 10 Clients bar chart**: Highest-spending clients
- **6 detail table tabs**: Raw data for all mart tables including CUBE results

### How to Run

```bash
source ../dbt-env/bin/activate
streamlit run dashboard.py
```

The dashboard connects to `PREP.HAND_ON_OUTPUT` and queries the mart tables directly. Data is cached for 10 minutes (`ttl=600`).

---

## 15. Project Structure

```
ecommerce/
├── dbt_project.yml                          # main config: project name, materialization, schemas
├── snowflake_setup.sql                      # complete Snowflake setup (integration, tables, pipes)
├── dashboard.py                             # Streamlit dashboard for data visualization
├── PROJECT_DOCUMENTATION.md                 # this file
│
├── models/
│   ├── raw/
│   │   └── source.yml                       # defines 7 source tables in RAW.OLTP
│   │
│   ├── 03_hands_on/                         # SILVER — staging layer
│   │   ├── schema.yml                       # data quality tests (unique, not_null)
│   │   ├── stg_client.sql
│   │   ├── stg_client_status.sql
│   │   ├── stg_client_type.sql
│   │   ├── stg_orders.sql
│   │   ├── stg_order_product.sql
│   │   ├── stg_product.sql
│   │   └── stg_payment_method.sql
│   │
│   └── 04_hands_on_output/                  # GOLD — star schema + data marts
│       ├── schema.yml                       # tests + relationship integrity checks
│       ├── dim_client.sql                   # dimension: clients with type + status (anonymized PII)
│       ├── dim_product.sql                  # dimension: products with category + price
│       ├── dim_payment.sql                  # dimension: payment methods
│       ├── fact_orders.sql                  # fact: order line items (300 rows)
│       ├── mart_monthly_sales.sql           # mart: revenue per month
│       ├── mart_sales_by_category.sql       # mart: revenue per product category
│       ├── mart_sales_by_client_type.sql    # mart: revenue per client type
│       ├── mart_sales_by_client.sql         # mart: revenue per individual client
│       ├── mart_cube_category_month.sql     # mart: CUBE aggregation (category x month)
│       └── mart_cube_payment_status.sql     # mart: CUBE aggregation (payment x status)
│
├── macros/
│   └── get_custom_schema.sql                # overrides default schema naming behavior
│
├── seeds/                                   # for loading CSV files directly via dbt
├── snapshots/                               # for tracking historical changes (SCD)
├── tests/                                   # custom SQL tests
├── analyses/                                # ad-hoc analytical queries
└── target/                                  # compiled SQL (what Snowflake actually executes)
```

### Row Counts

| Layer | Table | Rows |
|---|---|---|
| Bronze | raw.oltp.client | 200 |
| Bronze | raw.oltp.client_status | 5 |
| Bronze | raw.oltp.client_type | 5 |
| Bronze | raw.oltp.orders | 200 |
| Bronze | raw.oltp.order_product | 300 |
| Bronze | raw.oltp.product | 60 |
| Bronze | raw.oltp.payment_method | 4 |
| Gold | prep.hand_on_output.dim_client | 200 |
| Gold | prep.hand_on_output.dim_product | 60 |
| Gold | prep.hand_on_output.dim_payment | 4 |
| Gold | prep.hand_on_output.fact_orders | 300 |
| Gold | prep.hand_on_output.mart_monthly_sales | per month |
| Gold | prep.hand_on_output.mart_sales_by_category | per category |
| Gold | prep.hand_on_output.mart_sales_by_client_type | per client type |
| Gold | prep.hand_on_output.mart_sales_by_client | per client |
| Gold | prep.hand_on_output.mart_cube_category_month | CUBE (category x month) |
| Gold | prep.hand_on_output.mart_cube_payment_status | CUBE (payment x status) |

### Commands

```bash
dbt run                      # build all models
dbt test                     # run all data quality tests
dbt run --select 03_hands_on # build only staging models
dbt run --select 04_hands_on_output  # build only star schema + marts
dbt docs generate && dbt docs serve  # view lineage graph in browser
streamlit run dashboard.py   # launch the Streamlit dashboard
```
