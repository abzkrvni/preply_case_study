{{
    config(
        materialized='table'
    )
}}

select
    payment_id,
    payment_date,
    as_of_date,
    date_trunc(payment_date, year) as payment_year,
    date_trunc(payment_date, quarter) as payment_quarter,
    date_trunc(payment_date, month) as payment_month,
    'actual' as type,
    breakage_usd as revenue,
    country_code,
    acquisition_channel,
    persona,
    first_subject as subject_learned
from {{ ref('int_breakage_actual') }}

union all

select
    payment_id,
    payment_date,
    as_of_date,
    date_trunc(payment_date, year) as payment_year,
    date_trunc(payment_date, quarter) as payment_quarter,
    date_trunc(payment_date, month) as payment_month,
    'predicted' as type,
    estimated_breakage_usd as revenue,
    country_code,
    acquisition_channel,
    persona,
    first_subject as subject_learned
from {{ ref('int_breakage_estimated') }}
