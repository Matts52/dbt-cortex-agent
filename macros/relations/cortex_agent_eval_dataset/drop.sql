{% macro snowflake__get_drop_cortex_agent_eval_dataset_sql(relation) %}
{#-
--  Drops the registered evaluation DATASET object for the given source-table
--  relation. The source table itself is dropped by dbt as usual.
-#}
drop dataset if exists {{ dbt_cortex_agent._cortex_eval_dataset_relation(relation) }}
{% endmacro %}
