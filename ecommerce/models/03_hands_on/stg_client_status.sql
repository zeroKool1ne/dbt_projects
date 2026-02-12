{{
      config(
          alias='stg_client_status',
          materialized='view',
          tags=['hand_on']
      )
  }}

  with source as (
      select * from {{ source('ecommerce', 'client_status') }}
  ),

  renamed as (
      select
          client_status_id,
          status_name
      from source
  )

  select * from renamed