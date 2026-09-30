{% macro _cortex_eval_dataset_relation(relation) -%}
{#-
--  The DATASET object registered for a cortex_agent_eval_dataset model. It is a
--  separate object from the source table, created in the same database and
--  schema (a schema can hold a table and a dataset with different names).
-#}
  {%- set custom = dbt_cortex_agent._cortex_eval_cfg('dataset_name') -%}
  {{- return(api.Relation.create(
        database=relation.database, schema=relation.schema,
        identifier=(custom if custom else relation.identifier ~ '_dataset'))) -}}
{%- endmacro %}


{% macro snowflake__create_or_replace_cortex_agent_eval_dataset() %}
{#-
--  Builds the source table and (re-)registers the evaluation dataset for a model
--  that uses the `cortex_agent_eval_dataset` materialization. Runs pre/post
--  hooks around the main statement.
--
--  Returns: {'relations': [target_relation]}
-#}
  {%- set target_relation = this.incorporate(type='table') -%}

  {{ run_hooks(pre_hooks) }}

  {% call statement('main') -%}
    {{ dbt_cortex_agent.snowflake__get_create_cortex_agent_eval_dataset_table_sql(target_relation, sql) }}
  {%- endcall %}

  -- CREATE_EVALUATION_DATASET fails if the dataset already exists, so drop first
  {%- set dataset_relation = dbt_cortex_agent._cortex_eval_dataset_relation(target_relation) -%}
  {%- do run_query("drop dataset if exists " ~ dataset_relation) -%}
  {%- do run_query(dbt_cortex_agent.snowflake__get_register_cortex_agent_eval_dataset_sql(target_relation, dataset_relation)) -%}

  {{ run_hooks(post_hooks) }}

  {{ return({'relations': [target_relation]}) }}

{% endmacro %}


{% macro snowflake__get_create_cortex_agent_eval_dataset_sql(relation, sql) -%}
{#-
--  Produce all statements for a cortex_agent_eval_dataset model: the source
--  table and the dataset registration. Used by the compile-only stub
--  materialization, where they are rendered but not executed.
-#}
  {{ dbt_cortex_agent.snowflake__get_create_cortex_agent_eval_dataset_table_sql(relation, sql) }};

  drop dataset if exists {{ dbt_cortex_agent._cortex_eval_dataset_relation(relation) }};

  {{ dbt_cortex_agent.snowflake__get_register_cortex_agent_eval_dataset_sql(
       relation, dbt_cortex_agent._cortex_eval_dataset_relation(relation)) }}
{%- endmacro %}


{% macro snowflake__get_create_cortex_agent_eval_dataset_table_sql(relation, sql) -%}
  create or replace table {{ relation }} as (
{{ sql }}
  )
{%- endmacro %}


{% macro snowflake__get_register_cortex_agent_eval_dataset_sql(relation, dataset_relation) -%}
{#-
--  Produce the SYSTEM$CREATE_EVALUATION_DATASET call that registers the source
--  table as a Cortex Agent evaluation dataset.
--
--  Note the column-mapping key for ground truth is `expected_tools` in this SQL
--  interface, but `ground_truth` in the evaluation YAML's dataset block.
-#}
  {%- set query_col = dbt_cortex_agent._cortex_eval_cfg('query_text_column', 'query_text') -%}
  {%- set truth_col = dbt_cortex_agent._cortex_eval_cfg('ground_truth_column', 'ground_truth') -%}
  call system$create_evaluation_dataset(
    'Cortex Agent',
    '{{ relation }}',
    '{{ dataset_relation }}',
    object_construct('query_text', '{{ query_col }}', 'expected_tools', '{{ truth_col }}')
  )
{%- endmacro %}


{% macro cortex_agent_eval_dataset_name(dataset_ref) -%}
{#-
--  Returns the DATASET object (a Relation, which renders as the fully-qualified name) for a
--  cortex_agent_eval_dataset model given its ref(), so it can be used as
--  `source_metadata.dataset_name` in an evaluation YAML.
--
--  Calling ref() as the argument registers the DAG dependency, so the dataset
--  is registered before the eval config that points at it is deployed.
--
--  Usage in a cortex_agent_eval model body:
--
--    source_metadata:
--      type: "dataset"
--      dataset_name: "{{ dbt_cortex_agent.cortex_agent_eval_dataset_name(ref('support_agent_questions')) }}"
-#}
  {%- if execute -%}
    {%- set ns = namespace(custom='') -%}
    {%- for node in graph.nodes.values() -%}
      {%- if node.resource_type == 'model' and node.name == dataset_ref.identifier -%}
        {%- set ns.custom = node.config.get('meta', {}).get('dataset_name') or node.config.get('dataset_name', '') -%}
      {%- endif -%}
    {%- endfor -%}
    {{- return(api.Relation.create(
          database=dataset_ref.database, schema=dataset_ref.schema,
          identifier=(ns.custom if ns.custom else dataset_ref.identifier ~ '_dataset'))) -}}
  {%- else -%}
    {{- return(dataset_ref.database ~ '.' ~ dataset_ref.schema ~ '.' ~ dataset_ref.identifier ~ '_dataset') -}}
  {%- endif -%}
{%- endmacro %}
