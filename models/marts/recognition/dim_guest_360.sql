{#- One row per guest: who they are, their lifetime value, tier, preferences, and where they are right now. -#}
with params as (
    select {{ gaming_today() }} as as_of_date
),

players as (select * from {{ ref('stg_cms__player') }}),
members as (select * from {{ ref('stg_loy__member') }}),
tiers   as (select * from {{ ref('stg_loy__tier') }}),
props   as (select * from {{ ref('stg_ref__property') }}),

latest_lifetime as (        -- most recent cumulative snapshot per guest
    select * from (
        select
            c.*,
            row_number() over (partition by player_id order by activity_date desc) as rn
        from {{ ref('int_guest_cumulative_daily') }} c
        cross join params p
        where c.activity_date <= p.as_of_date
    ) x
    where rn = 1
),

first_visit as (
    select player_id, min(activity_date) as first_visit_date
    from {{ ref('int_guest_activity_daily') }}
    where visit_flag = 1
    group by 1
),

trailing_12m as (
    select
        a.player_id,
        sum(a.theo_win) as theo_win_12m,
        sum(a.visit_flag) as visit_days_12m
    from {{ ref('int_guest_activity_daily') }} a
    cross join params p
    where a.activity_date <= p.as_of_date
      and a.activity_date > {{ date_add('day', -365, 'p.as_of_date') }}
    group by 1
),

fav_game as (
    select player_id, game_category as favorite_game_category
    from (
        select
            s.player_id,
            s.game_category,
            row_number() over (partition by s.player_id order by sum(s.minutes_played) desc) as rn
        from {{ ref('stg_cms__player_session') }} s
        cross join params p
        where s.gaming_date <= p.as_of_date
          and s.gaming_date > {{ date_add('day', -365, 'p.as_of_date') }}
        group by s.player_id, s.game_category
    ) x
    where rn = 1
),

fav_outlet as (
    select player_id, favorite_outlet_name, favorite_outlet_type
    from (
        select
            m.player_id,
            o.outlet_name as favorite_outlet_name,
            o.outlet_type as favorite_outlet_type,
            row_number() over (partition by m.player_id order by sum(c.subtotal) desc) as rn
        from {{ ref('stg_pos__check') }} c
        join {{ ref('stg_loy__member') }} m on m.member_id = c.member_id
        join {{ ref('stg_pos__outlet') }} o on o.outlet_id = c.outlet_id
        where c.check_status = 'Closed'
        group by m.player_id, o.outlet_name, o.outlet_type
    ) x
    where rn = 1
),

active_today as (
    select player_id, 1 as on_property_today
    from {{ ref('int_guest_activity_daily') }} a
    cross join params p
    where a.activity_date = p.as_of_date and a.visit_flag = 1
),

property_today as (         -- where the guest is gaming right now
    select player_id, property_id
    from (
        select
            s.player_id,
            s.property_id,
            row_number() over (partition by s.player_id order by s.end_time desc) as rn
        from {{ ref('stg_cms__player_session') }} s
        cross join params p
        where s.gaming_date = p.as_of_date
    ) x
    where rn = 1
),

in_house as (               -- hotel guests staying tonight
    select player_id, property_id
    from (
        select
            r.player_id,
            r.property_id,
            row_number() over (partition by r.player_id order by r.arrival_date desc) as rn
        from {{ ref('stg_hotel__reservation') }} r
        cross join params p
        where r.player_id is not null
          and r.reservation_status in ('InHouse', 'CheckedOut')
          and r.arrival_date <= p.as_of_date
          and r.departure_date > p.as_of_date
    ) x
    where rn = 1
),

joined as (
    select
        p.player_id,
        m.member_id,
        m.member_number,
        p.first_name,
        p.last_name,
        p.full_name,
        {{ age_on('p.date_of_birth', 'pr.as_of_date') }} as age_years,
        p.is_vip,
        p.player_status,
        m.member_status,
        m.enroll_date,
        {{ age_on('m.enroll_date', 'pr.as_of_date') }} as member_years,
        m.tier_id,
        t.tier_name,
        m.points_balance,
        m.email_opt_in,
        m.sms_opt_in,

        p.home_property_id,
        hp.property_name as home_property_name,
        coalesce(pt.property_id, ih.property_id, p.home_property_id) as current_property_id,

        fv.first_visit_date,
        ll.activity_date as last_visit_date,
        {{ dbt.datediff('ll.activity_date', 'pr.as_of_date', 'day') }} as days_since_last_visit,

        {% for metric in var('cumulative_metrics') -%}
        coalesce(ll.cum_{{ metric }}, 0) as {{ metric }},
        {% endfor %}
        coalesce(t12.theo_win_12m, 0) as theo_win_12m,
        coalesce(t12.visit_days_12m, 0) as visit_days_12m,

        fg.favorite_game_category,
        fo.favorite_outlet_name,
        fo.favorite_outlet_type,

        case when act.player_id is not null then true else false end as on_property_today,
        case when ih.player_id is not null then true else false end as in_house_tonight,
        pr.as_of_date
    from players p
    cross join params pr
    left join members m        on m.player_id = p.player_id
    left join tiers t          on t.tier_id = m.tier_id
    left join props hp         on hp.property_id = p.home_property_id
    left join latest_lifetime ll on ll.player_id = p.player_id
    left join first_visit fv   on fv.player_id = p.player_id
    left join trailing_12m t12 on t12.player_id = p.player_id
    left join fav_game fg      on fg.player_id = p.player_id
    left join fav_outlet fo    on fo.player_id = p.player_id
    left join active_today act on act.player_id = p.player_id
    left join property_today pt on pt.player_id = p.player_id
    left join in_house ih      on ih.player_id = p.player_id
)

select
    j.*,
    cp.property_name as current_property_name,
    -- ---- eligibility: who may receive recognition at all --------------------------------------------------------
    case
        when j.member_id is null                               then 'not a loyalty member'
        when j.player_status <> 'Active'                       then 'player status: ' || j.player_status   -- excludes self-excluded / banned
        when j.member_status <> 'Active'                       then 'member status: ' || j.member_status
        when j.age_years < {{ var('min_gaming_age') }}         then 'under minimum age'
    end as ineligible_reason,
    case
        when j.member_id is not null
         and j.player_status = 'Active'
         and j.member_status = 'Active'
         and j.age_years >= {{ var('min_gaming_age') }}
        then true else false
    end as is_eligible
from joined j
left join props cp on cp.property_id = j.current_property_id
