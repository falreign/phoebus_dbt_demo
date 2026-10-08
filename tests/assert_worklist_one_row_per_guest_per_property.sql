select property_id, player_id, count(*) as n
from {{ ref('rpt_daily_recognition_worklist') }}
group by 1, 2
having count(*) > 1
