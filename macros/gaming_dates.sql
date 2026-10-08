{#- Today's gaming day. Override with --vars '{as_of_date: 2026-10-07}' for back-testing. -#}
{% macro gaming_today() %}
    {%- if var('as_of_date', none) is not none -%}
        cast('{{ var("as_of_date") }}' as date)
    {%- else -%}
        cast({{ dbt.dateadd('hour', var('local_utc_offset_hours') - var('gaming_day_start_hour'), dbt.current_timestamp()) }} as date)
    {%- endif -%}
{% endmacro %}

{#- Gaming day for a local (naive) timestamp column: the day rolls over at gaming_day_start_hour. -#}
{% macro to_gaming_date(ts_col) %}
    cast({{ dbt.dateadd('hour', -1 * var('gaming_day_start_hour'), ts_col) }} as date)
{% endmacro %}

{#- DATE arithmetic that always returns a DATE (some adapters return DATETIME from dateadd). -#}
{% macro date_add(datepart, interval, date_expr) %}
    cast({{ dbt.dateadd(datepart, interval, date_expr) }} as date)
{% endmacro %}

{#- Exact age in whole years on a reference date. -#}
{% macro age_on(dob_col, ref_date_col) %}
    ({{ dbt.datediff(dob_col, ref_date_col, 'year') }}
      - case when extract(month from {{ dob_col }}) * 100 + extract(day from {{ dob_col }})
                > extract(month from {{ ref_date_col }}) * 100 + extract(day from {{ ref_date_col }})
             then 1 else 0 end)
{% endmacro %}
