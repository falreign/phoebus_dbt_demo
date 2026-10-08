{% set rel = source('phoebus_loy', 'member') %}

with src as (
    select {{ fv_cols(rel, ['member_id', 'player_id', 'member_number', 'tier_id', 'enroll_date', 'enroll_property_id', 'points_balance', 'tier_credits_ytd', 'member_status', 'last_activity_date', 'email_opt_in', 'sms_opt_in']) }}
    from {{ rel }}
    where {{ fivetran_live(rel) }}
)

select
    member_id, player_id, member_number, tier_id, enroll_date, enroll_property_id,
    points_balance, tier_credits_ytd, member_status, last_activity_date,
    coalesce(email_opt_in, false) as email_opt_in,
    coalesce(sms_opt_in, false) as sms_opt_in
from src
