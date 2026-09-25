{{
  config(
    materialized = 'cortex_agent',
    meta         = {'comment': 'Agent with an MCP server wired via ref() for DAG lineage'}
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
  orchestration: "Use the example MCP server to answer questions."
mcp_servers:
  - server_spec:
      name: "{{ dbt_cortex_agent.cortex_mcp_server_name(ref('example_mcp_server')) }}"
