{#- Guest identity. Sensitive fields (SSN, ID numbers, address, email, phone) are deliberately NOT carried forward. -#}
{% set rel = source('phoebus_cms', 'player') %}

with src as (
    select {{ fv_cols(rel, ['player_id', 'first_name', 'last_name', 'date_of_birth', 'home_property_id', 'player_status', 'vip_flag', 'created_at']) }}
    from {{ rel }}
    where {{ fivetran_live(rel) }}
)

select
    player_id,
    first_name,
    last_name,
    first_name || ' ' || last_name as full_name,
    date_of_birth,
    home_property_id,
    player_status,
    coalesce(vip_flag, false) as is_vip,
    created_at
from src
