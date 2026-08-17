{% macro snowflake__get_drop_cortex_mcp_server_sql(relation) %}
{#-
--  Produce DDL that drops an External MCP Server object.
--
--  !! SYNTAX NEEDS VERIFICATION against live Snowflake docs.
--  Best-guess candidate:
--
--      DROP EXTERNAL MCP SERVER IF EXISTS <name>
--
--  Args:
--  - relation: SnowflakeRelation or str
--  Returns: DDL string
-#}
  drop external mcp server if exists {{ relation }}
{% endmacro %}
