{% macro snowflake__create_or_replace_cortex_agent() %}
{#-
--  Orchestrates CREATE AGENT DDL for a model using the `cortex_agent`
--  materialization. Runs pre/post hooks around the main statement(s).
--
--  When versioning=false (default): issues CREATE OR REPLACE AGENT.
--  When versioning=true: issues CREATE AGENT IF NOT EXISTS ... ADD VERSION
--  (new agent) or ALTER AGENT ... ADD VERSION (existing agent), then
--  optionally ALTER AGENT ... SET DEFAULT_VERSION when set_default=true.
--
--  Returns: {'relations': [target_relation]}
-#}
  {%- set identifier = model['alias'] -%}

  {%- set target_relation = api.Relation.create(
      identifier=identifier, schema=schema, database=database,
      type='view') -%}

  {%- set versioning = config.get('versioning', default=false) -%}
  {%- set raw_ddl    = config.get('raw_ddl', default=false) -%}

  {{ run_hooks(pre_hooks) }}

  {%- if versioning -%}

    {%- if raw_ddl -%}
      {{ exceptions.warn("cortex_agent: versioning=true is incompatible with raw_ddl=true. "
                         ~ "Falling back to CREATE OR REPLACE behavior. "
                         ~ "Switch to specification mode (raw_ddl=false) to use versioning.") }}
      {% call statement('main') -%}
        {{ dbt_cortex_agent.snowflake__get_create_cortex_agent_sql(target_relation, sql) }}
      {%- endcall %}

    {%- else -%}

      {%- set version_name = config.get('version_name', default=none) -%}
      {%- if version_name is none -%}
        {%- set version_name = dbt_cortex_agent._cortex_agent_auto_version_name() -%}
      {%- endif -%}
      {%- set set_default  = config.get('set_default', default=true) -%}
      {%- set agent_exists = dbt_cortex_agent._cortex_agent_exists(target_relation) -%}

      {%- if not agent_exists -%}

        {% call statement('main') -%}
          {{ dbt_cortex_agent.snowflake__get_create_agent_with_version_sql(target_relation, version_name, sql) }}
        {%- endcall %}
        {#-
        --  If Snowflake does NOT auto-set the first version as default, uncomment:
        --  {%- if set_default -%}
        --    {% call statement('set_default_version') -%}
        --      {{ dbt_cortex_agent.snowflake__get_set_agent_default_version_sql(target_relation, version_name) }}
        --    {%- endcall %}
        --  {%- endif -%}
        --  Verify against live Snowflake docs before enabling.
        -#}

      {%- else -%}

        {% call statement('main') -%}
          {{ dbt_cortex_agent.snowflake__get_alter_agent_add_version_sql(target_relation, version_name, sql) }}
        {%- endcall %}
        {%- if set_default -%}
          {% call statement('set_default_version') -%}
            {{ dbt_cortex_agent.snowflake__get_set_agent_default_version_sql(target_relation, version_name) }}
          {%- endcall %}
        {%- endif -%}

      {%- endif -%}

    {%- endif -%}

  {%- else -%}

    {% call statement('main') -%}
      {{ dbt_cortex_agent.snowflake__get_create_cortex_agent_sql(target_relation, sql) }}
    {%- endcall %}

  {%- endif -%}

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

    {%- if config.get('web_search_tool', default=false) or config.get('comment', default=none) is not none or config.get('profile', default=none) is not none -%}
      {{ exceptions.warn("cortex_agent: web_search_tool, comment, and profile configs are ignored when raw_ddl=true. Add these directly to your DDL body.") }}
    {%- endif -%}

    create or replace agent {{ relation }}
    {{ sql }}

  {%- else -%}

    {%- set comment = config.get('comment', default=none) -%}
    {%- set profile = config.get('profile', default=none) -%}
    {%- set web_search_tool = config.get('web_search_tool', default=false) -%}

    {%- if web_search_tool -%}
      {%- set sql = sql ~ '\ntools:\n  - tool_spec:\n      type: "web_search"\n      name: "web_search"\n' -%}
    {%- endif -%}

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


{% macro snowflake__get_create_agent_with_version_sql(relation, version_name, sql) -%}
{#-
--  Produce DDL that creates a new agent with a named first version.
--  Used when versioning=true and the agent does not yet exist.
--
--  !! SYNTAX NEEDS VERIFICATION against live Snowflake Cortex Agent docs.
--  Best-guess candidate:
--
--      CREATE AGENT IF NOT EXISTS <name>
--        [COMMENT = '...'] [PROFILE = '...']
--        ADD VERSION '<version_name>'
--        FROM SPECIFICATION $$...$$
--
--  Args:
--  - relation:     SnowflakeRelation or str
--  - version_name: str — the named version to create
--  - sql:          str — agent specification YAML body
--  Returns: DDL string
-#}

  {%- set comment        = config.get('comment', default=none) -%}
  {%- set profile        = config.get('profile', default=none) -%}
  {%- set web_search_tool = config.get('web_search_tool', default=false) -%}

  {%- if web_search_tool -%}
    {%- set sql = sql ~ '\ntools:\n  - tool_spec:\n      type: "web_search"\n      name: "web_search"\n' -%}
  {%- endif -%}

  create agent if not exists {{ relation }}
  {%- if comment is not none %}
  comment = {{ dbt_cortex_agent.cortex_agent_quote_string(comment) }}
  {%- endif %}
  {%- if profile is not none %}
  profile = {{ dbt_cortex_agent.cortex_agent_render_profile(profile) }}
  {%- endif %}
  add version {{ dbt_cortex_agent.cortex_agent_quote_string(version_name) }}
  from specification
$${{ '\n' }}{{ sql }}{{ '\n' }}$$

{%- endmacro %}


{% macro snowflake__get_alter_agent_add_version_sql(relation, version_name, sql) -%}
{#-
--  Produce DDL that adds a named version to an existing agent.
--  Used when versioning=true and the agent already exists.
--
--  Note: COMMENT and PROFILE are agent-level attributes set at creation time
--  and are intentionally omitted from the ALTER form.
--
--  !! SYNTAX NEEDS VERIFICATION against live Snowflake Cortex Agent docs.
--  Best-guess candidate:
--
--      ALTER AGENT <name>
--        ADD VERSION '<version_name>'
--        FROM SPECIFICATION $$...$$
--
--  Args:
--  - relation:     SnowflakeRelation or str
--  - version_name: str — the named version to add
--  - sql:          str — agent specification YAML body
--  Returns: DDL string
-#}

  {%- set web_search_tool = config.get('web_search_tool', default=false) -%}

  {%- if web_search_tool -%}
    {%- set sql = sql ~ '\ntools:\n  - tool_spec:\n      type: "web_search"\n      name: "web_search"\n' -%}
  {%- endif -%}

  alter agent {{ relation }}
  add version {{ dbt_cortex_agent.cortex_agent_quote_string(version_name) }}
  from specification
$${{ '\n' }}{{ sql }}{{ '\n' }}$$

{%- endmacro %}


{% macro snowflake__get_set_agent_default_version_sql(relation, version_name) -%}
{#-
--  Produce DDL that sets the default version of an existing agent.
--
--  !! SYNTAX NEEDS VERIFICATION against live Snowflake Cortex Agent docs.
--  Best-guess candidate:
--
--      ALTER AGENT <name> SET DEFAULT_VERSION = '<version_name>'
--
--  Args:
--  - relation:     SnowflakeRelation or str
--  - version_name: str — the version to promote to default
--  Returns: DDL string
-#}

  alter agent {{ relation }}
  set default_version = {{ dbt_cortex_agent.cortex_agent_quote_string(version_name) }}

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
