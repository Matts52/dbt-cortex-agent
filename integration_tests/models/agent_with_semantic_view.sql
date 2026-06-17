{{
  config(
    materialized = 'cortex_agent',
    comment      = 'Agent wired to a dbt-managed semantic view',
    profile      = {
      'display_name': 'Orders Analyst',
      'avatar': 'orders-icon.png',
      'color': 'blue'
    }
  )
}}
models:
  orchestration: claude-4-sonnet
orchestration:
  budget:
    seconds: 30
    tokens: 16000
instructions:
  response: "Respond in a friendly but concise manner."
  orchestration: "Use the Analyst tool for any question about orders or revenue."
  sample_questions:
    - question: "What is the total order amount by region?"
tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "OrdersAnalyst"
      description: "Answers questions about orders using the orders semantic view."
tool_resources:
  OrdersAnalyst:
    semantic_view: "{{ ref('orders_semantic_view') }}"
    execution_environment:
      type: "warehouse"
      warehouse: "{{ env_var('SNOWFLAKE_TEST_WAREHOUSE', 'COMPUTE_WH') }}"
