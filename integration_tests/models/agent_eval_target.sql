{{
  config(
    materialized = 'cortex_agent',
    meta         = {
      'comment': 'Tool-free agent that the evaluation fixtures run against',
      'profile': {'display_name': 'Eval Target Agent', 'color': 'gray'}
    }
  )
}}
models:
  orchestration: auto
orchestration:
  budget:
    seconds: 30
    tokens: 8000
instructions:
  response: "Answer in one short sentence."
