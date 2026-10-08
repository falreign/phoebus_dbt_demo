{#- Drop rows Fivetran marked as deleted at the source.
    Fivetran only creates _fivetran_deleted on some tables/connector modes, so apply the filter only when the column exists. -#}
{% macro fivetran_live(relation) %}
    {%- if not execute -%}
        true
    {%- else -%}
        {%- set cols = adapter.get_columns_in_relation(relation) | map(attribute='name') | map('lower') | list -%}
        {%- if '_fivetran_deleted' in cols -%}
            coalesce(_fivetran_deleted, false) = false
        {%- else -%}
            true
        {%- endif -%}
    {%- endif -%}
{% endmacro %}

{#- fv_cols: select the requested columns from a Fivetran table, matching names while ignoring case and underscores.
    Fivetran lands SQL Server names lowercased with no separators (PlayerID -> playerid); other connectors/destinations
    use snake_case (player_id). Asking for 'player_id' works for both, and the column is always aliased to the snake_case name. -#}
{% macro fv_cols(relation, columns) %}
    {%- if not execute -%}
        {%- for c in columns -%}null as {{ c }}{{ ',' if not loop.last }}{%- endfor -%}
    {%- else -%}
        {%- set actual = {} -%}
        {%- for c in adapter.get_columns_in_relation(relation) -%}
            {%- do actual.update({ (c.name | lower | replace('_', '')): c.name }) -%}
        {%- endfor -%}
        {%- for col in columns -%}
            {%- set lookup = col | replace('_', '') -%}
            {%- if lookup not in actual -%}
                {{ exceptions.raise_compiler_error("Column '" ~ col ~ "' not found in " ~ relation ~ " (matched ignoring case/underscores). Columns present: " ~ (actual.values() | list | join(', '))) }}
            {%- endif %}
        {{ adapter.quote(actual[lookup]) }} as {{ col }}{{ ',' if not loop.last }}
        {%- endfor -%}
    {%- endif -%}
{% endmacro %}
