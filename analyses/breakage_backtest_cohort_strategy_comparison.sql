{% set backtest_as_of = '2026-02-15' %}
{% set dataset_end = var('as_of_date', '2026-04-17') %}

with
payments_with_cycle as (
    select
        payment_id,
        student_id,
        payment_ts,
        hours as hours_purchased,
        price_per_hour_usd,
        payment_ts as cycle_start_ts,
        coalesce(
            lead(payment_ts) over (
                partition by student_id
                order by payment_ts, payment_id
            ),
            timestamp_add(payment_ts, interval 28 day)
        ) as cycle_end_ts
    from {{ ref('stg_payments') }}
),

closed_payment_cycles as (
    select
        p.payment_id,
        s.country_code,
        s.persona,
        s.acquisition_channel,
        p.hours_purchased,
        safe_divide(
            greatest(0, p.hours_purchased - coalesce(h.hours_booked_in_cycle, 0)),
            p.hours_purchased
        ) as pct_unbooked
    from payments_with_cycle as p
    inner join {{ ref('stg_students') }} as s using (student_id)
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
    where date(p.cycle_end_ts) <= date('{{ backtest_as_of }}')
        and p.hours_purchased > 0
),

specific_cohort_rates as (
    select
        country_code,
        persona,
        acquisition_channel,
        avg(pct_unbooked) as avg_pct_unbooked
    from closed_payment_cycles
    group by 1, 2, 3
),

generic_cohort_rates as (
    select
        country_code,
        avg(pct_unbooked) as avg_pct_unbooked
    from closed_payment_cycles
    group by 1
),

global_cohort_rate as (
    select avg(pct_unbooked) as avg_pct_unbooked
    from closed_payment_cycles
),

hours_booked_to_backtest as (
    select
        p.payment_id,
        sum(l.hours_booked) as hours_booked_to_as_of_date
    from payments_with_cycle as p
    inner join {{ ref('stg_lessons') }} as l
        on p.student_id = l.student_id
        and l.booking_ts >= p.cycle_start_ts
        and l.booking_ts < p.cycle_end_ts
        and date(l.booking_ts) <= date('{{ backtest_as_of }}')
    group by 1
),

hours_booked_final as (
    select
        p.payment_id,
        sum(l.hours_booked) as hours_booked_in_cycle
    from payments_with_cycle as p
    inner join {{ ref('stg_lessons') }} as l
        on p.student_id = l.student_id
        and l.booking_ts >= p.cycle_start_ts
        and l.booking_ts < p.cycle_end_ts
    group by 1
),

open_at_backtest as (
    select
        p.payment_id,
        p.hours_purchased,
        p.price_per_hour_usd,
        coalesce(hb.hours_booked_to_as_of_date, 0) as hours_booked_to_as_of_date,
        greatest(0, p.hours_purchased - coalesce(hb.hours_booked_to_as_of_date, 0)) as hours_remaining,
        s.country_code,
        s.persona,
        s.acquisition_channel
    from payments_with_cycle as p
    left join hours_booked_to_backtest as hb using (payment_id)
    inner join {{ ref('stg_students') }} as s using (student_id)
    where date(p.cycle_end_ts) > date('{{ backtest_as_of }}')
        and date(p.cycle_end_ts) <= date('{{ dataset_end }}')
),

actuals as (
    select
        p.payment_id,
        greatest(0, p.hours_purchased - coalesce(hf.hours_booked_in_cycle, 0))
            * p.price_per_hour_usd as actual_breakage_usd
    from payments_with_cycle as p
    left join hours_booked_final as hf using (payment_id)
),

payment_strategy_comparison as (
    select
        o.payment_id,
        date('{{ backtest_as_of }}') as backtest_as_of_date,
        a.actual_breakage_usd,
        case
            when safe_divide(o.hours_booked_to_as_of_date, o.hours_purchased)
                > (1 - coalesce(sc.avg_pct_unbooked, gc.avg_pct_unbooked, gr.avg_pct_unbooked))
                then greatest(0, o.hours_remaining) * o.price_per_hour_usd
            else greatest(0, o.hours_purchased)
                    * coalesce(sc.avg_pct_unbooked, gc.avg_pct_unbooked, gr.avg_pct_unbooked)
                    * o.price_per_hour_usd
        end as hierarchy_estimated_usd,
        case
            when safe_divide(o.hours_booked_to_as_of_date, o.hours_purchased)
                > (1 - coalesce(gc.avg_pct_unbooked, gr.avg_pct_unbooked))
                then greatest(0, o.hours_remaining) * o.price_per_hour_usd
            else greatest(0, o.hours_purchased)
                    * coalesce(gc.avg_pct_unbooked, gr.avg_pct_unbooked)
                    * o.price_per_hour_usd
        end as generic_only_estimated_usd,
        case
            when safe_divide(o.hours_booked_to_as_of_date, o.hours_purchased)
                > (1 - gr.avg_pct_unbooked)
                then greatest(0, o.hours_remaining) * o.price_per_hour_usd
            else greatest(0, o.hours_purchased) * gr.avg_pct_unbooked * o.price_per_hour_usd
        end as global_only_estimated_usd
    from open_at_backtest as o
    inner join actuals as a using (payment_id)
    left join specific_cohort_rates as sc
        on o.country_code = sc.country_code
        and o.persona = sc.persona
        and o.acquisition_channel = sc.acquisition_channel
    left join generic_cohort_rates as gc
        on o.country_code = gc.country_code
    cross join global_cohort_rate as gr
),

strategy_rows as (
    select
        backtest_as_of_date,
        payment_id,
        actual_breakage_usd,
        s.cohort_strategy,
        s.estimated_usd,
        s.estimated_usd - actual_breakage_usd as error_usd,
        abs(s.estimated_usd - actual_breakage_usd) as abs_error_usd
    from payment_strategy_comparison
    cross join unnest([
        struct('hierarchy' as cohort_strategy, hierarchy_estimated_usd as estimated_usd),
        struct('generic_only', generic_only_estimated_usd),
        struct('global_only', global_only_estimated_usd)
    ]) as s
)

select
    backtest_as_of_date,
    cohort_strategy,
    count(*) as payment_count,
    round(sum(estimated_usd), 2) as total_estimated_usd,
    round(sum(actual_breakage_usd), 2) as total_actual_usd,
    round(sum(error_usd), 2) as total_error_usd,
    round(avg(error_usd), 2) as mean_error_usd,
    round(avg(abs_error_usd), 2) as mae_usd,
    round(safe_divide(sum(abs_error_usd), nullif(sum(actual_breakage_usd), 0)), 4) as wape,
    countif(error_usd > 0) as overestimate_count,
    countif(error_usd < 0) as underestimate_count
from strategy_rows
group by 1, 2
order by wape
