-- A flagged guest gets the quiet check-in script, never a celebratory milestone message.
select recommendation_id, player_id, talking_point
from {{ ref('fct_recognition_recommendations') }}
where recommendation_status = 'RG_CHECK_IN'
  and talking_point not like '%quiet spot to take a break%'
