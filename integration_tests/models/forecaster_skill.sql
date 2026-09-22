{{
  config(
    materialized = 'cortex_skill',
    meta         = {'stage': var('skill_stage', '@my_db.my_schema.skill_stage')}
  )
}}
