{{
      config(
          alias='fact_orders',
          materialized='table',
          tags=['hand_on_output']
      )
  }}

  with orders as (
      select * from {{ ref('stg_orders') }}
  ),

  order_product as (
      select * from {{ ref('stg_order_product') }}
  ),

  final as (
      select
          op.order_product_id,
          o.order_id,
          o.client_id,
          op.product_id,
          o.payment_id,
          o.order_date,
          o.status,
          op.quantity,
          op.price_unit,
          o.total_amount
      from orders o
      inner join order_product op on o.order_id = op.order_id
  )

  select * from final
