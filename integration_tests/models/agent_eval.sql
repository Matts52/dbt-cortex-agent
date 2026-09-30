{{
  config(
    materialized = 'cortex_agent_eval',
    meta         = {'stage': var('eval_stage', '@my_db.my_schema.eval_stage')}
  )
}}
evaluation:
  agent_params:
    agent_name: "{{ ref('agent_eval_target') }}"
    agent_type: "CORTEX AGENT"
  run_params:
    label: "integration test"
    description: "Evaluation config deployed by the cortex_agent_eval materialization."
  source_metadata:
    type: "dataset"
    dataset_name: "{{ dbt_cortex_agent.cortex_agent_eval_dataset_name(ref('agent_eval_questions')) }}"
metrics:
  - "answer_correctness"
  - "logical_consistency"
