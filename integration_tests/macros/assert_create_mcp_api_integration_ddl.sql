{#-
--  Validates that create_mcp_api_integration produces correct DDL for both
--  OAUTH_DYNAMIC_CLIENT and OAUTH2 auth types by running in dry_run mode and
--  checking the logged output structure.
--
--  Raises a compiler error if any expected keyword is missing.
--
--  Usage:
--      dbt run-operation assert_create_mcp_api_integration_ddl --target snowflake
-#}
{% macro assert_create_mcp_api_integration_ddl() %}
  {%- if execute -%}

    {#- Case 1: OAUTH_DYNAMIC_CLIENT (DCR) -#}
    {%- set dcr_ddl -%}
      {{- dbt_cortex_agent.create_mcp_api_integration(
          integration_name='test_dcr_integration',
          allowed_prefixes=['https://mcp.atlassian.com'],
          auth_type='OAUTH_DYNAMIC_CLIENT',
          oauth_resource_url='https://mcp.atlassian.com/v1/mcp',
          dry_run=true
      ) -}}
    {%- endset -%}

    {%- set dcr_ddl_lower = dcr_ddl | lower -%}
    {%- set dcr_checks = [
        ('create or replace api integration', 'OR REPLACE clause'),
        ('api_provider = external_mcp', 'api_provider'),
        ('api_allowed_prefixes', 'api_allowed_prefixes'),
        ('https://mcp.atlassian.com', 'allowed prefix URL'),
        ('type = oauth_dynamic_client', 'auth type'),
        ('oauth_resource_url', 'oauth_resource_url'),
        ('https://mcp.atlassian.com/v1/mcp', 'resource URL'),
        ('enabled = true', 'enabled clause')
    ] -%}

    {%- for (keyword, label) in dcr_checks -%}
      {%- if keyword not in dcr_ddl_lower -%}
        {{ exceptions.raise_compiler_error(
            "assert_create_mcp_api_integration_ddl [DCR]: expected '" ~ label ~ "' ("
            ~ keyword ~ ") not found in DDL output."
        ) }}
      {%- endif -%}
    {%- endfor -%}

    {{ log("OK - OAUTH_DYNAMIC_CLIENT DDL contains all expected clauses.", info=true) }}

    {#- Case 2: OAUTH2 client credentials -#}
    {%- set oauth2_ddl -%}
      {{- dbt_cortex_agent.create_mcp_api_integration(
          integration_name='test_oauth2_integration',
          allowed_prefixes=['https://api.example.com/mcp'],
          auth_type='OAUTH2',
          oauth_client_id='my_client_id',
          oauth_client_secret='my_client_secret',
          oauth_token_endpoint='https://api.example.com/oauth/token',
          oauth_authorization_endpoint='https://api.example.com/oauth/authorize',
          dry_run=true
      ) -}}
    {%- endset -%}

    {%- set oauth2_ddl_lower = oauth2_ddl | lower -%}
    {%- set oauth2_checks = [
        ('create or replace api integration', 'OR REPLACE clause'),
        ('api_provider = external_mcp', 'api_provider'),
        ('type = oauth2', 'auth type'),
        ('oauth_client_id', 'oauth_client_id'),
        ('oauth_client_secret', 'oauth_client_secret'),
        ('oauth_token_endpoint', 'oauth_token_endpoint'),
        ('oauth_authorization_endpoint', 'oauth_authorization_endpoint'),
        ('enabled = true', 'enabled clause')
    ] -%}

    {%- for (keyword, label) in oauth2_checks -%}
      {%- if keyword not in oauth2_ddl_lower -%}
        {{ exceptions.raise_compiler_error(
            "assert_create_mcp_api_integration_ddl [OAUTH2]: expected '" ~ label ~ "' ("
            ~ keyword ~ ") not found in DDL output."
        ) }}
      {%- endif -%}
    {%- endfor -%}

    {{ log("OK - OAUTH2 DDL contains all expected clauses.", info=true) }}

    {#- Case 3: IF NOT EXISTS flag -#}
    {%- set ine_ddl -%}
      {{- dbt_cortex_agent.create_mcp_api_integration(
          integration_name='test_ine_integration',
          allowed_prefixes=['https://mcp.example.com'],
          auth_type='OAUTH_DYNAMIC_CLIENT',
          oauth_resource_url='https://mcp.example.com/v1/mcp',
          if_not_exists=true,
          dry_run=true
      ) -}}
    {%- endset -%}

    {%- if 'if not exists' not in ine_ddl | lower -%}
      {{ exceptions.raise_compiler_error(
          "assert_create_mcp_api_integration_ddl [IF NOT EXISTS]: "
          ~ "'if not exists' not found in DDL output."
      ) }}
    {%- endif -%}

    {%- if 'or replace' in ine_ddl | lower -%}
      {{ exceptions.raise_compiler_error(
          "assert_create_mcp_api_integration_ddl [IF NOT EXISTS]: "
          ~ "'or replace' must NOT appear when if_not_exists=true."
      ) }}
    {%- endif -%}

    {{ log("OK - IF NOT EXISTS DDL uses correct clause.", info=true) }}

    {{ log("All create_mcp_api_integration DDL assertions passed.", info=true) }}

  {%- endif -%}
{% endmacro %}
