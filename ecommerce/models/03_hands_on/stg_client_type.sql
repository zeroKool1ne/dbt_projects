{{
      config(
          alias='stg_client_type',
          materialized='view',
          tags=['hand_on']
      )
  }}

  with source as (
      select * from {{ source('ecommerce', 'client_type') }}
  ),

  renamed as (
      select
          client_type_id,
          type_name
      from source
  )

  select * from renamed