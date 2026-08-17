{#-
--  cortex_mcp_server materialization
--
--  Creates (or replaces) a Snowflake External MCP Server object from a dbt
--  model. The model body is empty (config-only); all parameters are supplied
--  via config().
--
--  Required configs:
--      display_name    string  Human-readable label for the MCP server
--      url             string  MCP server endpoint URL
--      api_integration string  Name of the API integration object in Snowflake
--
--  Example:
--
--      {{ config(
--          materialized    = 'cortex_mcp_server',
--          display_name    = 'Atlassian (Jira & Confluence)',
--          url             = 'https://mcp.atlassian.com/v1/mcp',
--          api_integration = 'jira_mcp_api_integration'
--      ) }}
--
--  To reference this server from a cortex_agent model body, use:
--
--      mcp_servers:
--        - server_spec:
--            name: "{{ dbt_cortex_agent.cortex_mcp_server_name(ref('my_mcp_server')) }}"
--
--  See macros/relations/cortex_mcp_server/create.sql for the DDL construction
--  and the README for usage and config options.
-#}

{% materialization cortex_mcp_server, adapter='snowflake' -%}

    {% set original_query_tag = set_query_tag() %}

    {% do dbt_cortex_agent.snowflake__create_or_replace_cortex_mcp_server() %}

    {#-
    --  Snowflake EXTERNAL MCP SERVER objects are not (yet) a first-class dbt
    --  relation type, so we incorporate the node as a `view` purely so that
    --  dbt can track it in the graph and downstream `ref()`s resolve. dbt never
    --  issues view DDL for this node.
    -#}
    {% set target_relation = this.incorporate(type='view') %}

    {% do unset_query_tag(original_query_tag) %}

    {% do return({'relations': [target_relation]}) %}

{%- endmaterialization %}


{#-
--  Default (non-Snowflake) stub materialization.
--
--  Renders the CREATE EXTERNAL MCP SERVER DDL without executing it, so
--  `dbt compile` works on any adapter (e.g. DuckDB) and the compiled SQL is
--  inspectable in target/compiled/.
-#}
{% materialization cortex_mcp_server, default -%}

    {%- set identifier = model['alias'] -%}
    {%- set target_relation = api.Relation.create(
        identifier=identifier, schema=schema, database=database,
        type='view') -%}

    {% call statement('main') -%}
        {{ dbt_cortex_agent.snowflake__get_create_cortex_mcp_server_sql(target_relation) }}
    {%- endcall %}

    {% do return({'relations': [target_relation]}) %}

{%- endmaterialization %}
