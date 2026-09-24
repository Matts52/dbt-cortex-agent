{{
  config(
    materialized = 'cortex_mcp_server',
    meta         = {
      'display_name':    'Example MCP Server',
      'url':             'https://mcp.example.com/v1/mcp',
      'api_integration': dbt_cortex_agent.cortex_mcp_api_integration_name(ref('example_mcp_api_integration'))
    }
  )
}}
