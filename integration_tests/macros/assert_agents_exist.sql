{#-
--  Verifies that the agents created by `dbt build` actually exist in Snowflake.
--
--  Agents are not exposed through INFORMATION_SCHEMA, so existence must be
--  checked with SHOW AGENTS + RESULT_SCAN, which requires running two
--  statements in sequence — something a singular dbt test (a single SELECT)
--  can't do. This is implemented as a run-operation instead:
--
--      dbt run-operation assert_agents_exist --target snowflake
--
--  It raises a compiler error (non-zero exit) if any expected agent is missing,
--  so it can be wired into CI after `dbt build`.
-#}
{% macro assert_agents_exist() %}
  {%- if execute -%}
    {%- set expected = ['agent_minimal', 'agent_with_semantic_view', 'agent_raw_ddl'] -%}
    {%- for model_name in expected -%}
      {%- set rel = ref(model_name) -%}
      {%- do run_query("show agents like '" ~ rel.identifier ~ "' in schema " ~ rel.database ~ "." ~ rel.schema) -%}
      {%- set results = run_query("select count(*) as n from table(result_scan(last_query_id()))") -%}
      {%- set n = results.columns[0].values()[0] -%}
      {%- if n | int < 1 -%}
        {{ exceptions.raise_compiler_error("Expected agent not found: " ~ rel) }}
      {%- else -%}
        {{ log("OK - agent exists: " ~ rel, info=true) }}
      {%- endif -%}
    {%- endfor -%}
    {{ log("All expected agents exist.", info=true) }}
  {%- endif -%}
{% endmacro %}
