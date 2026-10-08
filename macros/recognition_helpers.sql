{#- One place to tune how recommendations are ranked. -#}
{% macro priority_score(base_weight, tier_id, days_since_event, on_property, is_vip) %}
    ( {{ base_weight }}
      + {{ tier_id }} * 3
      + case when {{ on_property }} then 15 else 0 end
      + case when {{ is_vip }} then 5 else 0 end
      - least(greatest({{ days_since_event }}, 0), 14) * 1.5 )
{% endmacro %}

{#- Fill the {first_name} / {value} placeholders in a rule's talking point. -#}
{% macro render_talking_point(template, first_name, value) %}
    replace(replace({{ template }}, '{first_name}', {{ first_name }}),
            '{value}', cast(cast(round({{ value }}, 0) as {{ dbt.type_int() }}) as {{ dbt.type_string() }}))
{% endmacro %}
