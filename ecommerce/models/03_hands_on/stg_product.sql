{{
      config(
          alias='stg_product',
          materialized='view',
          tags=['hand_on']
      )
  }}

  with source as (
      select * from {{ source('ecommerce', 'product') }}
  ),

  renamed as (
      select
          product_id,
          product_name,
          category,
          price
      from source
  )

  select * from renamed