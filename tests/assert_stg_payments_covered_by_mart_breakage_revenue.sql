-- Fails if any staged payment is missing from the PayOps mart.
-- Complements unique on mart.payment_id (at-most-one) with full coverage (at-least-one).

select
    p.payment_id,
    p.student_id,
    p.payment_date
from {{ ref('stg_payments') }} as p
left join {{ ref('mart_breakage_revenue') }} as m
    on p.payment_id = m.payment_id
where m.payment_id is null
