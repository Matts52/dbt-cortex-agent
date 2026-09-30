{#-
--  cortex_agent_eval_dataset materialization
--
--  Builds the golden question set for a Cortex Agent evaluation as a table and
--  registers it as an evaluation DATASET object with
--  SYSTEM$CREATE_EVALUATION_DATASET.
--
--  The model body is a SELECT that returns the question and its ground truth:
--
--      query_text    VARCHAR  the question sent to the agent
--      ground_truth  VARIANT  JSON with any of: ground_truth_output (string),
--                             ground_truth_invocations (array of
--                             {tool_name, tool_input, tool_output}), plus any
--                             keys read by custom metrics
--
--  Snowflake refuses to create a dataset whose name already exists, so each
--  run drops and re-registers the dataset. That keeps it in sync with the
--  rebuilt table and makes `dbt build` idempotent.
--
--  Optional configs (top-level or under `meta`):
--      dataset_name         string  Dataset object name (default: <model_alias>_dataset,
--                                   created in the model's database and schema)
--      query_text_column    string  Column holding the question (default: query_text)
--      ground_truth_column  string  Column holding the ground truth (default: ground_truth)
--
--  Example (models/evals/support_agent_questions.sql):
--
--      {{ config(materialized = 'cortex_agent_eval_dataset') }}
--      select 'What is our refund window?' as query_text,
--             parse_json('{"ground_truth_output": "30 days"}') as ground_truth
--
--  Reference the dataset from an eval config with:
--
--      {{ dbt_cortex_agent.cortex_agent_eval_dataset_name(ref('support_agent_questions')) }}
--
--  See macros/relations/cortex_agent_eval_dataset/create.sql for the SQL.
-#}

{% materialization cortex_agent_eval_dataset, adapter='snowflake' -%}

    {% set original_query_tag = set_query_tag() %}

    {% do dbt_cortex_agent.snowflake__create_or_replace_cortex_agent_eval_dataset() %}

    {% set target_relation = this.incorporate(type='table') %}

    {% do unset_query_tag(original_query_tag) %}

    {% do return({'relations': [target_relation]}) %}

{%- endmaterialization %}


{#-
--  Default (non-Snowflake) stub materialization.
--
--  Renders the source-table and dataset-registration SQL without executing it,
--  so `dbt compile` works on any adapter (e.g. DuckDB).
-#}
{% materialization cortex_agent_eval_dataset, default -%}

    {%- set target_relation = api.Relation.create(
        identifier=model['alias'], schema=schema, database=database,
        type='table') -%}

    {% call statement('main') -%}
        {{ dbt_cortex_agent.snowflake__get_create_cortex_agent_eval_dataset_sql(target_relation, sql) }}
    {%- endcall %}

    {% do return({'relations': [target_relation]}) %}

{%- endmaterialization %}
