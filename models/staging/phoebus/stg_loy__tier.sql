{% set rel = source('phoebus_loy', 'tier') %}

with src as (
    select {{ fv_cols(rel, ['tier_id', 'tier_name', 'tier_credits_required', 'point_multiplier']) }}
    from {{ rel }}
    where {{ fivetran_live(rel) }}
)

select * from src
