{{
    config(
        alias='mart_cube_payment_status',
        materialized='table',
        tags=['hand_on_output']
    )
}}

with fact as (
    select * from {{ ref('fact_orders') }}
),

payment as (
    select * from {{ ref('dim_payment') }}
),

final as (
    select
        pm.payment_method,
        f.status as order_status,
        count(distinct f.order_id) as total_orders,
        sum(f.quantity) as total_units_sold,
        sum(f.price_unit * f.quantity) as total_revenue
    from fact f
    inner join payment pm on f.payment_id = pm.payment_id
    group by cube(pm.payment_method, f.status)
    order by pm.payment_method nulls last, f.status nulls last
)

select
    coalesce(payment_method, 'ALL METHODS') as payment_method,
    coalesce(order_status, 'ALL STATUSES') as order_status,
    total_orders,
    total_units_sold,
    total_revenue
from final
