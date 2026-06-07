{{
  config(
    materialized = 'cortex_agent',
    comment      = 'Minimal integration-test agent',
    profile      = {'display_name': 'Minimal Agent', 'color': 'gray'}
  )
}}
models:
  orchestration: claude-4-sonnet
orchestration:
  budget:
    seconds: 30
    tokens: 16000
instructions:
  response: "Respond concisely."
  orchestration: "Answer directly; you have no tools."
  sample_questions:
    - question: "What can you help me with?"
