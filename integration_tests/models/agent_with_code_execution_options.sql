{{
  config(
    materialized = 'cortex_agent',
    meta         = {
      'comment': 'Agent with code execution (map form) combined with an existing tools block',
      'code_execution_tool': {
        'permission_policy': 'always_allow',
        'artifact_repositories': ['SNOWFLAKE.SNOWPARK.PYPI_SHARED_REPOSITORY']
      }
    }
  )
}}
models:
  orchestration: claude-4-sonnet
instructions:
  response: "Be concise."
  orchestration: "Use PolicySearch for policy questions and code execution for calculations."
tools:
  - tool_spec:
      type: "cortex_search"
      name: "PolicySearch"
      description: "Searches policy documents."
tool_resources:
  PolicySearch:
    name: "{{ source('cortex_test', 'policy_search_service') }}"
    max_results: 5
