{{
    config(
        alias='mart_sales_by_category',
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
        count(distinct f.order_id) as total_orders,
        sum(f.quantity) as total_units_sold,
        sum(f.price_unit * f.quantity) as total_revenue,
        round(sum(f.price_unit * f.quantity) / sum(f.quantity), 2) as avg_price_per_unit
    from fact f
    inner join product p on f.product_id = p.product_id
    group by 1
    order by total_revenue desc
)

select * from final
