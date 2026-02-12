{{
    config(
        alias='mart_sales_by_client',
        materialized='table',
        tags=['hand_on_output']
    )
}}

with fact as (
    select * from {{ ref('fact_orders') }}
),

client as (
    select * from {{ ref('dim_client') }}
),

final as (
    select
        c.client_id,
        c.client_name,
        c.type_name as client_type,
        c.status_name as client_status,
        count(distinct f.order_id) as total_orders,
        sum(f.quantity) as total_units_sold,
        sum(f.price_unit * f.quantity) as total_revenue,
        min(f.order_date) as first_order_date,
        max(f.order_date) as last_order_date
    from fact f
    inner join client c on f.client_id = c.client_id
    group by 1, 2, 3, 4
    order by total_revenue desc
)

select * from final
