{% macro snowflake__get_drop_cortex_agent_sql(relation) %}
{#-
--  DDL to drop a Cortex Agent if it exists.
--
--  Args:
--      relation: SnowflakeRelation - the agent to drop
--  Returns: templated string
-#}
    drop agent if exists {{ relation }}
{% endmacro %}
