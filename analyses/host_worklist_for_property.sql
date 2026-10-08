-- Example: tonight's list for one property, as a host would read it.
select worklist_rank, guest_name, tier_name, presence, headline_milestone,
       recommended_action, action_owner, approved_reward_usd, talking_point, other_milestones
from {{ ref('rpt_daily_recognition_worklist') }}
where property_name = 'Phoebus Grand Las Vegas'
order by worklist_rank
