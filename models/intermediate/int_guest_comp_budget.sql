{#- How much recognition has this guest already received? Drives cooldown suppression and the per-tier budget. -#}
with params as (
    select {{ gaming_today() }} as as_of_date
)

select
    m.player_id,
    sum(case when c.comp_date > {{ date_add('day', -1 * var('recognition_cooldown_days'), 'p.as_of_date') }}
             then c.comp_amount else 0 end) as comps_cooldown_usd,
    sum(case when c.comp_date > {{ date_add('day', -1 * var('guardrail_window_days'), 'p.as_of_date') }}
             then c.comp_amount else 0 end) as comps_window_usd,
    max(c.comp_date) as last_comp_date
from {{ ref('stg_loy__comp') }} c
join {{ ref('stg_loy__member') }} m on m.member_id = c.member_id
cross join params p
where c.comp_date <= p.as_of_date
group by 1
