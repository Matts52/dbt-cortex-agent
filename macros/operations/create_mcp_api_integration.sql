{% macro create_mcp_api_integration(
    integration_name,
    allowed_prefixes,
    auth_type='OAUTH_DYNAMIC_CLIENT',
    oauth_resource_url=none,
    oauth_client_id=none,
    oauth_client_secret=none,
    oauth_token_endpoint=none,
    oauth_authorization_endpoint=none,
    oauth_client_auth_method=none,
    oauth_discovery_url=none,
    oauth_refresh_token_validity=none,
    enabled=true,
    if_not_exists=false,
    dry_run=false,
    comment=none
) %}
{#-
--  Bootstrap operation: creates a Snowflake API INTEGRATION for an external MCP server.
--
--  Requires ACCOUNTADMIN or CREATE INTEGRATION account-level privilege. Run once
--  per MCP endpoint before `dbt build`:
--
--      -- Dynamic Client Registration (recommended for DCR-capable providers):
--      dbt run-operation create_mcp_api_integration --args '{
--        integration_name: jira_mcp_api_integration,
--        allowed_prefixes: ["https://mcp.atlassian.com"],
--        auth_type: OAUTH_DYNAMIC_CLIENT,
--        oauth_resource_url: "https://mcp.atlassian.com/v1/mcp"
--      }'
--
--      -- OAuth2 client credentials (for providers without DCR):
--      dbt run-operation create_mcp_api_integration --args '{
--        integration_name: my_mcp_api_integration,
--        allowed_prefixes: ["https://api.example.com/mcp"],
--        auth_type: OAUTH2,
--        oauth_client_id: "abc123",
--        oauth_client_secret: "s3cr3t",
--        oauth_token_endpoint: "https://api.example.com/oauth/token",
--        oauth_authorization_endpoint: "https://api.example.com/oauth/authorize"
--      }'
--
--  Parameters:
--    integration_name              string  Snowflake object name for the integration.
--    allowed_prefixes              list    Base URL(s) of the MCP server (matched as prefix).
--    auth_type                     string  'OAUTH_DYNAMIC_CLIENT' (default) or 'OAUTH2'.
--    oauth_resource_url            string  Required for OAUTH_DYNAMIC_CLIENT. MCP server URL.
--    oauth_client_id               string  Required for OAUTH2.
--    oauth_client_secret           string  Required for OAUTH2.
--    oauth_token_endpoint          string  Required for OAUTH2.
--    oauth_authorization_endpoint  string  Required for OAUTH2.
--    oauth_client_auth_method      string  Optional for OAUTH2: CLIENT_SECRET_BASIC | CLIENT_SECRET_POST.
--    oauth_discovery_url           string  Optional for OAUTH2: OIDC discovery URL.
--    oauth_refresh_token_validity  int     Optional for OAUTH2: refresh token validity (seconds).
--    enabled                       bool    ENABLED clause (default true).
--    if_not_exists                 bool    Use IF NOT EXISTS instead of OR REPLACE (default false).
--    dry_run                       bool    Log DDL without executing (default false).
--    comment                       string  Optional COMMENT clause.
-#}

  {%- set auth_type_upper = auth_type | upper -%}

  {%- if auth_type_upper not in ['OAUTH2', 'OAUTH_DYNAMIC_CLIENT'] -%}
    {{ exceptions.raise_compiler_error(
        "create_mcp_api_integration: unsupported auth_type '" ~ auth_type ~ "'. "
        ~ "Valid values: 'OAUTH_DYNAMIC_CLIENT', 'OAUTH2'."
    ) }}
  {%- endif -%}

  {%- if auth_type_upper == 'OAUTH_DYNAMIC_CLIENT' and oauth_resource_url is none -%}
    {{ exceptions.raise_compiler_error(
        "create_mcp_api_integration: 'oauth_resource_url' is required when auth_type='OAUTH_DYNAMIC_CLIENT'."
    ) }}
  {%- endif -%}

  {%- if auth_type_upper == 'OAUTH2' -%}
    {%- if oauth_client_id is none or oauth_client_secret is none
            or oauth_token_endpoint is none or oauth_authorization_endpoint is none -%}
      {{ exceptions.raise_compiler_error(
          "create_mcp_api_integration: auth_type='OAUTH2' requires "
          ~ "'oauth_client_id', 'oauth_client_secret', 'oauth_token_endpoint', "
          ~ "and 'oauth_authorization_endpoint'."
      ) }}
    {%- endif -%}
  {%- endif -%}

  {%- set prefixes_list = [allowed_prefixes] if allowed_prefixes is string else allowed_prefixes -%}
  {%- set quoted_prefixes = [] -%}
  {%- for p in prefixes_list -%}
    {%- do quoted_prefixes.append("'" ~ p ~ "'") -%}
  {%- endfor -%}

  {%- set ddl -%}
create {% if if_not_exists %}api integration if not exists{% else %}or replace api integration{% endif %} {{ integration_name }}
  api_provider = external_mcp
  api_allowed_prefixes = ({{ quoted_prefixes | join(', ') }})
  api_user_authentication = (
    type = {{ auth_type_upper }}
    {%- if auth_type_upper == 'OAUTH_DYNAMIC_CLIENT' %}
    oauth_resource_url = '{{ oauth_resource_url }}'
    {%- else %}
    oauth_client_id = '{{ oauth_client_id }}'
    oauth_client_secret = '{{ oauth_client_secret }}'
    oauth_token_endpoint = '{{ oauth_token_endpoint }}'
    oauth_authorization_endpoint = '{{ oauth_authorization_endpoint }}'
    {%- if oauth_client_auth_method is not none %}
    oauth_client_auth_method = {{ oauth_client_auth_method }}
    {%- endif %}
    {%- if oauth_discovery_url is not none %}
    oauth_discovery_url = '{{ oauth_discovery_url }}'
    {%- endif %}
    {%- if oauth_refresh_token_validity is not none %}
    oauth_refresh_token_validity = {{ oauth_refresh_token_validity }}
    {%- endif %}
    {%- endif %}
  )
  enabled = {{ 'TRUE' if enabled else 'FALSE' }}
  {%- if comment is not none %}
  comment = '{{ comment }}'
  {%- endif %}
  {%- endset -%}

  {%- if dry_run -%}
    {{ log("-- dry_run=true: DDL not executed\n" ~ ddl, info=true) }}
  {%- elif execute -%}
    {{ log("Creating API integration: " ~ integration_name, info=true) }}
    {%- do run_query(ddl) -%}
    {{ log("Successfully created API integration: " ~ integration_name, info=true) }}
  {%- endif -%}

{% endmacro %}
