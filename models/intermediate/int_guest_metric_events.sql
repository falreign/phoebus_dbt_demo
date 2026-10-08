{#-
  The single "long" table every milestone is evaluated against.
  Shape: (player_id, event_date, metric_name, metric_value, prior_value).
  A rule fires when metric_value >= threshold AND prior_value < threshold - i.e. the guest just crossed it.
  New cumulative metrics appear here automatically (var: cumulative_metrics); event metrics are added below.
-#}
with cumulative as (
    {{ unpivot_cumulative(ref('int_guest_cumulative_daily'), var('cumulative_metrics')) }}
),

streaks as (
    select
        player_id,
        first_visit_in_month as event_date,
        'consecutive_visit_months' as metric_name,
        cast(streak_months as {{ dbt.type_float() }}) as metric_value,
        cast(streak_months - 1 as {{ dbt.type_float() }}) as prior_value
    from {{ ref('int_guest_visit_streaks') }}
),

comebacks as (   -- prior_value = 0 means "every qualifying return fires", not just the first
    select
        player_id,
        activity_date as event_date,
        'days_since_prior_visit' as metric_name,
        cast({{ dbt.datediff('prior_activity_date', 'activity_date', 'day') }} as {{ dbt.type_float() }}) as metric_value,
        cast(0 as {{ dbt.type_float() }}) as prior_value
    from {{ ref('int_guest_cumulative_daily') }}
    where prior_activity_date is not null
      and visit_flag = 1
),

big_wins as (
    select
        player_id,
        activity_date as event_date,
        'daily_jackpot_total' as metric_name,
        cast(jackpot_amount as {{ dbt.type_float() }}) as metric_value,
        cast(0 as {{ dbt.type_float() }}) as prior_value
    from {{ ref('int_guest_activity_daily') }}
    where jackpot_amount > 0
),

tier_upgrades as (
    select
        m.player_id,
        th.change_date as event_date,
        'tier_level' as metric_name,
        cast(th.new_tier_id as {{ dbt.type_float() }}) as metric_value,
        cast(th.old_tier_id as {{ dbt.type_float() }}) as prior_value
    from {{ ref('stg_loy__tier_history') }} th
    join {{ ref('stg_loy__member') }} m on m.member_id = th.member_id
    where th.old_tier_id is not null           -- skips the initial 'Enrollment' row
      and th.new_tier_id > th.old_tier_id
),

calendar as (
    select * from {{ ref('int_guest_calendar_events') }}
)

select * from cumulative
union all select * from streaks
union all select * from comebacks
union all select * from big_wins
union all select * from tier_upgrades
union all select * from calendar
