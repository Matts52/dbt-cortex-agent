{% macro snowflake__get_drop_cortex_skill_sql(relation) %}
{#-
--  Skills are files on a Snowflake stage, not SQL objects, so there is no
--  DROP SKILL statement. To remove a skill's file, run:
--
--      REMOVE @<stage>/skills/<name>/SKILL.md;
--
--  This macro is intentionally a no-op so dbt graph operations that call
--  drop_relation do not error.
-#}
{% endmacro %}
