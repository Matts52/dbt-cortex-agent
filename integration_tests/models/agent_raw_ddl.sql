{{ config(materialized='cortex_agent', raw_ddl=true) }}
comment = 'Raw-DDL pass-through integration-test agent'
profile = '{"display_name": "Raw DDL Agent", "color": "green"}'
from specification
$$
models:
  orchestration: claude-4-sonnet
instructions:
  response: "Be concise."
  sample_questions:
    - question: "Hello?"
$$
