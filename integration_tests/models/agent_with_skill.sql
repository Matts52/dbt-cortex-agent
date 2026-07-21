{{
  config(
    materialized = 'cortex_agent',
    comment      = 'Agent with a skill (compile-only: no live stage in test env)',
    profile      = {'display_name': 'Skill Agent', 'color': 'purple'}
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
  orchestration: "Use the forecaster skill to answer forecasting questions."
skills:
  - name: forecaster
    source:
      type: STAGE
      path: "{{ dbt_cortex_agent.cortex_skill_path(ref('forecaster_skill')) }}"
