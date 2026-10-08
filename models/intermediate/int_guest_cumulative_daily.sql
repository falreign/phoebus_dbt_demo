{#- Lifetime running totals per guest-day. Which metrics exist is driven by var('cumulative_metrics'). -#}
select
    a.*,
    {{ cumulative_cols(var('cumulative_metrics'), 'player_id', 'activity_date') }},
    lag(activity_date) over (partition by player_id order by activity_date) as prior_activity_date
from {{ ref('int_guest_activity_daily') }} a
