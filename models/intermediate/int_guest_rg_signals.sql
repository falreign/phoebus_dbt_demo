{#-
  Responsible-gaming guardrail. Looks at the last few gaming days and flags guests whose play looks unusual
  relative to their OWN history. Flagged guests are never offered gaming incentives; the host gets a
  check-in prompt instead (see fct_recognition_recommendations).
-#}
with params as (
    select {{ gaming_today() }} as as_of_date
),

recent as (
    select
        a.player_id,
        sum(a.actual_win) as recent_loss_usd,          -- casino perspective: positive = guest lost
        sum(a.gaming_minutes) as recent_minutes,
        max(a.gaming_minutes) as max_minutes_in_a_day
    from {{ ref('int_guest_activity_daily') }} a
    cross join params p
    where a.activity_date <= p.as_of_date
      and a.activity_date > {{ date_add('day', -1 * var('rg_lookback_days'), 'p.as_of_date') }}
    group by 1
),

baseline as (
    select
        a.player_id,
        avg(a.actual_win) as avg_daily_loss_90d
    from {{ ref('int_guest_activity_daily') }} a
    cross join params p
    where a.gaming_sessions > 0
      and a.activity_date <= {{ date_add('day', -1 * var('rg_lookback_days'), 'p.as_of_date') }}
      and a.activity_date > {{ date_add('day', -90, 'p.as_of_date') }}
    group by 1
)

select
    r.player_id,
    r.recent_loss_usd,
    r.max_minutes_in_a_day,
    b.avg_daily_loss_90d,
    case
        when r.max_minutes_in_a_day >= {{ var('rg_max_minutes_per_day') }}
            then true
        when r.recent_loss_usd >= {{ var('rg_min_daily_loss_usd') }}
         and r.recent_loss_usd >= {{ var('rg_loss_multiple_of_avg') }} * greatest(coalesce(b.avg_daily_loss_90d, 0), 1)
            then true
        else false
    end as rg_review_flag,
    case
        when r.max_minutes_in_a_day >= {{ var('rg_max_minutes_per_day') }} then 'extended play time'
        when r.recent_loss_usd >= {{ var('rg_min_daily_loss_usd') }}
         and r.recent_loss_usd >= {{ var('rg_loss_multiple_of_avg') }} * greatest(coalesce(b.avg_daily_loss_90d, 0), 1)
            then 'losses well above guest norm'
    end as rg_reason
from recent r
left join baseline b on b.player_id = r.player_id
