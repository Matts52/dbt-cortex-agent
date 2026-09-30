{{
  config(
    materialized        = 'cortex_agent',
    code_execution_tool = true
  )
}}
models:
  orchestration: claude-4-sonnet
instructions:
  response: "Be concise."
  orchestration: "Use the code execution tool to perform calculations and data analysis."
