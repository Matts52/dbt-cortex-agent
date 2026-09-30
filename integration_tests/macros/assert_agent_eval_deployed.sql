{#-
--  Verifies that `dbt build` deployed the evaluation fixtures:
--
--    * the dataset object registered by agent_eval_questions exists
--    * the config file written by agent_eval is on the stage and holds the
--      rendered YAML (ref()s resolved, no leftover Jinja)
--
--      dbt run-operation assert_agent_eval_deployed --target snowflake
--
--  It raises a compiler error (non-zero exit) if either check fails, so it can
--  be wired into CI after `dbt build`. It does not start an evaluation run,
--  which is paid, asynchronous work.
-#}
{% macro assert_agent_eval_deployed() %}
  {%- if execute -%}
    {%- set questions = ref('agent_eval_questions') -%}
    {%- set dataset = dbt_cortex_agent.cortex_agent_eval_dataset_name(questions) -%}
    {%- do run_query("show datasets like '" ~ dataset.identifier ~ "' in schema " ~ dataset.database ~ "." ~ dataset.schema) -%}
    {%- set n = run_query("select count(*) from table(result_scan(last_query_id()))").columns[0].values()[0] -%}
    {%- if n | int < 1 -%}
      {{ exceptions.raise_compiler_error("Expected evaluation dataset not found: " ~ dataset) }}
    {%- endif -%}
    {{ log("OK - evaluation dataset exists: " ~ dataset, info=true) }}

    {%- set config_path = dbt_cortex_agent.cortex_agent_eval_config_path(ref('agent_eval')) | trim -%}
    {%- set lines = run_query("select $1 from " ~ config_path) -%}
    {%- set content = lines.columns[0].values() | join('\n') -%}
    {%- if 'agent_params' not in content or '{{' in content or dataset.identifier | upper not in content | upper -%}
      {{ exceptions.raise_compiler_error("Evaluation config at " ~ config_path ~ " is missing or not rendered:\n" ~ content) }}
    {%- endif -%}
    {{ log("OK - evaluation config deployed: " ~ config_path, info=true) }}
  {%- endif -%}
{% endmacro %}
