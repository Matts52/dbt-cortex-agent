{% macro snowflake__get_drop_cortex_agent_eval_sql(relation) %}
{#-
--  Eval configs are files on a Snowflake stage, not SQL objects, so there is no
--  DROP statement. To remove a config, run:
--
--      REMOVE @<stage>/evals/<name>/config.yaml;
--
--  This macro is intentionally a no-op so dbt graph operations that call
--  drop_relation do not error.
-#}
{% endmacro %}
