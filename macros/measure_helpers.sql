{#- measure_cols: emit one column per measure; use the provided SQL expression, or 0 when this source has none.
    This is what keeps the three activity sources (gaming / dining / hotel) from repeating the full column list. -#}
{% macro measure_cols(measures, provided) %}
{%- for m in measures %}
        {{ provided[m] if m in provided else '0' }} as {{ m }}{{ ',' if not loop.last }}
{%- endfor %}
{% endmacro %}

{% macro sum_measures(measures) %}
{%- for m in measures %}
        sum({{ m }}) as {{ m }}{{ ',' if not loop.last }}
{%- endfor %}
{% endmacro %}

{#- cumulative_cols: running lifetime total of each measure in {metric_name: measure}. -#}
{% macro cumulative_cols(metric_map, partition_by, order_by) %}
{%- for metric, measure in metric_map.items() %}
        sum({{ measure }}) over (partition by {{ partition_by }} order by {{ order_by }}
            rows between unbounded preceding and current row) as cum_{{ metric }}{{ ',' if not loop.last }}
{%- endfor %}
{% endmacro %}

{#- unpivot_cumulative: turn the wide cum_* columns into (metric_name, metric_value, prior_value) rows. -#}
{% macro unpivot_cumulative(relation, metric_map) %}
{%- for metric, measure in metric_map.items() %}
    select
        player_id,
        activity_date as event_date,
        '{{ metric }}' as metric_name,
        cast(cum_{{ metric }} as {{ dbt.type_float() }}) as metric_value,
        cast(cum_{{ metric }} - {{ measure }} as {{ dbt.type_float() }}) as prior_value
    from {{ relation }}
    where {{ measure }} > 0
    {{ 'union all' if not loop.last }}
{%- endfor %}
{% endmacro %}
