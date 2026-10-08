-- Self-excluded, banned, inactive or under-age guests must never reach a host's worklist.
select w.player_id, g.ineligible_reason
from {{ ref('rpt_daily_recognition_worklist') }} w
join {{ ref('dim_guest_360') }} g on g.player_id = w.player_id
where not g.is_eligible
