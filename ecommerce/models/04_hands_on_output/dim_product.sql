{{
      config(
          alias='dim_product',
          materialized='table',
          tags=['hand_on_output']
      )
  }}

  with product as (
      select * from {{ ref('stg_product') }}
  ),

  final as (
      select
          product_id,
          product_name,
          category,
          price
      from product
  )

  select * from final