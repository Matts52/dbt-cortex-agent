{#-
--  cortex_skill materialization
--
--  Uploads all files in a sibling skill directory to a Snowflake named stage
--  so that a Cortex Agent can reference the skill. The directory must contain
--  at least SKILL.md and may include any companion scripts (e.g. .py files
--  for code execution tools).
--
--  Convention — place a directory with the same base name as the .sql model
--  in the same folder:
--
--      models/skills/forecaster_skill.sql   ← dbt model (config only)
--      models/skills/forecaster_skill/      ← skill directory
--          SKILL.md                         ← required
--          forecaster.py                    ← optional companion scripts
--
--  All files in the directory are uploaded to:
--
--      <stage>/skills/<model_alias>/
--
--  Required config:
--      stage  string  Fully-qualified stage path, e.g. '@my_db.my_schema.skill_stage'
--
--  See macros/relations/cortex_skill/create.sql for the PUT DDL and
--  the README for usage and config options.
-#}

{% materialization cortex_skill, adapter='snowflake' -%}

    {% set original_query_tag = set_query_tag() %}

    {% do dbt_cortex_agent.snowflake__create_or_replace_cortex_skill() %}

    {#-
    --  Snowflake skills are stage files, not SQL objects. We track the node as
    --  a `view` purely so dbt can represent it in the graph and downstream
    --  `ref()`s resolve for dependency ordering. dbt never issues view DDL for
    --  this node.
    -#}
    {% set target_relation = this.incorporate(type='view') %}

    {% do unset_query_tag(original_query_tag) %}

    {% do return({'relations': [target_relation]}) %}

{%- endmaterialization %}


{#-
--  Default (non-Snowflake) stub materialization.
--
--  Resolves the sibling skill directory and renders the PUT statement without
--  executing it, so `dbt compile` works on any adapter (e.g. DuckDB) and the
--  compiled SQL is inspectable in target/compiled/.
-#}
{% materialization cortex_skill, default -%}

    {%- set identifier  = model['alias'] -%}
    {%- set stage       = config.get('stage', default='@my_db.my_schema.skill_stage') -%}
    {%- set skill_path  = stage ~ '/skills/' ~ identifier -%}
    {%- set skill_dir   = dbt_cortex_agent.cortex_skill__resolve_skill_dir() -%}

    {%- set target_relation = api.Relation.create(
        identifier=identifier, schema=schema, database=database,
        type='view') -%}

    {% call statement('main') -%}
        {{ dbt_cortex_agent.snowflake__get_create_cortex_skill_sql(target_relation, skill_dir, skill_path) }}
    {%- endcall %}

    {% do return({'relations': [target_relation]}) %}

{%- endmaterialization %}
