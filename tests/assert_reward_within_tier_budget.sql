select recommendation_id, player_id, approved_reward_usd, remaining_budget_usd
from {{ ref('fct_recognition_recommendations') }}
where approved_reward_usd > greatest(remaining_budget_usd, 0)
