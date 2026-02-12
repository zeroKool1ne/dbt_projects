{{
      config(
          alias='stg_order_product',
          materialized='view',
          tags=['hand_on']
      )
  }}

  with source as (
      select * from {{ source('ecommerce', 'order_product') }}
  ),

  renamed as (
      select
          order_product_id,
          order_id,
          product_id,
          quantity,
          price_unit
      from source
  )

  select * from renamed