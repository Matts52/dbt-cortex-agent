{{
  config(
    materialized = 'cortex_agent',
    model        = 'claude-opus-4',
    budget       = { 'seconds': 30, 'tokens': 16000 }
  )
}}
instructions:
  response: "You are a helpful data assistant."
