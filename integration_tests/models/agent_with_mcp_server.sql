{{
  config(
    materialized = 'cortex_agent',
    comment      = 'Agent with an MCP server wired via ref() for DAG lineage'
  )
}}
models:
  orchestration: claude-4-sonnet
orchestration:
  budget:
    seconds: 30
    tokens: 16000
instructions:
  response: "Be concise."
  orchestration: "Use the Atlassian MCP server to answer questions about Jira and Confluence."
mcp_servers:
  - server_spec:
      name: "{{ dbt_cortex_agent.cortex_mcp_server_name(ref('atlassian_mcp_server')) }}"
