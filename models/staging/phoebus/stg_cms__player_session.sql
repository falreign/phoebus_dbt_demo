{% set rel = source('phoebus_cms', 'player_session') %}

with src as (
    select {{ fv_cols(rel, ['session_id', 'player_id', 'property_id', 'game_category', 'gaming_date', 'start_time', 'end_time', 'minutes_played', 'cash_in', 'cash_out', 'coin_in_or_action', 'average_bet', 'theoretical_win', 'actual_win', 'points_awarded']) }}
    from {{ rel }}
    where {{ fivetran_live(rel) }}
)

select * from src   -- actual_win is casino perspective: positive = guest lost
