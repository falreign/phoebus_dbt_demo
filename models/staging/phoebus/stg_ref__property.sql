{% set rel = source('phoebus_ref', 'property') %}

with src as (
    select {{ fv_cols(rel, ['property_id', 'property_code', 'property_name']) }}
    from {{ rel }}
    where {{ fivetran_live(rel) }}
)

select * from src
