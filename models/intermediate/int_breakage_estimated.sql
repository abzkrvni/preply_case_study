{{ config(
    meta={'as_of_date': '2026-04-17'}
) }}

{% set as_of_date = var('as_of_date', config.get('meta', {}).get('as_of_date', '2026-04-17')) %}

with
{{ payments_with_cycle_cte() }},

closed_payment_cycles as (
    select
        p.payment_id,
        p.hours_purchased,
        greatest(0, p.hours_purchased - coalesce(h.hours_booked_in_cycle, 0)) as hours_unbooked,
        safe_divide(
            greatest(0, p.hours_purchased - coalesce(h.hours_booked_in_cycle, 0)),
            p.hours_purchased
        ) as pct_unbooked
    from payments_with_cycle as p
    left join (
        select
            p2.payment_id,
            sum(l.hours_booked) as hours_booked_in_cycle
        from payments_with_cycle as p2
        inner join {{ ref('stg_lessons') }} as l
            on p2.student_id = l.student_id
            and l.booking_ts >= p2.cycle_start_ts
            and l.booking_ts < p2.cycle_end_ts
        group by 1
    ) as h using (payment_id)
    where date(p.cycle_end_ts) <= date('{{ as_of_date }}')
        and p.hours_purchased > 0
),

global_cohort_rate as (
    select avg(pct_unbooked) as avg_pct_unbooked
    from closed_payment_cycles
),

hours_booked_to_as_of as (
    select
        p.payment_id,
        sum(l.hours_booked) as hours_booked_to_as_of_date
    from payments_with_cycle as p
    inner join {{ ref('stg_lessons') }} as l
        on p.student_id = l.student_id
        and l.booking_ts >= p.cycle_start_ts
        and l.booking_ts < p.cycle_end_ts
        and date(l.booking_ts) <= date('{{ as_of_date }}')
    group by 1
),

open_payments as (
    select
        p.payment_id,
        p.student_id,
        p.payment_date,
        p.hours_purchased,
        p.price_per_hour_usd,
        p.cycle_start_ts,
        p.cycle_end_ts,
        coalesce(h.hours_booked_to_as_of_date, 0) as hours_booked_to_as_of_date,
        greatest(0, p.hours_purchased - coalesce(h.hours_booked_to_as_of_date, 0)) as hours_remaining,
        s.country_code,
        s.acquisition_channel,
        s.persona,
        s.first_subject
    from payments_with_cycle as p
    left join hours_booked_to_as_of as h using (payment_id)
    inner join {{ ref('stg_students') }} as s using (student_id)
    where date(p.cycle_end_ts) > date('{{ as_of_date }}')
),

open_with_estimates as (
    select
        o.payment_id,
        o.student_id,
        o.payment_date,
        o.cycle_start_ts,
        o.cycle_end_ts,
        o.hours_purchased,
        o.hours_booked_to_as_of_date,
        o.hours_remaining,
        o.price_per_hour_usd,
        o.country_code,
        o.acquisition_channel,
        o.persona,
        o.first_subject,
        gr.avg_pct_unbooked,
        safe_divide(o.hours_booked_to_as_of_date, o.hours_purchased) as utilization_pct,
        case
            when safe_divide(o.hours_booked_to_as_of_date, o.hours_purchased)
                > (1 - gr.avg_pct_unbooked)
                then 'remaining_hours'
            else 'global_rate'
        end as estimation_method,
        case
            when safe_divide(o.hours_booked_to_as_of_date, o.hours_purchased)
                > (1 - gr.avg_pct_unbooked)
                then greatest(0, o.hours_remaining)
            else greatest(0, o.hours_purchased) * gr.avg_pct_unbooked
        end as estimated_unbooked_hours,
        case
            when safe_divide(o.hours_booked_to_as_of_date, o.hours_purchased)
                > (1 - gr.avg_pct_unbooked)
                then greatest(0, o.hours_remaining) * o.price_per_hour_usd
            else greatest(0, o.hours_purchased) * gr.avg_pct_unbooked * o.price_per_hour_usd
        end as estimated_breakage_usd
    from open_payments as o
    cross join global_cohort_rate as gr
)

select
    payment_id,
    student_id,
    payment_date,
    date(cycle_start_ts) as cycle_start_date,
    date(cycle_end_ts) as cycle_end_date,
    date('{{ as_of_date }}') as as_of_date,
    greatest(0, date_diff(date('{{ as_of_date }}'), date(cycle_start_ts), day)) as days_into_cycle,
    greatest(0, date_diff(date(cycle_end_ts), date('{{ as_of_date }}'), day)) as days_remaining,
    hours_purchased,
    hours_booked_to_as_of_date,
    hours_remaining,
    price_per_hour_usd,
    utilization_pct,
    1 - avg_pct_unbooked as expected_booking_pct,
    utilization_pct > (1 - avg_pct_unbooked) as is_above_booking_pace,
    estimation_method,
    estimated_breakage_usd,
    estimated_unbooked_hours,
    country_code,
    acquisition_channel,
    persona,
    first_subject
from open_with_estimates
