{% macro cortex_skill__resolve_skill_dir() -%}
{#-
--  Finds the sibling skill directory for the current cortex_skill model and
--  returns its absolute path for use in a PUT command.
--
--  Convention: the skill directory has the same name as the .sql model
--  (without the extension) and lives in the same directory:
--
--      models/skills/forecaster_skill.sql  →  models/skills/forecaster_skill/
--
--  The directory must contain at least a SKILL.md file. Any additional files
--  (e.g. Python scripts for code execution) are also uploaded to the stage.
--
--  Raises a compiler error if the directory or SKILL.md is missing.
-#}
  {%- set dir_relative = model['original_file_path'][:-4] -%}
  {%- set dir_abs = modules.os.path.join(modules.os.getcwd(), dir_relative) -%}
  {%- if not modules.os.path.isdir(dir_abs) -%}
    {{ exceptions.raise_compiler_error(
        "cortex_skill: skill directory not found at '" ~ dir_abs ~ "'. "
        ~ "Create a '" ~ dir_relative ~ "/' directory alongside your .sql model."
    ) }}
  {%- endif -%}
  {%- if not modules.os.path.exists(modules.os.path.join(dir_abs, 'SKILL.md')) -%}
    {{ exceptions.raise_compiler_error(
        "cortex_skill: SKILL.md not found in '" ~ dir_abs ~ "'. "
        ~ "Every skill directory must contain a SKILL.md file."
    ) }}
  {%- endif -%}
  {{- dir_abs -}}
{%- endmacro %}


{% macro snowflake__create_or_replace_cortex_skill() %}
{#-
--  Orchestrates uploading all files in the sibling skill directory to a
--  Snowflake stage for a model that uses the `cortex_skill` materialization.
--  Runs pre/post hooks around the main statement, exactly like dbt's built-in
--  materializations.
--
--  Returns: {'relations': [target_relation]}
-#}
  {%- set identifier       = model['alias'] -%}
  {%- set stage            = config.require('stage') -%}
  {%- set skill_path       = stage ~ '/skills/' ~ identifier -%}
  {%- set stage_identifier = stage[1:] -%}
  {%- set skill_dir        = dbt_cortex_agent.cortex_skill__resolve_skill_dir() -%}

  {%- set target_relation = api.Relation.create(
      identifier=identifier, schema=schema, database=database,
      type='view') -%}

  {{ run_hooks(pre_hooks) }}

  -- ensure stage exists
  {%- do run_query("create stage if not exists " ~ stage_identifier) -%}

  -- upload all skill files
  {% call statement('main') -%}
    {{ dbt_cortex_agent.snowflake__get_create_cortex_skill_sql(target_relation, skill_dir, skill_path) }}
  {%- endcall %}

  {{ run_hooks(post_hooks) }}

  {{ return({'relations': [target_relation]}) }}

{% endmacro %}


{% macro snowflake__get_create_cortex_skill_sql(relation, skill_dir, skill_path) -%}
{#-
--  Produce the PUT statement that uploads all files in the skill directory
--  to the stage.
--
--  Args:
--  - relation:   SnowflakeRelation or str (for context)
--  - skill_dir:  str - absolute local path to the skill directory
--  - skill_path: str - fully-qualified stage path prefix,
--                      e.g. '@my_db.my_schema.skill_stage/skills/forecaster_skill'
--
--  The wildcard '*' uploads SKILL.md and any companion scripts in one
--  statement. PUT gives exact filename control — no suffix is appended.
--
--  Returns: a valid Snowflake PUT statement.
-#}

  put 'file://{{ skill_dir }}/*'
      {{ skill_path }}/
  auto_compress = false
  overwrite     = true

{%- endmacro %}


{% macro cortex_skill_path(skill_ref) -%}
{#-
--  Returns the stage path for a cortex_skill model given its ref(), so it can
--  be embedded in a cortex_agent's skills: section.
--
--  Calling ref() as the argument registers the DAG dependency (the agent will
--  not be created until the skill files are on the stage), and the macro
--  derives the correct path from the skill model's `stage` config — no var()
--  or hard-coded path needed.
--
--  Usage in a cortex_agent model:
--
--    skills:
--      - name: forecaster
--        source:
--          type: STAGE
--          path: "{{ dbt_cortex_agent.cortex_skill_path(ref('forecaster_skill')) }}"
--
--  Args:
--  - skill_ref: Relation returned by ref() for the cortex_skill model
--
--  Returns: stage path string, e.g. '@my_db.my_schema.skill_stage/skills/forecaster_skill'
-#}
  {%- set model_name = skill_ref.identifier -%}
  {%- if execute -%}
    {%- set ns = namespace(stage='') -%}
    {%- for node in graph.nodes.values() -%}
      {%- if node.resource_type == 'model' and node.name == model_name -%}
        {%- set ns.stage = node.config.get('stage', '') -%}
      {%- endif -%}
    {%- endfor -%}
    {%- if ns.stage == '' -%}
      {{ exceptions.raise_compiler_error(
          "cortex_skill_path: no stage config found for model '" ~ model_name ~ "'. "
          ~ "Ensure it uses the cortex_skill materialization with a stage config."
      ) }}
    {%- endif -%}
    {{- ns.stage ~ '/skills/' ~ model_name -}}
  {%- else -%}
    {{- '@__skill_stage_placeholder__/skills/' ~ model_name -}}
  {%- endif -%}
{%- endmacro %}
