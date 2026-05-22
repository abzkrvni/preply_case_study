{{
    config(
        materialized='table'
    )
}}

select
    date(cast(booking_ts as timestamp)) as booking_date,
    cast(lesson_id as int64) as lesson_id,
    cast(student_id as int64) as student_id,
    cast(booking_ts as timestamp) as booking_ts,
    cast(hours_booked as numeric) as hours_booked
from {{ source('raw', 'lessons') }}
