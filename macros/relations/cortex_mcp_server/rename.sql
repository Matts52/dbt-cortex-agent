{%- macro snowflake__get_cortex_mcp_server_rename_sql(relation, new_name) -%}
{#-
--  Renaming an External MCP Server is not supported via ALTER DDL.
--  To rename, drop and recreate the server with the new name.
--
--  This macro is intentionally a no-op so dbt graph operations that call
--  rename_relation do not error.
-#}
{%- endmacro -%}
