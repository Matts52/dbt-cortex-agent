{{
  config(
    materialized = 'cortex_agent_eval_dataset'
  )
}}
select 'What is 2 plus 2?' as query_text,
       parse_json('{"ground_truth_output": "4"}') as ground_truth
union all
select 'What is the capital of France?' as query_text,
       parse_json('{"ground_truth_output": "Paris"}') as ground_truth
