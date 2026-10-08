{% set rel = source('phoebus_loy', 'tier_history') %}

with src as (
    select {{ fv_cols(rel, ['tier_history_id', 'member_id', 'old_tier_id', 'new_tier_id', 'change_date', 'change_reason']) }}
    from {{ rel }}
    where {{ fivetran_live(rel) }}
)

select * from src
