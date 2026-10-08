{% set rel = source('phoebus_pos', 'check') %}

with src as (
    select {{ fv_cols(rel, ['check_id', 'outlet_id', 'member_id', 'opened_at', 'closed_at', 'guest_count', 'subtotal', 'total_amount', 'check_status']) }}
    from {{ rel }}
    where {{ fivetran_live(rel) }}
)

select * from src
