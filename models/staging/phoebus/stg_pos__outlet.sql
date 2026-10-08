{% set rel = source('phoebus_pos', 'outlet') %}

with src as (
    select {{ fv_cols(rel, ['outlet_id', 'property_id', 'outlet_name', 'outlet_type']) }}
    from {{ rel }}
    where {{ fivetran_live(rel) }}
)

select * from src
