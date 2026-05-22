{{
    config(
        materialized='table'
    )
}}

select
    date(cast(join_ts as timestamp)) as join_date,
    cast(student_id as int64) as student_id,
    cast(join_ts as timestamp) as join_ts,
    country_code,
    acquisition_channel,
    persona,
    first_subject
from {{ source('raw', 'students') }}
