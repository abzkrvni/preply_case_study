{% macro payments_with_cycle_cte() %}
payments_with_cycle as (
    select
        payment_id,
        student_id,
        payment_date,
        payment_ts,
        hours as hours_purchased,
        price_per_hour_usd,
        payment_ts as cycle_start_ts,
        coalesce(
            lead(payment_ts) over (
                partition by student_id
                order by payment_ts, payment_id
            ),
            timestamp_add(payment_ts, interval 28 day) -- guardrail for last payment
        ) as cycle_end_ts
    from {{ ref('stg_payments') }}
)
{% endmacro %}
