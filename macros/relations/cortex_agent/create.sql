{% macro snowflake__create_or_replace_cortex_agent() %}
{#-
--  Orchestrates the CREATE OR REPLACE AGENT statement for a model that uses
--  the `cortex_agent` materialization. Runs pre/post hooks around the main
--  statement, exactly like dbt's built-in materializations.
--
--  Returns: {'relations': [target_relation]}
-#}
  {%- set identifier = model['alias'] -%}

  {%- set target_relation = api.Relation.create(
      identifier=identifier, schema=schema, database=database,
      type='view') -%}

  {{ run_hooks(pre_hooks) }}

  -- build model
  {% call statement('main') -%}
    {{ dbt_cortex_agent.snowflake__get_create_cortex_agent_sql(target_relation, sql) }}
  {%- endcall %}

  {{ run_hooks(post_hooks) }}

  {{ return({'relations': [target_relation]}) }}

{% endmacro %}


{% macro snowflake__get_create_cortex_agent_sql(relation, sql) -%}
{#-
--  Produce the DDL that creates a Cortex Agent.
--
--  Args:
--  - relation: Union[SnowflakeRelation, str]
--      - SnowflakeRelation - required for relation.render()
--      - str - is already the rendered relation name
--  - sql: str - the compiled body of the model
--
--  Two modes, selected by the `raw_ddl` config (default false):
--
--  1. Specification mode (default): the model body is the agent
--     specification YAML. It is wrapped in `FROM SPECIFICATION $$ ... $$`,
--     and the optional `comment` / `profile` configs are emitted as the
--     COMMENT and PROFILE clauses.
--
--  2. Raw DDL mode (`raw_ddl=true`): the model body is everything that
--     follows `CREATE OR REPLACE AGENT <name>` — a direct pass-through to
--     the Snowflake SQL layer. This guarantees forward compatibility with
--     any future CREATE AGENT syntax without a package upgrade.
--
--  Returns: a valid DDL statement that creates the agent.
-#}

  {%- set raw_ddl = config.get('raw_ddl', default=false) -%}

  {%- if raw_ddl -%}

    create or replace agent {{ relation }}
    {{ sql }}

  {%- else -%}

    {%- set comment = config.get('comment', default=none) -%}
    {%- set profile = config.get('profile', default=none) -%}

    create or replace agent {{ relation }}
    {%- if comment is not none %}
    comment = {{ dbt_cortex_agent.cortex_agent_quote_string(comment) }}
    {%- endif %}
    {%- if profile is not none %}
    profile = {{ dbt_cortex_agent.cortex_agent_render_profile(profile) }}
    {%- endif %}
    from specification
$${{ '\n' }}{{ sql }}{{ '\n' }}$$

  {%- endif -%}

{%- endmacro %}


{% macro cortex_agent_quote_string(value) -%}
{#-
--  Wrap a value in single quotes for use as a SQL string literal, doubling
--  any embedded single quotes so the literal stays well-formed.
-#}
  {{- "'" ~ (value | string | replace("'", "''")) ~ "'" -}}
{%- endmacro %}


{% macro cortex_agent_render_profile(profile) -%}
{#-
--  Render the PROFILE clause value. PROFILE is a JSON object serialized as a
--  string. Accept either:
--    - a mapping (dict) supplied via config(profile={...}); it is serialized
--      to JSON for you, or
--    - a pre-serialized JSON string, used as-is.
--  The result is returned as a quoted SQL string literal.
-#}
  {%- if profile is mapping -%}
    {%- set profile_str = tojson(profile) -%}
  {%- else -%}
    {%- set profile_str = profile -%}
  {%- endif -%}
  {{- dbt_cortex_agent.cortex_agent_quote_string(profile_str) -}}
{%- endmacro %}
