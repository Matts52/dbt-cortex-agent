{%- macro snowflake__get_cortex_mcp_api_integration_rename_sql(relation, new_name) -%}
{#-
--  Produce DDL that renames a Snowflake API INTEGRATION object.
--
--  Unlike EXTERNAL MCP SERVER (see cortex_mcp_server/rename.sql), API
--  INTEGRATION is a standard, long-documented Snowflake object type and
--  `ALTER ... RENAME TO` is supported for it.
--
--  Args:
--  - relation: SnowflakeRelation or str
--  - new_name: new identifier
--  Returns: DDL string
-#}
  alter api integration {{ relation }} rename to {{ new_name }}
{%- endmacro -%}
