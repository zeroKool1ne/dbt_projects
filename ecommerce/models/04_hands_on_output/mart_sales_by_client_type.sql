{{
    config(
        alias='mart_sales_by_client_type',
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
        c.type_name as client_type,
        count(distinct c.client_id) as total_clients,
        count(distinct f.order_id) as total_orders,
        sum(f.price_unit * f.quantity) as total_revenue,
        round(sum(f.price_unit * f.quantity) / count(distinct c.client_id), 2) as revenue_per_client
    from fact f
    inner join client c on f.client_id = c.client_id
    group by 1
    order by total_revenue desc
)

select * from final
