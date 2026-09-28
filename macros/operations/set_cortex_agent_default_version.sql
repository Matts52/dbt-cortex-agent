{% macro set_cortex_agent_default_version(agent, version) -%}
{#-
--  Run-operation: point a Cortex Agent's default version at a committed
--  version, by Snowflake version name (VERSION$3) or by alias (the
--  `version_name` a versioned run tagged it with). Use it to promote a
--  staged canary or to roll back.
--
--    dbt run-operation set_cortex_agent_default_version \
--      --args '{agent: my_db.my_schema.my_agent, version: v_20250101_120000}'
--
--  Snowflake's SET DEFAULT_VERSION does not accept aliases, so the alias is
--  resolved to its version name first.
-#}
  {%- set versions = dbt_cortex_agent._cortex_agent_versions(agent) -%}
  {%- set key = version | string | upper -%}
  {%- if key in versions.aliases -%}
    {%- set target = versions.aliases[key] -%}
  {%- elif key.startswith('VERSION$') or key in ['FIRST', 'LAST'] -%}
    {%- set target = key -%}
  {%- else -%}
    {{ exceptions.raise_compiler_error("set_cortex_agent_default_version: '" ~ version
       ~ "' is neither an alias on " ~ agent ~ " nor a VERSION$<n> name. Known aliases: "
       ~ (versions.aliases.keys() | list | join(', '))) }}
  {%- endif -%}
  {%- do run_query(dbt_cortex_agent.snowflake__get_set_agent_default_version_sql(agent, target)) -%}
  {{ log('set_cortex_agent_default_version: ' ~ agent ~ ' default -> ' ~ target, info=true) }}
{%- endmacro %}
