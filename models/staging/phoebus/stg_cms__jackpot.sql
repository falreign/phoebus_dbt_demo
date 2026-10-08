{% set rel = source('phoebus_cms', 'jackpot') %}

with src as (
    select {{ fv_cols(rel, ['jackpot_id', 'asset_id', 'player_id', 'jackpot_date_time', 'amount', 'jackpot_type']) }}
    from {{ rel }}
    where {{ fivetran_live(rel) }}
)

select
    jackpot_id,
    asset_id,
    player_id,
    jackpot_date_time as jackpot_at,
    {{ to_gaming_date('jackpot_date_time') }} as gaming_date,
    amount as jackpot_amount,
    jackpot_type
from src
where player_id is not null
