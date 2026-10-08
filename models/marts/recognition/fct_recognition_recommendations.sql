{#-
  Prescriptive layer. For TODAY, every milestone that is actionable (inside its window) is scored and given a status:

    RECOMMEND            go ahead - action, owner, approved reward and talking point are ready
    RG_CHECK_IN          responsible-gaming signals present: host check-in only, NO gaming incentives
    SUPPRESSED_COOLDOWN  guest was recently comped/recognized (unless the milestone is high priority)
    SUPPRESSED_BUDGET    per-tier 30-day recognition budget is used up
    INELIGIBLE           not an active loyalty member / self-excluded / banned / under age
-#}
with params as (
    select {{ gaming_today() }} as as_of_date
),

actionable as (
    select
        m.*,
        p.as_of_date,
        {{ dbt.datediff('m.event_date', 'p.as_of_date', 'day') }} as days_since_event
    from {{ ref('fct_guest_milestones') }} m
    cross join params p
    where m.event_date >= {{ date_add('day', '-1 * m.recognition_window_days', 'p.as_of_date') }}
      and m.event_date <= {{ date_add('day', 'm.lead_days', 'p.as_of_date') }}
),

enriched as (
    select
        a.*,
        g.first_name,
        g.last_name,
        g.full_name,
        g.tier_id,
        g.tier_name,
        g.is_vip,
        g.is_eligible,
        g.ineligible_reason,
        g.on_property_today,
        g.in_house_tonight,
        g.current_property_id,
        g.current_property_name,
        g.favorite_outlet_name,
        g.favorite_game_category,
        g.visit_days_12m,
        g.lifetime_theo_win,
        g.lifetime_visit_days,
        g.member_years,
        coalesce(rg.rg_review_flag, false) as rg_review_flag,
        rg.rg_reason,
        coalesce(cb.comps_cooldown_usd, 0) as comps_cooldown_usd,
        coalesce(cb.comps_window_usd, 0) as comps_window_usd,
        coalesce(gr.max_reward_usd_30d, {{ var('default_30d_budget_usd') }}) as tier_budget_30d_usd
    from actionable a
    join {{ ref('dim_guest_360') }} g          on g.player_id = a.player_id
    left join {{ ref('int_guest_rg_signals') }} rg on rg.player_id = a.player_id
    left join {{ ref('int_guest_comp_budget') }} cb on cb.player_id = a.player_id
    left join {{ ref('recognition_budget_guardrails') }} gr on gr.tier_id = g.tier_id
),

scored as (
    select
        *,
        {{ priority_score('priority_weight', 'coalesce(tier_id, 1)', 'days_since_event', 'on_property_today or in_house_tonight', 'is_vip') }}
            as priority_score,
        tier_budget_30d_usd - comps_window_usd as remaining_budget_usd
    from enriched
),

statused as (
    select
        *,
        case
            when not is_eligible then 'INELIGIBLE'
            when rg_review_flag then 'RG_CHECK_IN'
            when comps_cooldown_usd >= {{ var('recognition_cooldown_min_usd') }}
             and priority_score < {{ var('cooldown_override_priority') }} then 'SUPPRESSED_COOLDOWN'
            when reward_budget_usd > 0 and remaining_budget_usd <= 0 then 'SUPPRESSED_BUDGET'
            else 'RECOMMEND'
        end as recommendation_status
    from scored
)

select
    milestone_id as recommendation_id,
    as_of_date,
    player_id,
    first_name,
    last_name,
    full_name,
    tier_id,
    tier_name,
    is_vip,
    current_property_id,
    current_property_name,
    on_property_today,
    in_house_tonight,

    rule_id,
    milestone_family,
    milestone_name,
    achieved_value,
    event_date,
    days_since_event,
    {{ date_add('day', 'recognition_window_days', 'event_date') }} as actionable_through,

    recommendation_status,
    rg_review_flag,
    rg_reason,
    round(priority_score, 1) as priority_score,

    -- ---- the prescriptive part --------------------------------------------------------------------------------------
    case when recommendation_status = 'RG_CHECK_IN' then '{{ var("rg_check_in_action") | replace("'", "''") }}'
         else recommended_action end as final_action,
    case when recommendation_status = 'RG_CHECK_IN' then 'PersonalNote' else reward_type end as final_reward_type,
    case when recommendation_status = 'RECOMMEND'
         then greatest(least(reward_budget_usd, remaining_budget_usd), 0) else 0 end as approved_reward_usd,
    action_owner,
    case when recommendation_status = 'RG_CHECK_IN'
         then replace('{{ var("rg_talking_point") | replace("'", "''") }}', '{first_name}', first_name)
         else {{ render_talking_point('talking_point', 'first_name', 'achieved_value') }}
    end as talking_point,

    -- ---- context a host would want to glance at ---------------------------------------------------------------------
    favorite_outlet_name,
    favorite_game_category,
    visit_days_12m,
    lifetime_visit_days,
    lifetime_theo_win,
    member_years,
    comps_cooldown_usd,
    comps_window_usd,
    remaining_budget_usd
from statused
