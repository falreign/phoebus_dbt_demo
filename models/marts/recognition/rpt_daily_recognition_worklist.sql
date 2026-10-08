{#-
  What a host sees. One row per guest (their best recommendation), ranked per property, with any other
  milestones folded into one text column. Responsible-gaming check-ins sort above celebrations.
-#}
with recs as (
    select *
    from {{ ref('fct_recognition_recommendations') }}
    where recommendation_status in ('RECOMMEND', 'RG_CHECK_IN')
),

per_guest as (
    select
        *,
        row_number() over (
            partition by player_id
            order by case when recommendation_status = 'RG_CHECK_IN' then 0 else 1 end, priority_score desc
        ) as guest_rank
    from recs
),

others as (
    select
        player_id,
        {{ dbt.listagg('milestone_name', "', '", 'order by priority_score desc') }} as other_milestones
    from per_guest
    where guest_rank > 1
    group by 1
),

headline as (
    select p.*, o.other_milestones
    from per_guest p
    left join others o on o.player_id = p.player_id
    where p.guest_rank = 1
),

ranked as (
    select
        *,
        row_number() over (
            partition by current_property_id
            order by case when recommendation_status = 'RG_CHECK_IN' then 0 else 1 end, priority_score desc
        ) as worklist_rank
    from headline
)

select
    as_of_date,
    current_property_id as property_id,
    current_property_name as property_name,
    worklist_rank,
    recommendation_id,
    player_id,
    full_name as guest_name,
    tier_name,
    case when in_house_tonight then 'In house tonight'
         when on_property_today then 'On property today'
         else 'Not on property yet' end as presence,
    recommendation_status,
    rg_reason,
    milestone_name as headline_milestone,
    final_action as recommended_action,
    action_owner,
    final_reward_type as reward_type,
    approved_reward_usd,
    talking_point,
    other_milestones,
    actionable_through,
    priority_score,
    'Member ' || cast(member_years as {{ dbt.type_string() }}) || ' yrs - '
      || cast(lifetime_visit_days as {{ dbt.type_string() }}) || ' visits - '
      || coalesce('favorite spot: ' || favorite_outlet_name, 'favorite spot: n/a') as guest_context
from ranked
where worklist_rank <= {{ var('worklist_size_per_property') }}
