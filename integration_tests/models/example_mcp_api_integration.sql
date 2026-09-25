{{
  config(
    materialized      = 'cortex_mcp_api_integration',
    meta              = {
      'allowed_prefixes':   ['https://mcp.example.com'],
      'auth_type':          'OAUTH_DYNAMIC_CLIENT',
      'oauth_resource_url': 'https://mcp.example.com/v1/mcp'
    }
  )
}}
