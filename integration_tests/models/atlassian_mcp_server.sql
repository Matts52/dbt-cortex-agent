{{
  config(
    materialized    = 'cortex_mcp_server',
    display_name    = 'Atlassian (Jira & Confluence)',
    url             = 'https://mcp.atlassian.com/v1/mcp',
    api_integration = 'jira_mcp_api_integration'
  )
}}
