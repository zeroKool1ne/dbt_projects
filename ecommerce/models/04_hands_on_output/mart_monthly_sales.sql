{{
    config(
        alias='mart_monthly_sales',
        materialized='table',
        tags=['hand_on_output']
    )
}}

with fact as (
    select * from {{ ref('fact_orders') }}
),

final as (
    select
        date_trunc('month', order_date) as month,
        count(distinct order_id) as total_orders,
        sum(quantity) as total_units_sold,
        sum(price_unit * quantity) as total_revenue,
        round(sum(price_unit * quantity) / count(distinct order_id), 2) as avg_order_value
    from fact
    group by 1
    order by 1
)

select * from final
