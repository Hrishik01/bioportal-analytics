{# Session inactivity timeout in seconds, from the `session_timeout_minutes` var.
   Wrapped in a macro because dbt 1.8 unit tests cannot call var() directly in model SQL. #}
{% macro session_timeout_seconds() -%}
    {{ return(var('session_timeout_minutes') * 60) }}
{%- endmacro %}
