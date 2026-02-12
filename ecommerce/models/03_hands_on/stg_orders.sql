{{
      config(
          alias='stg_orders',
          materialized='view',
          tags=['hand_on']
      )
  }}

  with source as (
      select * from {{ source('ecommerce', 'orders') }}
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

