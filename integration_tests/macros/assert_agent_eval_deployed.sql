{#-
--  Verifies that `dbt build` deployed the evaluation fixture:
--
--    * the dataset declared in agent_eval's `dataset:` block is registered, and
--      its text ground-truth column was cast through the `_source` view
--    * the config file on the stage is fully rendered: refs resolved, the dataset
--      name qualified, the `dataset:` block removed, and the custom-metric
--      placeholders left intact
--
--      dbt run-operation assert_agent_eval_deployed --target snowflake
--
--  It raises a compiler error (non-zero exit) if a check fails, so it can be
--  wired into CI after `dbt build`. It does not start an evaluation run, which
--  is paid, asynchronous work.
-#}
{% macro assert_agent_eval_deployed() %}
  {%- if execute -%}
    {%- set eval_rel = ref('agent_eval') -%}
    {%- set dataset = eval_rel.database ~ '.' ~ eval_rel.schema ~ '.agent_eval_dataset' -%}
    {%- do run_query("show datasets like 'AGENT_EVAL_DATASET' in schema " ~ eval_rel.database ~ "." ~ eval_rel.schema) -%}
    {%- set n = run_query("select count(*) from table(result_scan(last_query_id()))").columns[0].values()[0] -%}
    {%- if n | int < 1 -%}
      {{ exceptions.raise_compiler_error("Expected evaluation dataset not found: " ~ dataset) }}
    {%- endif -%}
    {%- set view_rows = run_query("select count(*) from " ~ dataset ~ "_source where typeof(ground_truth) = 'OBJECT'").columns[0].values()[0] -%}
    {%- if view_rows | int != 2 -%}
      {{ exceptions.raise_compiler_error("Expected 2 parsed ground-truth rows in " ~ dataset ~ "_source, found " ~ view_rows) }}
    {%- endif -%}
    {{ log("OK - evaluation dataset registered with parsed ground truth: " ~ dataset, info=true) }}

    {%- set config_path = dbt_cortex_agent.cortex_agent_eval_config_path(eval_rel) | trim -%}
    {%- set lines = run_query("select $1 from " ~ config_path) -%}
    {%- set content = lines.columns[0].values() | join('\n') -%}
    {%- if 'agent_params' not in content or 'dataset_type' in content or 'column_mapping' in content
           or '{{output}}' not in content or (dataset | upper) not in (content | upper) -%}
      {{ exceptions.raise_compiler_error("Evaluation config at " ~ config_path ~ " is missing or not rendered as expected:\n" ~ content) }}
    {%- endif -%}
    {{ log("OK - evaluation config deployed: " ~ config_path, info=true) }}
  {%- endif -%}
{% endmacro %}
