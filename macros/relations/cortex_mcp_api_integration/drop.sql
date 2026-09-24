{% macro snowflake__get_drop_cortex_mcp_api_integration_sql(relation) %}
{#-
--  Produce DDL that drops a Snowflake API INTEGRATION object.
--
--  Args:
--  - relation: SnowflakeRelation or str
--  Returns: DDL string
-#}
  drop api integration if exists {{ relation }}
{% endmacro %}
