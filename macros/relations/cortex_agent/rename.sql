{%- macro snowflake__get_cortex_agent_rename_sql(relation, new_name) -%}
{#-
--  Rename or move a Cortex Agent to a new name.
--
--  Args:
--      relation: SnowflakeRelation - relation to be renamed
--      new_name: Union[str, SnowflakeRelation] - new name for `relation`
--  Returns: templated string
-#}
    alter agent if exists {{ relation }} rename to {{ new_name }}
{%- endmacro -%}
