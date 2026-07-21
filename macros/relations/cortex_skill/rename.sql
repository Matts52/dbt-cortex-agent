{%- macro snowflake__get_cortex_skill_rename_sql(relation, new_name) -%}
{#-
--  Skills are files on a Snowflake stage, not SQL objects. Renaming a skill
--  requires moving the stage file manually:
--
--      COPY FILES INTO @<stage>/skills/<new_name>/ FROM @<stage>/skills/<old_name>/;
--      REMOVE @<stage>/skills/<old_name>/SKILL.md;
--
--  This macro is intentionally a no-op so dbt graph operations that call
--  rename_relation do not error.
-#}
{%- endmacro -%}
