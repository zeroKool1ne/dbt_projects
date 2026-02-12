{{
    config(
        alias='mart_cube_category_month',
        materialized='table',
        tags=['hand_on_output']
    )
}}

with fact as (
    select * from {{ ref('fact_orders') }}
),

product as (
    select * from {{ ref('dim_product') }}
),

final as (
    select
        p.category,
        date_trunc('month', f.order_date) as month,
        count(distinct f.order_id) as total_orders,
        sum(f.quantity) as total_units_sold,
        sum(f.price_unit * f.quantity) as total_revenue
    from fact f
    inner join product p on f.product_id = p.product_id
    group by cube(p.category, date_trunc('month', f.order_date))
    order by p.category nulls last, month nulls last
)

select
    coalesce(category, 'ALL CATEGORIES') as category,
    coalesce(cast(month as varchar), 'ALL MONTHS') as month,
    total_orders,
    total_units_sold,
    total_revenue
from final
