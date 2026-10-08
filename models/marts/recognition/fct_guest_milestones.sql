{#-
  Every milestone a guest has ever crossed (calendar milestones: those near today).
  Generic by design: this model has NO knowledge of individual milestones - it joins the metric events to the
  rules seed. When a guest jumps several thresholds at once (e.g. $10K and $25K on the same day), only the
  highest one per milestone family is kept.
-#}
with crossed as (
    select
        e.player_id,
        e.event_date,
        e.metric_value as achieved_value,
        r.rule_id,
        r.milestone_family,
        r.milestone_name,
        r.metric_name,
        r.threshold,
        r.lead_days,
        r.recognition_window_days,
        r.reward_type,
        r.reward_budget_usd,
        r.action_owner,
        r.priority_weight,
        r.recommended_action,
        r.talking_point
    from {{ ref('int_guest_metric_events') }} e
    join {{ ref('loyalty_milestone_rules') }} r
      on r.metric_name = e.metric_name
     and r.is_active = 1
    where e.metric_value >= r.threshold
      and e.prior_value < r.threshold
),

ranked as (
    select
        *,
        row_number() over (
            partition by player_id, milestone_family, event_date
            order by threshold desc
        ) as threshold_rank
    from crossed
)

select
    {{ dbt_utils.generate_surrogate_key(['player_id', 'rule_id', 'event_date']) }} as milestone_id,
    player_id,
    rule_id,
    milestone_family,
    milestone_name,
    metric_name,
    threshold,
    achieved_value,
    event_date,
    lead_days,
    recognition_window_days,
    reward_type,
    reward_budget_usd,
    action_owner,
    priority_weight,
    recommended_action,
    talking_point
from ranked
where threshold_rank = 1
