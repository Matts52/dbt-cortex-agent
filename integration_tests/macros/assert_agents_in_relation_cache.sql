{#-
--  Verifies that dbt's relation lookup finds the agents built by `dbt build`, which is what
--  `--defer` checks before falling back to the deferred (production) relation. Without the
--  package's snowflake__list_relations_without_caching (enabled by the dispatch config in
--  dbt_project.yml), SHOW OBJECTS leaves agents out and get_relation returns none.
--
--      dbt run-operation assert_agents_in_relation_cache --target snowflake
-#}
{% macro assert_agents_in_relation_cache() %}
  {%- if execute -%}
    {%- for model_name in ['agent_minimal', 'agent_with_semantic_view'] -%}
      {%- set rel = ref(model_name) -%}
      {%- if adapter.get_relation(rel.database, rel.schema, rel.identifier) is none -%}
        {{ exceptions.raise_compiler_error("Agent not in the relation cache, --defer would skip it: " ~ rel) }}
      {%- else -%}
        {{ log("OK - agent in the relation cache: " ~ rel, info=true) }}
      {%- endif -%}
    {%- endfor -%}
  {%- endif -%}
{% endmacro %}
