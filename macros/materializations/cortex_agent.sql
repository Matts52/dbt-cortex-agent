{#-
--  cortex_agent materialization
--
--  Creates (or replaces) a Snowflake Cortex Agent from a dbt model.
--
--  The body of the model becomes the agent's FROM SPECIFICATION YAML by
--  default. Set `raw_ddl=true` in the model config to instead treat the body
--  as the full DDL that follows `CREATE OR REPLACE AGENT <name>` (a direct
--  pass-through to Snowflake's SQL layer, mirroring how the model is written
--  in a .sql file).
--
--  See macros/relations/cortex_agent/create.sql for the DDL construction and
--  the README for usage and config options.
-#}

{% materialization cortex_agent, adapter='snowflake' -%}

    {% set original_query_tag = set_query_tag() %}

    {% do dbt_cortex_agent.snowflake__create_or_replace_cortex_agent() %}

    {#-
    --  Snowflake AGENTs are not (yet) a first-class dbt relation type, so we
    --  incorporate the node as a `view` purely so that dbt can track it in the
    --  graph and downstream `ref()`s resolve. dbt never issues view DDL for
    --  this node because the materialization only ever runs CREATE OR REPLACE
    --  AGENT. persist_docs is intentionally not called for the same reason.
    -#}
    {% set target_relation = this.incorporate(type='view') %}

    {% do unset_query_tag(original_query_tag) %}

    {% do return({'relations': [target_relation]}) %}

{%- endmaterialization %}


{#-
--  Default (non-Snowflake) stub materialization.
--
--  Renders the full CREATE AGENT DDL without executing it, so `dbt compile`
--  works on any adapter (e.g. DuckDB) and the compiled SQL is inspectable in
--  target/compiled/. Attempting `dbt run` with a non-Snowflake adapter will
--  succeed in compiling but issue DDL that the adapter cannot execute.
--
--  When versioning=true, always renders the CREATE AGENT IF NOT EXISTS ...
--  ADD VERSION form (existence cannot be checked without a live DB).
-#}
{% materialization cortex_agent, default -%}

    {%- set identifier = model['alias'] -%}
    {%- set target_relation = api.Relation.create(
        identifier=identifier, schema=schema, database=database,
        type='view') -%}

    {%- set versioning = config.get('versioning', default=false) -%}
    {%- set raw_ddl    = config.get('raw_ddl', default=false) -%}

    {%- if versioning and not raw_ddl -%}

      {%- set version_name = config.get('version_name', default=none) -%}
      {%- if version_name is none -%}
        {%- set version_name = dbt_cortex_agent._cortex_agent_auto_version_name() -%}
      {%- endif -%}

      {% call statement('main') -%}
          {{ dbt_cortex_agent.snowflake__get_create_agent_with_version_sql(target_relation, version_name, sql) }}
      {%- endcall %}

    {%- else -%}

      {% call statement('main') -%}
          {{ dbt_cortex_agent.snowflake__get_create_cortex_agent_sql(target_relation, sql) }}
      {%- endcall %}

    {%- endif -%}

    {% do return({'relations': [target_relation]}) %}

{%- endmaterialization %}
