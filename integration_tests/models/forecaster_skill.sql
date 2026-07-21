{{
  config(
    materialized = 'cortex_skill',
    stage        = var('skill_stage', '@my_db.my_schema.skill_stage')
  )
}}
