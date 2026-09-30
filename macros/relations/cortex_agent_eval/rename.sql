{%- macro snowflake__get_cortex_agent_eval_rename_sql(relation, new_name) -%}
{#-
--  Eval configs are files on a Snowflake stage, not SQL objects. Renaming one
--  means moving the stage file manually:
--
--      COPY FILES INTO @<stage>/evals/<new_name>/ FROM @<stage>/evals/<old_name>/;
--      REMOVE @<stage>/evals/<old_name>/config.yaml;
--
--  This macro is intentionally a no-op so dbt graph operations that call
--  rename_relation do not error.
-#}
{%- endmacro -%}
