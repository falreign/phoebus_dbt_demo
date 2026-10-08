{#- Consecutive calendar months with at least one visit (gaps-and-islands). Grain: guest x visit month. -#}
with visit_months as (
    select
        player_id,
        {{ dbt.date_trunc('month', 'activity_date') }} as visit_month,
        min(activity_date) as first_visit_in_month
    from {{ ref('int_guest_activity_daily') }}
    where visit_flag = 1
    group by 1, 2
),

indexed as (
    select
        *,
        extract(year from visit_month) * 12 + extract(month from visit_month) as month_index
    from visit_months
),

islands as (
    select
        *,
        month_index - row_number() over (partition by player_id order by visit_month) as island_id
    from indexed
)

select
    player_id,
    visit_month,
    first_visit_in_month,
    row_number() over (partition by player_id, island_id order by visit_month) as streak_months
from islands
