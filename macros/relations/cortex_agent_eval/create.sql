{% macro _cortex_eval_cfg(key, default=none) -%}
{#-
--  Reads a config key for the eval materializations, preferring
--  config(meta={...}) and falling back to a top-level config() key, the same
--  precedence the other materializations use.
-#}
  {%- set _m = config.get('meta', {}).get(key) -%}
  {{- return(_m if _m is not none else config.get(key, default=default)) -}}
{%- endmacro %}


{% macro cortex_agent_eval__config_path(stage, identifier) -%}
{#-
--  Stage path of the config file deployed for a cortex_agent_eval model.
-#}
  {{- stage ~ '/evals/' ~ identifier ~ '/config.yaml' -}}
{%- endmacro %}


{% macro snowflake__create_or_replace_cortex_agent_eval() %}
{#-
--  Writes the model body (the evaluation YAML) to a stage file for a model that
--  uses the `cortex_agent_eval` materialization. Runs pre/post hooks around the
--  main statement, exactly like dbt's built-in materializations.
--
--  Returns: {'relations': [target_relation]}
-#}
  {%- set identifier       = model['alias'] -%}
  {%- set stage            = dbt_cortex_agent._cortex_eval_cfg('stage') -%}
  {%- if not stage -%}
    {{ exceptions.raise_compiler_error(
        "cortex_agent_eval: config 'stage' is required, e.g. meta={'stage': '@my_db.my_schema.eval_stage'}"
    ) }}
  {%- endif -%}
  {%- set config_path      = dbt_cortex_agent.cortex_agent_eval__config_path(stage, identifier) -%}
  {%- set stage_identifier = stage[1:] -%}

  {%- set target_relation = api.Relation.create(
      identifier=identifier, schema=schema, database=database,
      type='view') -%}

  {{ run_hooks(pre_hooks) }}

  -- ensure stage exists
  {%- do run_query("create stage if not exists " ~ stage_identifier) -%}

  -- write the evaluation YAML
  {% call statement('main') -%}
    {{ dbt_cortex_agent.snowflake__get_create_cortex_agent_eval_sql(target_relation, sql, config_path) }}
  {%- endcall %}

  -- validate that the file landed on the stage
  {%- set list_result = run_query("list " ~ config_path) -%}
  {%- if list_result.rows | length == 0 -%}
    {{ exceptions.raise_compiler_error(
        "cortex_agent_eval: config file not found at '" ~ config_path ~ "' after upload."
    ) }}
  {%- endif -%}

  {{ run_hooks(post_hooks) }}

  {{ return({'relations': [target_relation]}) }}

{% endmacro %}


{% macro snowflake__get_create_cortex_agent_eval_sql(relation, sql, config_path) -%}
{#-
--  Produce the COPY INTO statement that writes the evaluation YAML to a stage
--  file.
--
--  Args:
--  - relation:    SnowflakeRelation or str (for context)
--  - sql:         str - compiled model body (the evaluation YAML)
--  - config_path: str - full stage path of the file,
--                       e.g. '@my_db.my_schema.eval_stage/evals/support_eval/config.yaml'
--
--  Unlike cortex_skill, no local file is needed: the rendered YAML is unloaded
--  straight from a literal, so Jinja in the body (ref(), var(), ...) is
--  resolved and the same statement works under dbt Core and dbt Fusion. The
--  file format writes the string verbatim (no delimiters, quoting, escaping or
--  compression), which EXECUTE_AI_EVALUATION can read back as YAML.
--
--  The YAML is embedded in a $$-quoted literal, so it must not contain '$$'.
--
--  Returns: a valid Snowflake COPY INTO statement.
-#}
  {%- if '$$' in sql -%}
    {{ exceptions.raise_compiler_error(
        "cortex_agent_eval: the evaluation YAML must not contain '$$' (it is embedded in a $$-quoted string)."
    ) }}
  {%- endif -%}

  copy into {{ config_path }}
  from (select $$
{{ sql | trim }}
$$)
  file_format = (
    type                     = 'CSV'
    compression              = 'NONE'
    field_delimiter          = none
    record_delimiter         = none
    field_optionally_enclosed_by = none
    escape_unenclosed_field  = none
  )
  single    = true
  overwrite = true
  header    = false

{%- endmacro %}


{% macro cortex_agent_eval_config_path(eval_ref) -%}
{#-
--  Returns the stage path of the config file for a cortex_agent_eval model
--  given its ref() or its model name, so it can be passed to
--  EXECUTE_AI_EVALUATION.
--
--  Calling ref() as the argument registers the DAG dependency, and the macro
--  derives the path from the eval model's `stage` config.
--
--  Args:
--  - eval_ref: Relation returned by ref(), or a model name string
--
--  Returns: e.g. '@my_db.my_schema.eval_stage/evals/support_eval/config.yaml'
-#}
  {%- set model_name = eval_ref.identifier if eval_ref is not string else eval_ref -%}
  {%- if execute -%}
    {%- set ns = namespace(stage='') -%}
    {%- for node in graph.nodes.values() -%}
      {%- if node.resource_type == 'model' and node.name == model_name
             and node.config.materialized == 'cortex_agent_eval' -%}
        {%- set ns.stage = node.config.get('meta', {}).get('stage') or node.config.get('stage', '') -%}
      {%- endif -%}
    {%- endfor -%}
    {%- if ns.stage == '' -%}
      {{ exceptions.raise_compiler_error(
          "cortex_agent_eval_config_path: no cortex_agent_eval model named '" ~ model_name
          ~ "' with a stage config was found."
      ) }}
    {%- endif -%}
    {{- dbt_cortex_agent.cortex_agent_eval__config_path(ns.stage, model_name) -}}
  {%- else -%}
    {{- '@__eval_stage_placeholder__/evals/' ~ model_name ~ '/config.yaml' -}}
  {%- endif -%}
{%- endmacro %}
