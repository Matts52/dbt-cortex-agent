{% macro snowflake__get_create_cortex_mcp_api_integration_sql(relation) -%}
{#-
--  Produce the DDL that creates a Snowflake API INTEGRATION for an external
--  MCP server, from a config-only cortex_mcp_api_integration model.
--
--  The integration's Snowflake object name is the model's alias (relation
--  identifier) — the same convention cortex_mcp_server uses for its own name.
--
--  Required config:
--      allowed_prefixes  list[string]  Base URL(s) of the MCP server, matched as a prefix.
--
--  Optional config (see create_mcp_api_integration operation docs for full list):
--      auth_type, oauth_resource_url, oauth_client_id, oauth_client_secret,
--      oauth_token_endpoint, oauth_authorization_endpoint,
--      oauth_client_auth_method, oauth_discovery_url,
--      oauth_refresh_token_validity, enabled, if_not_exists, comment
--
--  `if_not_exists` defaults to `true` here (unlike the `create_mcp_api_integration`
--  operation, which defaults to `false`) — a materialization can be swept into a
--  routine `dbt build` (a broad selector, `state:modified.body`, `--full-refresh`)
--  without the caller directly intending to rebuild this specific node, so we
--  avoid blindly `OR REPLACE`-ing a live OAuth-authenticated integration as a
--  side effect. Pass `if_not_exists=false` explicitly to opt back into
--  `CREATE OR REPLACE` semantics (e.g. to rotate configuration deliberately).
--
--  Returns: a valid DDL statement that creates the API integration.
-#}
  {%- set integration_name = relation.identifier -%}

  {%- set _m = config.get('meta', {}).get('allowed_prefixes') -%}
  {%- set allowed_prefixes = _m if _m is not none else config.require('allowed_prefixes') -%}

  {%- set _m = config.get('meta', {}).get('auth_type') -%}
  {%- set auth_type = _m if _m is not none else config.get('auth_type', default='OAUTH_DYNAMIC_CLIENT') -%}

  {%- set _m = config.get('meta', {}).get('oauth_resource_url') -%}
  {%- set oauth_resource_url = _m if _m is not none else config.get('oauth_resource_url') -%}

  {%- set _m = config.get('meta', {}).get('oauth_client_id') -%}
  {%- set oauth_client_id = _m if _m is not none else config.get('oauth_client_id') -%}

  {%- set _m = config.get('meta', {}).get('oauth_client_secret') -%}
  {%- set oauth_client_secret = _m if _m is not none else config.get('oauth_client_secret') -%}

  {%- set _m = config.get('meta', {}).get('oauth_token_endpoint') -%}
  {%- set oauth_token_endpoint = _m if _m is not none else config.get('oauth_token_endpoint') -%}

  {%- set _m = config.get('meta', {}).get('oauth_authorization_endpoint') -%}
  {%- set oauth_authorization_endpoint = _m if _m is not none else config.get('oauth_authorization_endpoint') -%}

  {%- set _m = config.get('meta', {}).get('oauth_client_auth_method') -%}
  {%- set oauth_client_auth_method = _m if _m is not none else config.get('oauth_client_auth_method') -%}

  {%- set _m = config.get('meta', {}).get('oauth_discovery_url') -%}
  {%- set oauth_discovery_url = _m if _m is not none else config.get('oauth_discovery_url') -%}

  {%- set _m = config.get('meta', {}).get('oauth_refresh_token_validity') -%}
  {%- set oauth_refresh_token_validity = _m if _m is not none else config.get('oauth_refresh_token_validity') -%}

  {%- set _m = config.get('meta', {}).get('enabled') -%}
  {%- set enabled = _m if _m is not none else config.get('enabled', default=true) -%}

  {%- set _m = config.get('meta', {}).get('if_not_exists') -%}
  {%- set if_not_exists = _m if _m is not none else config.get('if_not_exists', default=true) -%}

  {%- set _m = config.get('meta', {}).get('comment') -%}
  {%- set comment = _m if _m is not none else config.get('comment') -%}

  {{ dbt_cortex_agent._mcp_api_integration_ddl(
      integration_name=integration_name,
      allowed_prefixes=allowed_prefixes,
      auth_type=auth_type,
      oauth_resource_url=oauth_resource_url,
      oauth_client_id=oauth_client_id,
      oauth_client_secret=oauth_client_secret,
      oauth_token_endpoint=oauth_token_endpoint,
      oauth_authorization_endpoint=oauth_authorization_endpoint,
      oauth_client_auth_method=oauth_client_auth_method,
      oauth_discovery_url=oauth_discovery_url,
      oauth_refresh_token_validity=oauth_refresh_token_validity,
      enabled=enabled,
      if_not_exists=if_not_exists,
      comment=comment
  ) }}
{%- endmacro %}


{% macro snowflake__create_or_replace_cortex_mcp_api_integration() %}
{#-
--  Orchestrates CREATE API INTEGRATION DDL for a model using the
--  `cortex_mcp_api_integration` materialization. Runs pre/post hooks around
--  the main statement.
--
--  Returns: {'relations': [target_relation]}
-#}
  {%- set identifier = model['alias'] -%}
  {%- set target_relation = api.Relation.create(
      identifier=identifier, schema=schema, database=database,
      type='view') -%}

  {{ run_hooks(pre_hooks) }}

  {% call statement('main') -%}
    {{ dbt_cortex_agent.snowflake__get_create_cortex_mcp_api_integration_sql(target_relation) }}
  {%- endcall %}

  {{ run_hooks(post_hooks) }}

  {{ return({'relations': [target_relation]}) }}

{% endmacro %}


{% macro cortex_mcp_api_integration_name(integration_ref) -%}
{#-
--  Returns the Snowflake object name for a cortex_mcp_api_integration model
--  given its ref(), so it can be wired into a cortex_mcp_server model's
--  `api_integration` config.
--
--  Calling ref() as the argument registers the DAG dependency (the MCP server
--  will not be created until the API integration exists).
--
--  API integrations are account-level objects with no database/schema, so
--  (unlike `cortex_mcp_server_name`) this returns a bare identifier, not a
--  dotted `database.schema.name`.
--
--  Usage in a cortex_mcp_server model's config:
--
--    {{ config(
--        materialized    = 'cortex_mcp_server',
--        display_name    = 'Atlassian (Jira & Confluence)',
--        url             = 'https://mcp.atlassian.com/v1/mcp',
--        api_integration = dbt_cortex_agent.cortex_mcp_api_integration_name(ref('jira_mcp_api_integration'))
--    ) }}
--
--  Args:
--  - integration_ref: Relation returned by ref() for the cortex_mcp_api_integration model
--
--  Returns: bare identifier string, e.g. 'jira_mcp_api_integration'
-#}
  {%- set model_name = integration_ref.identifier -%}
  {%- if execute -%}
    {%- set ns = namespace(found=false, alias='') -%}
    {%- for node in graph.nodes.values() -%}
      {%- if node.resource_type == 'model' and node.name == model_name -%}
        {%- set ns.found = true -%}
        {%- set ns.alias = node.alias -%}
      {%- endif -%}
    {%- endfor -%}
    {%- if not ns.found -%}
      {{ exceptions.raise_compiler_error(
          "cortex_mcp_api_integration_name: no model found for '" ~ model_name ~ "'. "
          ~ "Ensure it uses the cortex_mcp_api_integration materialization."
      ) }}
    {%- endif -%}
    {{- ns.alias -}}
  {%- else -%}
    {{- model_name -}}
  {%- endif -%}
{%- endmacro %}
