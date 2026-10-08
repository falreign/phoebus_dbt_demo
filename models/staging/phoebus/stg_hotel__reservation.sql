{% set rel = source('phoebus_hotel', 'reservation') %}

with src as (
    select {{ fv_cols(rel, ['reservation_id', 'player_id', 'property_id', 'arrival_date', 'departure_date', 'nightly_rate', 'is_comp', 'reservation_status']) }}
    from {{ rel }}
    where {{ fivetran_live(rel) }}
)

select
    reservation_id, player_id, property_id, arrival_date, departure_date,
    {{ dbt.datediff('arrival_date', 'departure_date', 'day') }} as nights,   -- computed here: SQL Server computed columns are not relied on
    nightly_rate,
    coalesce(is_comp, false) as is_comp,
    reservation_status
from src
