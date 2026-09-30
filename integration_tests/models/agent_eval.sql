{{
  config(
    materialized = 'cortex_agent_eval',
    meta         = {'stage': var('eval_stage', '@my_db.my_schema.eval_stage')}
  )
}}
dataset:
  dataset_type: "CORTEX AGENT"
  table_name: "{{ ref('agent_eval_questions') }}"
  dataset_name: "agent_eval_dataset"
  column_mapping:
    query_text: "prompt"
    ground_truth: "expected"
evaluation:
  agent_params:
    agent_name: "{{ ref('agent_eval_target') }}"
    agent_type: "CORTEX AGENT"
  run_params:
    label: "integration test"
    description: "Evaluation config deployed by the cortex_agent_eval materialization."
  source_metadata:
    type: "dataset"
    dataset_name: "agent_eval_dataset"
metrics:
  - "answer_correctness"
  - "logical_consistency"
  - name: "brevity"
    model: "claude-sonnet-4-6"
    score_ranges:
      min_score: [0, 3]
      median_score: [4, 6]
      max_score: [7, 10]
    prompt: |
      {% raw %}Score how brief {{output}} is for the question {{input}}. Ground truth: {{ground_truth}}.{% endraw %}
