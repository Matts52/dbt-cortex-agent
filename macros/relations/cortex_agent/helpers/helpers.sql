{% macro _cortex_agent_exists(relation) -%}
{#-
--  Returns true if the named Cortex Agent already exists in Snowflake.
--  Uses SHOW AGENTS + RESULT_SCAN since agents are not in INFORMATION_SCHEMA.
--  Returns false at parse time (execute=False guard).
-#}
  {%- if not execute -%}{{ return(false) }}{%- endif -%}
  {%- do run_query("show agents like '" ~ relation.identifier ~ "' in schema " ~ relation.database ~ "." ~ relation.schema) -%}
  {%- set results = run_query("select count(*) as n from table(result_scan(last_query_id()))") -%}
  {{ return((results.columns[0].values()[0] | int) > 0) }}
{%- endmacro %}


{% macro _cortex_agent_versions(relation) -%}
{#-
--  Summarise an agent's versions via SHOW VERSIONS IN AGENT + RESULT_SCAN.
--  Specs are compared by md5 so the (unbounded, never-pruned) version
--  history does not ship full spec text back on every run.
--
--  Returns a dict:
--  - has_live:     true if an uncommitted live version is open
--  - live_hash:    md5 of the live version's spec (none if no live version)
--  - last_name:    newest committed version name, e.g. VERSION$3
--  - last_hash:    md5 of that version's spec
--  - default_name: the version currently serving as default
--  - aliases:      {ALIAS: VERSION$n} for every aliased version
--  All values are empty at parse time (execute=False guard).
-#}
  {%- set out = {'has_live': false, 'live_hash': none, 'last_name': none,
                 'last_hash': none, 'default_name': none, 'aliases': {}} -%}
  {%- if not execute -%}{{ return(out) }}{%- endif -%}
  {%- do run_query('show versions in agent ' ~ relation) -%}
  {%- set rows = run_query(
      'select "name", "is_default", "alias", md5("agent_spec") '
      ~ 'from table(result_scan(last_query_id())) '
      ~ 'order by try_to_number(split_part("name", ' ~ "'$'" ~ ', 2)) desc nulls first'
  ).rows -%}
  {%- for row in rows -%}
    {%- if row[0] is none -%}
      {%- do out.update({'has_live': true, 'live_hash': row[3]}) -%}
    {%- else -%}
      {%- if out.last_name is none -%}
        {%- do out.update({'last_name': row[0], 'last_hash': row[3]}) -%}
      {%- endif -%}
      {%- if (row[1] | string | lower) == 'true' -%}
        {%- do out.update({'default_name': row[0]}) -%}
      {%- endif -%}
      {%- if row[2] is not none -%}
        {%- do out.aliases.update({(row[2] | upper): row[0]}) -%}
      {%- endif -%}
    {%- endif -%}
  {%- endfor -%}
  {{ return(out) }}
{%- endmacro %}


{% macro _cortex_agent_auto_version_name() -%}
{#-
--  Generates a deterministic version alias from run_started_at: v_YYYYMMDD_HHMMSS.
--  All models versioned in the same dbt run share one alias.
--  Returns a placeholder string at parse time.
-#}
  {%- if execute -%}
    {{- 'v_' ~ run_started_at.strftime('%Y%m%d_%H%M%S') -}}
  {%- else -%}
    {{- 'v_YYYYMMDD_HHMMSS' -}}
  {%- endif -%}
{%- endmacro %}
