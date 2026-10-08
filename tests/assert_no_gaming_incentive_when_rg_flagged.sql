-- Responsible gaming: a flagged guest may only receive the check-in, never a gaming offer or reward value.
select recommendation_id, player_id, final_reward_type, approved_reward_usd
from {{ ref('fct_recognition_recommendations') }}
where rg_review_flag
  and (final_reward_type = 'GamingOffer' or approved_reward_usd > 0)
