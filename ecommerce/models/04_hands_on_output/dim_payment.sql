{{
      config(
          alias='dim_payment',
          materialized='table',
          tags=['hand_on_output']
      )
  }}

  with payment as (
      select * from {{ ref('stg_payment_method') }}
  ),

  final as (
      select
          payment_id,
          payment_method
      from payment
  )

  select * from final
