{{
  config(
    materialized      = 'cortex_mcp_api_integration',
    meta              = {
      'allowed_prefixes':   ['https://mcp.atlassian.com'],
      'auth_type':          'OAUTH_DYNAMIC_CLIENT',
      'oauth_resource_url': 'https://mcp.atlassian.com/v1/mcp'
    }
  )
}}
