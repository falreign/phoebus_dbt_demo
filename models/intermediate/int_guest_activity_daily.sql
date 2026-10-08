{#-
  Grain: one row per guest (player_id) per gaming day with any activity.
  Three activity sources (gaming, dining, hotel) + jackpots are unioned onto ONE column list (var: activity_measures).
  The measure_cols macro zero-fills what a source does not provide, so each source only states what it knows.
-#}
{% set measures = var('activity_measures') %}

{% set gaming_expr = {
    'gaming_sessions': 'count(*)',
    'gaming_minutes':  'coalesce(sum(minutes_played), 0)',
    'theo_win':        'coalesce(sum(theoretical_win), 0)',
    'actual_win':      'coalesce(sum(actual_win), 0)',
    'cash_in':         'coalesce(sum(cash_in), 0)',
    'points_earned':   'coalesce(sum(points_awarded), 0)'
} %}
{% set dining_expr = {
    'dining_checks': 'count(*)',
    'dining_spend':  'coalesce(sum(c.subtotal), 0)'
} %}
{% set hotel_expr = {
    'hotel_stays':   'count(*)',
    'hotel_nights':  'coalesce(sum(nights), 0)',
    'hotel_revenue': 'coalesce(sum(case when is_comp then 0 else nights * nightly_rate end), 0)'
} %}
{% set jackpot_expr = {
    'jackpot_count':  'count(*)',
    'jackpot_amount': 'coalesce(sum(jackpot_amount), 0)'
} %}

with gaming as (
    select
        player_id,
        gaming_date as activity_date,
        {{ measure_cols(measures, gaming_expr) }}
    from {{ ref('stg_cms__player_session') }}
    group by 1, 2
),

dining as (   -- POS checks only count when the guest swiped their card (member_id present)
    select
        m.player_id,
        {{ to_gaming_date('c.closed_at') }} as activity_date,
        {{ measure_cols(measures, dining_expr) }}
    from {{ ref('stg_pos__check') }} c
    join {{ ref('stg_loy__member') }} m on m.member_id = c.member_id
    where c.check_status = 'Closed'
    group by 1, 2
),

hotel as (
    select
        player_id,
        arrival_date as activity_date,
        {{ measure_cols(measures, hotel_expr) }}
    from {{ ref('stg_hotel__reservation') }}
    where player_id is not null
      and reservation_status in ('InHouse', 'CheckedOut')
    group by 1, 2
),

jackpots as (
    select
        player_id,
        gaming_date as activity_date,
        {{ measure_cols(measures, jackpot_expr) }}
    from {{ ref('stg_cms__jackpot') }}
    group by 1, 2
),

unioned as (
    select * from gaming
    union all select * from dining
    union all select * from hotel
    union all select * from jackpots
),

daily as (
    select
        player_id,
        activity_date,
        {{ sum_measures(measures) }}
    from unioned
    group by 1, 2
)

select
    daily.*,
    case when gaming_sessions + dining_checks + hotel_stays > 0 then 1 else 0 end as visit_flag
from daily
