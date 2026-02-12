{{
      config(
          alias='stg_payment_method',
          materialized='view',
          tags=['hand_on']
      )
  }}

  with source as (
      select * from {{ source('ecommerce', 'payment_method') }}
  ),

  renamed as (
      select
          payment_id,
          payment_method
      from source
  )

  select * from renamed