{{
      config(
          alias='stg_client',
          materialized='view',
          tags=['hand_on']
      )
  }}

  with source as (
      select * from {{ source('ecommerce', 'client') }}
  ),

  renamed as (
      select
          client_id,
          client_name,
          email,
          phone_number,
          address,
          type_id,
          status_id,
          registration_date
      from source
  )

  select * from renamed
