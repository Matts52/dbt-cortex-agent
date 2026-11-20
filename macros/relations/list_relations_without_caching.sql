{#-
--  dbt-snowflake builds its relation cache from SHOW OBJECTS, which does not return
--  Cortex agents or Cortex Search Services. dbt then thinks they do not exist in the
--  target, so `--defer` always resolves ref() to the deferred (production) object,
--  even when a dev / CI copy exists.
--
--  This override returns the same SHOW OBJECTS result plus the agents and search
--  services of the schema, tracked as `view` like the materializations do. It is
--  opt-in: add the package to the `dbt` dispatch search order in dbt_project.yml.
--
--      dispatch:
--        - macro_namespace: dbt
--          search_order: ['<your_project>', 'dbt_cortex_agent', 'dbt']
--
--  The body up to the cortex objects mirrors dbt-snowflake's
--  snowflake__list_relations_without_caching (pagination over SHOW OBJECTS).
-#}
{% macro snowflake__list_relations_without_caching(schema_relation, max_iter=10000, max_results_per_iter=10000) %}

    {%- set schema = schema_relation if schema_relation is string else schema_relation.include(identifier=False) -%}
    {%- set max_results_per_iter = adapter.config.flags.get('list_relations_per_page', max_results_per_iter) -%}
    {%- set max_iter = adapter.config.flags.get('list_relations_page_limit', max_iter) -%}

    {%- set paginated_state = namespace(paginated_results=[], watermark=none) -%}
    {%- for _ in range(max_iter + 1) -%}
        {%- if loop.index == max_iter + 1 -%}
            {%- do exceptions.warn(
                'dbt is configured to list at most ' ~ (max_results_per_iter * max_iter) ~ ' objects per schema; '
                ~ schema ~ ' exceeds this limit. Set list_relations_per_page and list_relations_page_limit in your project flags.'
            ) -%}
            {%- break -%}
        {%- endif -%}
        {%- set paginated_result = run_query(snowflake__show_objects_sql(schema, max_results_per_iter, paginated_state.watermark)) -%}
        {%- set paginated_result = adapter.normalize_show_objects_result(paginated_result) -%}
        {%- do paginated_state.paginated_results.append(paginated_result) -%}
        {%- if (paginated_result | length) < max_results_per_iter -%}
            {%- break -%}
        {%- endif -%}
        {%- set paginated_state.watermark = paginated_result.columns.get('name').values()[-1] -%}
    {%- endfor -%}

    {#- Cortex objects that SHOW OBJECTS leaves out -#}
    {%- for show_command in ['show agents in ' ~ schema, 'show cortex search services in ' ~ schema] -%}
        {%- set cortex_objects = run_query(
            show_command ~ ' ->> select "database_name", "schema_name", "name",'
            ~ ' \'VIEW\' as "kind", \'N\' as "is_dynamic", \'N\' as "is_iceberg" from $1'
        ) -%}
        {%- do paginated_state.paginated_results.append(adapter.normalize_show_objects_result(cortex_objects)) -%}
    {%- endfor -%}

    {%- set agate_table = paginated_state.paginated_results[0] -%}
    {%- do return(agate_table.merge(paginated_state.paginated_results)) -%}

{% endmacro %}
