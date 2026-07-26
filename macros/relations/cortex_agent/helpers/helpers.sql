{% macro _cortex_agent_exists(relation) -%}
{#-
--  Returns true if the named Cortex Agent already exists in Snowflake.
--  Uses SHOW AGENTS + RESULT_SCAN since agents are not in INFORMATION_SCHEMA.
--  Returns false at parse time (execute=False guard).
-#}
  {%- if not execute -%}{{ return(false) }}{%- endif -%}
  {%- do run_query("show agents like '" ~ relation.identifier ~ "' in schema " ~ relation.database ~ "." ~ relation.schema) -%}
  {%- set results = run_query("select count(*) as n from table(result_scan(last_query_id()))") -%}
  {{ return((results.columns[0].values()[0] | int) > 0) }}
{%- endmacro %}


{% macro _cortex_agent_auto_version_name() -%}
{#-
--  Generates a deterministic version name from run_started_at: v_YYYYMMDD_HHMMSS.
--  All models versioned in the same dbt run share one version name.
--  Returns a placeholder string at parse time.
-#}
  {%- if execute -%}
    {{- 'v_' ~ run_started_at.strftime('%Y%m%d_%H%M%S') -}}
  {%- else -%}
    {{- 'v_YYYYMMDD_HHMMSS' -}}
  {%- endif -%}
{%- endmacro %}
