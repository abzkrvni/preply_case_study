{{ config(
    meta={'as_of_date': '2026-04-17'}
) }}

{% set as_of_date = var('as_of_date', config.get('meta', {}).get('as_of_date', '2026-04-17')) %}

with
{{ payments_with_cycle_cte() }},

hours_booked as (
    select
        p.payment_id,
        sum(l.hours_booked) as hours_booked_in_cycle
    from payments_with_cycle as p
    inner join {{ ref('stg_lessons') }} as l
        on p.student_id = l.student_id
        and l.booking_ts >= p.cycle_start_ts
        and l.booking_ts < p.cycle_end_ts
    group by p.payment_id
)

select
    p.payment_id,
    p.student_id,
    p.payment_date,
    date(p.cycle_start_ts) as cycle_start_date,
    date(p.cycle_end_ts) as cycle_end_date,
    date('{{ as_of_date }}') as as_of_date,
    p.hours_purchased,
    coalesce(h.hours_booked_in_cycle, 0) as hours_booked_in_cycle,
    greatest(0, p.hours_purchased - coalesce(h.hours_booked_in_cycle, 0)) as hours_unbooked,
    p.price_per_hour_usd,
    greatest(0, p.hours_purchased - coalesce(h.hours_booked_in_cycle, 0))
        * p.price_per_hour_usd as breakage_usd,
    s.country_code,
    s.acquisition_channel,
    s.persona,
    s.first_subject
from payments_with_cycle as p
left join hours_booked as h using (payment_id)
left join {{ ref('stg_students') }} as s using (student_id)
where date(p.cycle_end_ts) <= date('{{ as_of_date }}')
