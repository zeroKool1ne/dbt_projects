{{
      config(
          alias='dim_client',
          materialized='table',
          tags=['hand_on_output']
      )
  }}

  with client as (
      select * from {{ ref('stg_client') }}
  ),

  client_status as (
      select * from {{ ref('stg_client_status') }}
  ),

  client_type as (
      select * from {{ ref('stg_client_type') }}
  ),

  final as (
      select
          c.client_id,
          c.client_name,
          -- anonymized fields (GDPR / data governance)
          concat(left(c.email, 1), '***@', split_part(c.email, '@', 2)) as email,
          concat('(***) ***-', right(c.phone_number, 4)) as phone_number,
          concat(left(c.address, 3), '***') as address,
          ct.type_name,
          cs.status_name,
          c.registration_date
      from client c
      left join client_type ct on c.type_id = ct.client_type_id
      left join client_status cs on c.status_id = cs.client_status_id
  )

  select * from final
