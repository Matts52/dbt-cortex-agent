{{
  config(
    materialized = 'cortex_agent',
    meta         = {
      'comment':            'Agent with analytical search enabled (compile-only: no live search service in test env)',
      'analytical_search':  true,
      'budget':             {'seconds': 30, 'tokens': 16000}
    }
  )
}}
instructions:
  response: "Analyze search results thoroughly."
tools:
  - tool_spec:
      type: "cortex_search"
      name: "PolicySearch"
      description: "Searches policy documents."
tool_resources:
  PolicySearch:
    name: "{{ source('cortex_test', 'policy_search_service') }}"
    max_results: 1000
