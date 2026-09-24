{{
  config(
    materialized = 'cortex_mcp_server',
    meta         = {
      'display_name':    'Atlassian (Jira & Confluence)',
      'url':             'https://mcp.atlassian.com/v1/mcp',
      'api_integration': dbt_cortex_agent.cortex_mcp_api_integration_name(ref('jira_mcp_api_integration'))
    }
  )
}}
