{% set rel = source('phoebus_loy', 'comp') %}

with src as (
    select {{ fv_cols(rel, ['comp_id', 'member_id', 'property_id', 'comp_date_time', 'comp_category', 'comp_amount', 'authorized_by_employee_id']) }}
    from {{ rel }}
    where {{ fivetran_live(rel) }}
)

select
    comp_id, member_id, property_id,
    comp_date_time as comp_at,
    cast(comp_date_time as date) as comp_date,
    comp_category, comp_amount, authorized_by_employee_id
from src
