{#-
--  cortex_agent_eval materialization
--
--  Deploys a Cortex Agent evaluation to Snowflake: registers its dataset (if the
--  YAML declares one) and writes its config to a named stage so it can be run
--  with EXECUTE_AI_EVALUATION. Like cortex_skill, the model is a *deployment*
--  step for a stage file, not a SQL object. The model body IS the evaluation
--  YAML, and it is written to
--
--      <stage>/evals/<model_alias>/config.yaml
--
--  Evaluations themselves are not creatable objects, and running one is paid,
--  asynchronous work, so this materialization never starts a run. Use the
--  `run_cortex_agent_eval` run-operation for that.
--
--  Each eval is its own model, so different agents (or different eval sets for
--  the same agent) simply get their own model, each pointing at whatever table
--  holds its questions. The dataset can be ANY table or view in the project (a
--  seed, source, or model): nothing is copied.
--
--  The body uses Snowflake's own evaluation YAML. The optional `dataset:` block
--  is handled by the package instead of being sent to Snowflake: the dataset is
--  (re-)registered here and the block is removed from the uploaded file, so
--  repeated runs do not try to create the dataset again.
--
--  Required config:
--      stage  string  Fully-qualified stage path, e.g. '@my_db.my_schema.eval_stage'
--
--  Example (any .sql file in your models path):
--
--      {{ config(
--          materialized = 'cortex_agent_eval',
--          meta         = {'stage': '@my_db.my_schema.eval_stage'}
--      ) }}
--      dataset:
--        table_name: "{{ ref('support_questions') }}"   # seed, source, or model
--        dataset_name: "support_agent_golden"
--        column_mapping:
--          query_text: question
--          ground_truth: expected
--      evaluation:
--        agent_params:
--          agent_name: "{{ ref('support_agent') }}"
--          agent_type: "CORTEX AGENT"
--        source_metadata:
--          type: "dataset"
--          dataset_name: "support_agent_golden"
--      metrics:
--        - "answer_correctness"
--        - "logical_consistency"
--
--  Custom-metric prompts contain {{output}}-style placeholders that Snowflake
--  fills in, so wrap them in {% raw %} ... {% endraw %} to stop dbt rendering them.
--
--  See macros/relations/cortex_agent_eval/create.sql for the dataset registration
--  and upload SQL, and the README for usage and config options.
-#}

{% materialization cortex_agent_eval, adapter='snowflake' -%}

    {% set original_query_tag = set_query_tag() %}

    {% do dbt_cortex_agent.snowflake__create_or_replace_cortex_agent_eval() %}

    {#-
    --  The eval config is a stage file, not a SQL object. We track the node as
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
--  Renders the stage upload statement without executing it, so `dbt compile`
--  works on any adapter (e.g. DuckDB) and the compiled SQL is inspectable in
--  target/compiled/.
-#}
{% materialization cortex_agent_eval, default -%}

    {%- set identifier  = model['alias'] -%}
    {%- set stage       = dbt_cortex_agent._cortex_eval_cfg('stage', '@my_db.my_schema.eval_stage') -%}
    {%- set config_path = stage ~ '/evals/' ~ identifier ~ '/config.yaml' -%}

    {%- set target_relation = api.Relation.create(
        identifier=identifier, schema=schema, database=database,
        type='view') -%}

    {% call statement('main') -%}
        {{ dbt_cortex_agent.snowflake__get_create_cortex_agent_eval_sql(target_relation, sql, config_path) }}
    {%- endcall %}

    {% do return({'relations': [target_relation]}) %}

{%- endmaterialization %}
