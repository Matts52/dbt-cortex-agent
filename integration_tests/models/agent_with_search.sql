{{
  config(
    materialized = 'cortex_agent',
    comment      = 'Agent with a Cortex Search tool (compile-only: no live search service in test env)',
    profile      = {'display_name': 'Search Agent', 'color': 'teal'}
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
  orchestration: "Use PolicySearch for policy questions."
tools:
  - tool_spec:
      type: "cortex_search"
      name: "PolicySearch"
      description: "Searches policy documents."
tool_resources:
  PolicySearch:
    name: "{{ source('cortex_test', 'policy_search_service') }}"
    max_results: 5
    filter:
      "@eq":
        region: "North America"
    title_column: "title"
    id_column: "doc_id"
