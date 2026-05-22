{{
    config(
        materialized='table'
    )
}}

select
    date(cast(payment_ts as timestamp)) as payment_date,
    cast(payment_id as int64) as payment_id,
    cast(student_id as int64) as student_id,
    cast(payment_ts as timestamp) as payment_ts,
    cast(hours as int64) as hours,
    cast(price_per_hour_usd as numeric) as price_per_hour_usd
from {{ source('raw', 'payments') }}

