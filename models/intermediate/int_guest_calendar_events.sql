{#-
  Forward-looking calendar events (birthdays, member anniversaries) expressed in the same
  (metric_name, metric_value, prior_value) shape as every other milestone event.
  Only a window around today is materialized; these are not back-filled historically.
-#}
with params as (
    select {{ gaming_today() }} as as_of_date
),

year_offsets as (
    select -1 as y union all select 0 union all select 1
),

people as (
    select
        p.player_id,
        p.date_of_birth,
        m.enroll_date
    from {{ ref('stg_cms__player') }} p
    left join {{ ref('stg_loy__member') }} m on m.player_id = p.player_id
),

dated as (
    select
        people.player_id,
        extract(year from params.as_of_date) + year_offsets.y as event_year,
        {{ date_add('year',
                    '(extract(year from params.as_of_date) + year_offsets.y) - extract(year from people.date_of_birth)',
                    'people.date_of_birth') }} as birthday_date,
        {{ date_add('year',
                    '(extract(year from params.as_of_date) + year_offsets.y) - extract(year from people.enroll_date)',
                    'people.enroll_date') }} as anniversary_date,
        extract(year from people.date_of_birth) as birth_year,
        extract(year from people.enroll_date) as enroll_year,
        params.as_of_date
    from people
    cross join year_offsets
    cross join params
),

events as (
    select player_id, birthday_date as event_date, 'birthday' as metric_name,
           1 as metric_value, 0 as prior_value, as_of_date
    from dated

    union all
    select player_id, birthday_date, 'age_at_birthday',
           event_year - birth_year, event_year - birth_year - 1, as_of_date
    from dated

    union all
    select player_id, anniversary_date, 'membership_years',
           event_year - enroll_year, event_year - enroll_year - 1, as_of_date
    from dated
    where enroll_year is not null
      and event_year - enroll_year >= 1
)

select
    player_id,
    event_date,
    metric_name,
    cast(metric_value as {{ dbt.type_float() }}) as metric_value,
    cast(prior_value as {{ dbt.type_float() }}) as prior_value
from events
where event_date between {{ date_add('day', -1 * var('calendar_window_days'), 'as_of_date') }}
                     and {{ date_add('day', var('calendar_window_days'), 'as_of_date') }}
