{% macro _mcp_api_integration_exists(integration_name) -%}
{#-
--  Returns true if the named API integration exists in Snowflake.
--  Uses SHOW INTEGRATIONS + RESULT_SCAN (requires MONITOR USAGE or ACCOUNTADMIN).
--  Returns true at parse time to avoid blocking compilation.
-#}
  {%- if not execute -%}{{ return(true) }}{%- endif -%}
  {%- do run_query("show integrations like '" ~ integration_name ~ "'") -%}
  {%- set results = run_query("select count(*) as n from table(result_scan(last_query_id()))") -%}
  {{ return((results.columns[0].values()[0] | int) > 0) }}
{%- endmacro %}


{% macro snowflake__get_create_cortex_mcp_server_sql(relation) -%}
{#-
--  Produce the DDL that creates an External MCP Server object.
--
--  Required configs:
--  - display_name:    string — human-readable label for the MCP server
--  - url:             string — MCP server endpoint URL
--  - api_integration: string — name of the API integration object
--
--  Returns: a valid DDL statement that creates the external MCP server.
-#}
  {%- set display_name    = config.require('display_name') -%}
  {%- set url             = config.require('url') -%}
  {%- set api_integration = config.require('api_integration') -%}

  create or replace external mcp server {{ relation }}
    with display_name = {{ dbt_cortex_agent.cortex_agent_quote_string(display_name) }}
    url = {{ dbt_cortex_agent.cortex_agent_quote_string(url) }}
    api_integration = {{ api_integration }}

{%- endmacro %}


{% macro snowflake__create_or_replace_cortex_mcp_server() %}
{#-
--  Orchestrates CREATE EXTERNAL MCP SERVER DDL for a model using the
--  `cortex_mcp_server` materialization. Runs pre/post hooks around the main
--  statement.
--
--  Returns: {'relations': [target_relation]}
-#}
  {%- set identifier = model['alias'] -%}
  {%- set api_integration = config.require('api_integration') -%}

  {%- if execute and not dbt_cortex_agent._mcp_api_integration_exists(api_integration) -%}
    {{ exceptions.raise_compiler_error(
        "\n\ncortex_mcp_server: API integration '" ~ api_integration ~ "' does not exist "
        ~ "in Snowflake.\n\n"
        ~ "Bootstrap it first (requires ACCOUNTADMIN or CREATE INTEGRATION privilege):\n\n"
        ~ "    dbt run-operation create_mcp_api_integration --args '{\n"
        ~ "      integration_name: " ~ api_integration ~ ",\n"
        ~ "      allowed_prefixes: [\"<your-mcp-base-url>\"],\n"
        ~ "      auth_type: OAUTH_DYNAMIC_CLIENT,\n"
        ~ "      oauth_resource_url: \"<your-mcp-server-url>\"\n"
        ~ "    }'\n\n"
        ~ "See the README for full options including OAUTH2 (client credentials) mode."
    ) }}
  {%- endif -%}

  {%- set target_relation = api.Relation.create(
      identifier=identifier, schema=schema, database=database,
      type='view') -%}

  {{ run_hooks(pre_hooks) }}

  {% call statement('main') -%}
    {{ dbt_cortex_agent.snowflake__get_create_cortex_mcp_server_sql(target_relation) }}
  {%- endcall %}

  {{ run_hooks(post_hooks) }}

  {{ return({'relations': [target_relation]}) }}

{% endmacro %}


{% macro cortex_mcp_server_name(server_ref) -%}
{#-
--  Returns the fully-qualified dotted name for a cortex_mcp_server model given
--  its ref(), so it can be embedded in a cortex_agent's mcp_servers: section.
--
--  Calling ref() as the argument registers the DAG dependency (the agent will
--  not be created until the MCP server object exists), and the macro derives
--  the correct database.schema.name from the graph.
--
--  Usage in a cortex_agent model body:
--
--    mcp_servers:
--      - server_spec:
--          name: "{{ dbt_cortex_agent.cortex_mcp_server_name(ref('atlassian_mcp_server')) }}"
--
--  Args:
--  - server_ref: Relation returned by ref() for the cortex_mcp_server model
--
--  Returns: dotted name string, e.g. 'my_db.my_schema.atlassian_mcp_server'
-#}
  {%- set model_name = server_ref.identifier -%}
  {%- if execute -%}
    {%- set ns = namespace(fqn='') -%}
    {%- for node in graph.nodes.values() -%}
      {%- if node.resource_type == 'model' and node.name == model_name -%}
        {%- set ns.fqn = node.database ~ '.' ~ node.schema ~ '.' ~ node.name -%}
      {%- endif -%}
    {%- endfor -%}
    {%- if ns.fqn == '' -%}
      {{ exceptions.raise_compiler_error(
          "cortex_mcp_server_name: no model found for '" ~ model_name ~ "'. "
          ~ "Ensure it uses the cortex_mcp_server materialization."
      ) }}
    {%- endif -%}
    {{- ns.fqn -}}
  {%- else -%}
    {{- '__mcp_server_placeholder__.' ~ model_name -}}
  {%- endif -%}
{%- endmacro %}
