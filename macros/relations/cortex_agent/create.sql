{% macro snowflake__create_or_replace_cortex_agent() %}
{#-
--  Orchestrates the DDL for a model using the `cortex_agent`
--  materialization. Runs pre/post hooks around the main statement(s).
--
--  When versioning=false (default): issues CREATE OR REPLACE AGENT.
--
--  When versioning=true, uses Snowflake's live-version workflow:
--    - Agent absent:  CREATE AGENT ... FROM SPECIFICATION (commits VERSION$1),
--      which is always pinned as the default: Snowflake's initial default is
--      the floating 'LAST', which would silently follow later commits.
--    - Agent present: ALTER AGENT ... ADD LIVE VERSION FROM LAST (if no live
--      version is open), ALTER AGENT ... MODIFY LIVE VERSION SET
--      SPECIFICATION, ALTER AGENT ... SET COMMENT/PROFILE, then
--      ALTER AGENT ... COMMIT — skipped when the spec is unchanged.
--    - `version_name` is validated as an unquoted identifier before any DDL
--      runs. The new version is promoted with SET DEFAULT_VERSION when
--      set_default=true, then tagged with `version_name` as its alias. When
--      set_default=false the current default is pinned before committing.
--
--  Returns: {'relations': [target_relation]}
-#}
  {%- set identifier = model['alias'] -%}

  {%- set target_relation = api.Relation.create(
      identifier=identifier, schema=schema, database=database,
      type='view') -%}

  {%- set _m = config.get('meta', {}).get('versioning') -%}
  {%- set versioning = _m if _m is not none else config.get('versioning', default=false) -%}
  {%- set _m = config.get('meta', {}).get('raw_ddl') -%}
  {%- set raw_ddl    = _m if _m is not none else config.get('raw_ddl', default=false) -%}

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

      {%- set _m = config.get('meta', {}).get('version_name') -%}
      {%- set version_name = _m if _m is not none else config.get('version_name', default=none) -%}
      {%- if version_name is none -%}
        {%- set version_name = dbt_cortex_agent._cortex_agent_auto_version_name() -%}
      {%- endif -%}
      {%- set _m = config.get('meta', {}).get('set_default') -%}
      {%- set set_default  = _m if _m is not none else config.get('set_default', default=true) -%}
      {%- set _m = config.get('meta', {}).get('comment') -%}
      {%- set comment      = _m if _m is not none else config.get('comment', default=none) -%}
      {%- set _m = config.get('meta', {}).get('profile') -%}
      {%- set profile      = _m if _m is not none else config.get('profile', default=none) -%}

      {%- do dbt_cortex_agent._cortex_agent_validate_version_name(version_name) -%}

      {%- if not dbt_cortex_agent._cortex_agent_exists(target_relation) -%}

        {#- First run: CREATE AGENT commits VERSION$1. Always pin it as the
            default (there is no earlier default to protect), so the default
            never floats with 'LAST'. -#}
        {% call statement('main') -%}
          {{ dbt_cortex_agent.snowflake__get_create_versioned_agent_sql(target_relation, sql) }}
        {%- endcall %}
        {%- set versions = dbt_cortex_agent._cortex_agent_versions(target_relation) -%}
        {%- do dbt_cortex_agent._cortex_agent_promote_and_tag(target_relation, versions.last_name, version_name, true) -%}

      {%- else -%}

        {%- set versions = dbt_cortex_agent._cortex_agent_versions(target_relation) -%}

        {%- if not versions.has_live -%}
          {% call statement('add_live_version') -%}
            {{ dbt_cortex_agent.snowflake__get_add_live_agent_version_sql(target_relation) }}
          {%- endcall %}
        {%- endif -%}

        {% call statement('main') -%}
          {{ dbt_cortex_agent.snowflake__get_modify_live_agent_version_sql(target_relation, sql) }}
        {%- endcall %}

        {%- if comment is not none or profile is not none -%}
          {% call statement('set_agent_attributes') -%}
            {{ dbt_cortex_agent.snowflake__get_set_agent_attributes_sql(target_relation, comment, profile) }}
          {%- endcall %}
        {%- endif -%}

        {%- set versions = dbt_cortex_agent._cortex_agent_versions(target_relation) -%}

        {%- if execute and versions.live_hash is none -%}
          {{ exceptions.raise_compiler_error("cortex_agent: " ~ target_relation
             ~ " has no live version spec after MODIFY LIVE VERSION; refusing to guess whether the spec changed.") }}
        {%- endif -%}

        {%- if versions.live_hash == versions.last_hash -%}

          {{ log('cortex_agent: ' ~ target_relation ~ ' spec unchanged, no new version committed', info=true) }}
          {#- Promote an already-committed (e.g. canary) version on request. -#}
          {%- if set_default and versions.default_name != versions.last_name -%}
            {% call statement('set_default_version') -%}
              {{ dbt_cortex_agent.snowflake__get_set_agent_default_version_sql(target_relation, versions.last_name) }}
            {%- endcall %}
          {%- endif -%}

        {%- else -%}

          {#- A floating 'LAST' default would follow the commit: pin it first. -#}
          {%- if not set_default and versions.default_name is not none -%}
            {% call statement('pin_default_version') -%}
              {{ dbt_cortex_agent.snowflake__get_set_agent_default_version_sql(target_relation, versions.default_name) }}
            {%- endcall %}
          {%- endif -%}

          {% call statement('commit_version') -%}
            {{ dbt_cortex_agent.snowflake__get_commit_agent_version_sql(target_relation, 'dbt ' ~ invocation_id) }}
          {%- endcall %}

          {%- set versions = dbt_cortex_agent._cortex_agent_versions(target_relation) -%}
          {%- do dbt_cortex_agent._cortex_agent_promote_and_tag(target_relation, versions.last_name, version_name, set_default) -%}

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


{% macro _cortex_agent_promote_and_tag(relation, committed_name, version_name, set_default) -%}
{#-
--  After a commit: when set_default=true, pin the new version as the default,
--  then tag it with `version_name` as its alias. Promotion runs first so a
--  failed alias never blocks it. No-op at parse time.
-#}
  {%- if not execute or committed_name is none -%}{{ return(none) }}{%- endif -%}
  {%- if set_default -%}
    {% call statement('set_default_version') -%}
      {{ dbt_cortex_agent.snowflake__get_set_agent_default_version_sql(relation, committed_name) }}
    {%- endcall %}
  {%- endif -%}
  {%- if version_name is not none -%}
    {% call statement('set_version_alias') -%}
      {{ dbt_cortex_agent.snowflake__get_set_agent_version_alias_sql(relation, committed_name, version_name) }}
    {%- endcall %}
  {%- endif -%}
{%- endmacro %}


{% macro _cortex_agent_validate_version_name(version_name) -%}
{#-
--  Raise a compiler error unless `version_name` is a valid unquoted Snowflake
--  identifier (it is emitted unquoted as the version alias). Checked before
--  any DDL runs, so an invalid name never leaves a half-finished publish.
-#}
  {%- if version_name is none -%}{{ return(none) }}{%- endif -%}
  {%- if not modules.re.match('^[A-Za-z_][A-Za-z0-9_$]*$', version_name | string) -%}
    {{ exceptions.raise_compiler_error("cortex_agent: version_name '" ~ version_name
       ~ "' is not a valid unquoted Snowflake identifier. It is used as the version "
       ~ "alias and must match ^[A-Za-z_][A-Za-z0-9_$]*$ (start with a letter or _, "
       ~ "then letters, digits, _ or $). Snowflake stores aliases uppercased. "
       ~ "Nothing was deployed.") }}
  {%- endif -%}
{%- endmacro %}


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

  {%- set _m = config.get('meta', {}).get('raw_ddl') -%}
  {%- set raw_ddl = _m if _m is not none else config.get('raw_ddl', default=false) -%}
  {%- set _m = config.get('meta', {}).get('comment') -%}
  {%- set comment = _m if _m is not none else config.get('comment', default=none) -%}
  {%- set _m = config.get('meta', {}).get('profile') -%}
  {%- set profile = _m if _m is not none else config.get('profile', default=none) -%}
  {%- set _m = config.get('meta', {}).get('web_search_tool') -%}
  {%- set web_search_tool = _m if _m is not none else config.get('web_search_tool', default=false) -%}
  {%- set _m = config.get('meta', {}).get('model') -%}
  {%- set model = _m if _m is not none else config.get('model', default=none) -%}
  {%- set _m = config.get('meta', {}).get('budget') -%}
  {%- set budget = _m if _m is not none else config.get('budget', default=none) -%}
  {%- set _m = config.get('meta', {}).get('mcp_servers') -%}
  {%- set mcp_servers = _m if _m is not none else config.get('mcp_servers', default=[]) -%}

  {%- if raw_ddl -%}

    {%- if web_search_tool or comment is not none or profile is not none or model is not none or budget is not none or mcp_servers | length > 0 -%}
      {{ exceptions.warn("cortex_agent: web_search_tool, comment, profile, model, budget, and mcp_servers configs are ignored when raw_ddl=true. Add these directly to your DDL body.") }}
    {%- endif -%}

    create or replace agent {{ relation }}
    {{ sql }}

  {%- else -%}

    create or replace agent {{ relation }}
    {%- if comment is not none %}
    comment = {{ dbt_cortex_agent.cortex_agent_quote_string(comment) }}
    {%- endif %}
    {%- if profile is not none %}
    profile = {{ dbt_cortex_agent.cortex_agent_render_profile(profile) }}
    {%- endif %}
    from specification
$${{ '\n' }}{{ dbt_cortex_agent.cortex_agent_render_spec_body(sql) }}{{ '\n' }}$$

  {%- endif -%}

{%- endmacro %}


{% macro cortex_agent_render_spec_body(sql) -%}
{#-
--  Render the full specification YAML for specification mode: the model body
--  plus the config-injected `models:` / `orchestration:` blocks (from the
--  `model` / `budget` configs), the web_search tool, and `mcp_servers:`.
--  Shared by the CREATE OR REPLACE path and the versioning path so every
--  config behaves the same in both.
--
--  Args:
--  - sql: str — the compiled model body (agent specification YAML)
--  Returns: the specification YAML string (without the $$ delimiters).
-#}
  {%- set _m = config.get('meta', {}).get('web_search_tool') -%}
  {%- set web_search_tool = _m if _m is not none else config.get('web_search_tool', default=false) -%}
  {%- set _m = config.get('meta', {}).get('model') -%}
  {%- set model = _m if _m is not none else config.get('model', default=none) -%}
  {%- set _m = config.get('meta', {}).get('budget') -%}
  {%- set budget = _m if _m is not none else config.get('budget', default=none) -%}
  {%- set _m = config.get('meta', {}).get('mcp_servers') -%}
  {%- set mcp_servers = _m if _m is not none else config.get('mcp_servers', default=[]) -%}

  {%- if model is not none and '\nmodels:' in ('\n' ~ sql) -%}
    {{ exceptions.warn("cortex_agent: 'model' config is set but the spec body also appears to contain a top-level 'models:' key. The config-injected value will be ignored by most YAML parsers. Remove 'models:' from the spec body or unset the 'model' config.") }}
  {%- endif -%}
  {%- if budget is not none and '\norchestration:' in ('\n' ~ sql) -%}
    {{ exceptions.warn("cortex_agent: 'budget' config is set but the spec body also appears to contain a top-level 'orchestration:' key. The config-injected value will be ignored by most YAML parsers. Remove 'orchestration:' from the spec body or unset the 'budget' config.") }}
  {%- endif -%}
  {%- if mcp_servers | length > 0 and '\nmcp_servers:' in ('\n' ~ sql) -%}
    {{ exceptions.warn("cortex_agent: 'mcp_servers' config is set but the spec body also appears to contain a top-level 'mcp_servers:' key. The config-injected block will conflict. Remove 'mcp_servers:' from the spec body or unset the 'mcp_servers' config.") }}
  {%- endif -%}

  {%- if web_search_tool -%}
    {%- set sql = sql ~ '\ntools:\n  - tool_spec:\n      type: "web_search"\n      name: "web_search"\n' -%}
  {%- endif -%}

  {%- if mcp_servers | length > 0 -%}
    {%- set mcp_block = '\nmcp_servers:\n' -%}
    {%- for server in mcp_servers -%}
      {%- set mcp_block = mcp_block ~ '  - server_spec:\n      name: "' ~ server ~ '"\n' -%}
    {%- endfor -%}
    {%- set sql = sql ~ mcp_block -%}
  {%- endif -%}

  {{- dbt_cortex_agent.cortex_agent_render_model_and_budget(model, budget) ~ sql -}}
{%- endmacro %}


{% macro snowflake__get_create_versioned_agent_sql(relation, sql) -%}
{#-
--  Produce DDL that creates a new agent for the versioning path. Snowflake
--  commits the specification as VERSION$1 (the default starts as the
--  floating 'LAST'; the orchestrator pins VERSION$1 right after). Plain CREATE (not OR REPLACE), so an existing agent's version history is
--  never dropped.
--
--  Args:
--  - relation: SnowflakeRelation or str
--  - sql:      str — agent specification YAML body
--  Returns: DDL string
-#}
  {%- set _m = config.get('meta', {}).get('comment') -%}
  {%- set comment = _m if _m is not none else config.get('comment', default=none) -%}
  {%- set _m = config.get('meta', {}).get('profile') -%}
  {%- set profile = _m if _m is not none else config.get('profile', default=none) -%}

  create agent {{ relation }}
  {%- if comment is not none %}
  comment = {{ dbt_cortex_agent.cortex_agent_quote_string(comment) }}
  {%- endif %}
  {%- if profile is not none %}
  profile = {{ dbt_cortex_agent.cortex_agent_render_profile(profile) }}
  {%- endif %}
  from specification
$${{ '\n' }}{{ dbt_cortex_agent.cortex_agent_render_spec_body(sql) }}{{ '\n' }}$$

{%- endmacro %}


{% macro snowflake__get_add_live_agent_version_sql(relation) -%}
{#-
--  Produce DDL that opens a live (uncommitted, editable) version seeded from
--  the most recently committed version. Needed after every COMMIT, which
--  consumes the live version.
-#}
  alter agent {{ relation }} add live version from last
{%- endmacro %}


{% macro snowflake__get_modify_live_agent_version_sql(relation, sql) -%}
{#-
--  Produce DDL that replaces the live version's specification.
--
--  Args:
--  - relation: SnowflakeRelation or str
--  - sql:      str — agent specification YAML body
--  Returns: DDL string
-#}
  alter agent {{ relation }} modify live version set specification =
$${{ '\n' }}{{ dbt_cortex_agent.cortex_agent_render_spec_body(sql) }}{{ '\n' }}$$
{%- endmacro %}


{% macro snowflake__get_set_agent_attributes_sql(relation, comment, profile) -%}
{#-
--  Produce DDL that updates the agent-level COMMENT and/or PROFILE on an
--  existing agent. At least one of comment/profile must be non-null.
-#}
  alter agent {{ relation }} set
  {%- if comment is not none %}
  comment = {{ dbt_cortex_agent.cortex_agent_quote_string(comment) }}{{ ',' if profile is not none }}
  {%- endif %}
  {%- if profile is not none %}
  profile = {{ dbt_cortex_agent.cortex_agent_render_profile(profile) }}
  {%- endif %}
{%- endmacro %}


{% macro snowflake__get_commit_agent_version_sql(relation, comment) -%}
{#-
--  Produce DDL that commits the live version as a new, immutable
--  VERSION$<n>. Snowflake assigns the version name.
-#}
  alter agent {{ relation }} commit comment = {{ dbt_cortex_agent.cortex_agent_quote_string(comment) }}
{%- endmacro %}


{% macro snowflake__get_set_agent_version_alias_sql(relation, version, alias) -%}
{#-
--  Produce DDL that tags a committed version with an alias. The alias is
--  emitted unquoted, so it must be a valid unquoted identifier (enforced by
--  `_cortex_agent_validate_version_name`) and Snowflake stores it
--  uppercased — which the uppercase alias lookups rely on. Aliases are
--  unique per agent: assigning one already in use moves it to this version.
--
--  Args:
--  - relation: SnowflakeRelation or str
--  - version:  str — the Snowflake version name, e.g. VERSION$3
--  - alias:    str — a valid unquoted Snowflake identifier
-#}
  alter agent {{ relation }} modify version {{ version }} set alias = {{ alias }}
{%- endmacro %}


{% macro snowflake__get_set_agent_default_version_sql(relation, version_name) -%}
{#-
--  Produce DDL that sets the default version of an existing agent.
--  Snowflake accepts a version name (VERSION$<n>), FIRST or LAST here — not
--  an alias; resolve aliases with `_cortex_agent_versions` first.
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


{% macro cortex_agent_render_model_and_budget(model, budget) -%}
{#-
--  Render the `models:` and `orchestration:` YAML blocks that are prepended
--  to the spec body when the `model` and/or `budget` configs are set.
--
--  Args:
--  - model:  string or none — value for `models.orchestration`
--  - budget: int, float, or dict or none
--      int/float → shorthand for {seconds: <value>}
--      dict      → {seconds: ..., tokens: ...} (either key is optional)
--
--  Returns: a YAML fragment (possibly empty) ending with a newline when
--  non-empty, so it can be concatenated directly before the spec body.
-#}
  {%- set lines = [] -%}
  {%- if model is not none -%}
    {%- do lines.append('models:') -%}
    {%- do lines.append('  orchestration: ' ~ model) -%}
  {%- endif -%}
  {%- if budget is not none -%}
    {%- set budget = {'seconds': budget} if (budget is not mapping) else budget -%}
    {%- do lines.append('orchestration:') -%}
    {%- do lines.append('  budget:') -%}
    {%- if budget.seconds is defined -%}{%- do lines.append('    seconds: ' ~ budget.seconds) -%}{%- endif -%}
    {%- if budget.tokens  is defined -%}{%- do lines.append('    tokens: '  ~ budget.tokens)  -%}{%- endif -%}
  {%- endif -%}
  {{- (lines | join('\n')) ~ ('\n' if lines else '') -}}
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
