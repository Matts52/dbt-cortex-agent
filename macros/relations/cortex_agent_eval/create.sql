{% macro _cortex_eval_cfg(key, default=none) -%}
{#-
--  Reads a config key for the eval materializations, preferring
--  config(meta={...}) and falling back to a top-level config() key, the same
--  precedence the other materializations use.
-#}
  {%- set _m = config.get('meta', {}).get(key) -%}
  {{- return(_m if _m is not none else config.get(key, default=default)) -}}
{%- endmacro %}


{% macro _cortex_eval_unwrap_empty_ref(value) -%}
{#-
--  dbt renders ref() and source() as a subquery under `--empty`:
--    (select * from <db>.<schema>.<table> where false limit 0)
--  Strip that wrapper so identifier-position values stay plain relation names.
-#}
  {%- set s = value | string | trim -%}
  {%- set match = modules.re.match(
      r'^\(select \* from (.+?)(?: where false)? limit 0\)$', s,
      modules.re.IGNORECASE
  ) -%}
  {{- return(match.group(1) if match else s) -}}
{%- endmacro %}


{% macro cortex_agent_eval__config_path(stage, identifier) -%}
{#-
--  Stage path of the config file deployed for a cortex_agent_eval model.
-#}
  {{- stage ~ '/evals/' ~ identifier ~ '/config.yaml' -}}
{%- endmacro %}


{% macro snowflake__create_or_replace_cortex_agent_eval() %}
{#-
--  Deploys an evaluation config for a model that uses the `cortex_agent_eval`
--  materialization. Runs pre/post hooks around the main statement, exactly like
--  dbt's built-in materializations.
--
--  If the YAML has a `dataset:` block, the dataset is registered here (see
--  _cortex_eval_register_dataset) and the block is removed from the uploaded
--  file, so repeated EXECUTE_AI_EVALUATION runs never try to re-create it.
--
--  Returns: {'relations': [target_relation]}
-#}
  {%- set identifier       = model['alias'] -%}
  {%- set stage            = dbt_cortex_agent._cortex_eval_cfg('stage') -%}
  {%- if not stage -%}
    {{ exceptions.raise_compiler_error(
        "cortex_agent_eval: config 'stage' is required, e.g. meta={'stage': '@my_db.my_schema.eval_stage'}"
    ) }}
  {%- endif -%}
  {%- set config_path      = dbt_cortex_agent.cortex_agent_eval__config_path(stage, identifier) -%}
  {%- set stage_identifier = stage[1:] -%}

  {%- set target_relation = api.Relation.create(
      identifier=identifier, schema=schema, database=database,
      type='view') -%}

  {%- set parsed = fromyaml(sql) -%}
  {%- if parsed is not mapping or 'evaluation' not in parsed or 'metrics' not in parsed -%}
    {{ exceptions.raise_compiler_error(
        "cortex_agent_eval: the model body must be an evaluation YAML with top-level 'evaluation' and 'metrics' keys."
    ) }}
  {%- endif -%}

  {#- unwrap --empty ref() subquery rendering in name fields -#}
  {%- set _eval = parsed['evaluation'] -%}
  {%- set _ap = _eval.get('agent_params', {}) -%}
  {%- if 'agent_name' in _ap -%}
    {%- do _ap.update({'agent_name': dbt_cortex_agent._cortex_eval_unwrap_empty_ref(_ap['agent_name'])}) -%}
  {%- endif -%}
  {%- set _sm = _eval.get('source_metadata', {}) -%}
  {%- if 'dataset_name' in _sm -%}
    {%- do _sm.update({'dataset_name': dbt_cortex_agent._cortex_eval_unwrap_empty_ref(_sm['dataset_name'])}) -%}
  {%- endif -%}

  {{ run_hooks(pre_hooks) }}

  {%- set config_sql = sql -%}
  {%- if 'dataset' in parsed -%}
    {%- set dataset_name = dbt_cortex_agent._cortex_eval_register_dataset(parsed['dataset'], target_relation) -%}
    {%- do parsed.pop('dataset') -%}
    {#- point the eval at the qualified dataset that was actually registered -#}
    {%- set source_metadata = parsed['evaluation'].get('source_metadata') -%}
    {%- if source_metadata is mapping -%}
      {%- do source_metadata.update({'dataset_name': dataset_name}) -%}
    {%- else -%}
      {%- do parsed['evaluation'].update({'source_metadata': {'type': 'dataset', 'dataset_name': dataset_name}}) -%}
    {%- endif -%}
    {%- set config_sql = toyaml(parsed) -%}
  {%- endif -%}

  -- ensure stage exists
  {%- do run_query("create stage if not exists " ~ stage_identifier) -%}

  -- write the evaluation YAML
  {% call statement('main') -%}
    {{ dbt_cortex_agent.snowflake__get_create_cortex_agent_eval_sql(target_relation, config_sql, config_path) }}
  {%- endcall %}

  -- validate that the file landed on the stage
  {%- set list_result = run_query("list " ~ config_path) -%}
  {%- if list_result.rows | length == 0 -%}
    {{ exceptions.raise_compiler_error(
        "cortex_agent_eval: config file not found at '" ~ config_path ~ "' after upload."
    ) }}
  {%- endif -%}

  {{ run_hooks(post_hooks) }}

  {{ return({'relations': [target_relation]}) }}

{% endmacro %}


{% macro _cortex_eval_register_dataset(dataset, model_relation) -%}
{#-
--  Registers the `dataset:` block of an evaluation YAML as an evaluation DATASET
--  object with SYSTEM$CREATE_EVALUATION_DATASET, and returns the qualified
--  dataset name.
--
--  The block uses the same keys as Snowflake's evaluation YAML:
--
--      dataset:
--        table_name: "{{ ref('my_golden_questions') }}"   # any table or view
--        dataset_name: "my_agent_golden"                  # qualified with the
--                                                         # model's db.schema if bare
--        column_mapping:
--          query_text: question
--          ground_truth: expected
--
--  `table_name` can be anything in the project: a seed, source, or model. Nothing
--  is copied or rebuilt; the dataset is registered over that table.
--
--  * Snowflake refuses to create a dataset that already exists, so any existing
--    one is dropped first. The dataset is a snapshot, so this is also what
--    refreshes it after the table changes.
--  * The ground truth must be a VARIANT. If the column is text (for example JSON
--    loaded from a seed), it is cast with TRY_PARSE_JSON through a view named
--    `<dataset_name>_source`, so the source table is never modified.
-#}
  {%- for key in ['table_name', 'dataset_name', 'column_mapping'] -%}
    {%- if key not in dataset -%}
      {{ exceptions.raise_compiler_error("cortex_agent_eval: dataset block is missing required key '" ~ key ~ "'.") }}
    {%- endif -%}
  {%- endfor -%}
  {%- set mapping = dataset['column_mapping'] -%}
  {%- for key in ['query_text', 'ground_truth'] -%}
    {%- if key not in mapping -%}
      {{ exceptions.raise_compiler_error("cortex_agent_eval: dataset.column_mapping is missing '" ~ key ~ "'.") }}
    {%- endif -%}
  {%- endfor -%}

  {%- set raw_name = dbt_cortex_agent._cortex_eval_unwrap_empty_ref(dataset['dataset_name'] | string) -%}
  {%- set dataset_name = raw_name if '.' in raw_name
        else model_relation.database ~ '.' ~ model_relation.schema ~ '.' ~ raw_name -%}
  {%- set table_name = dbt_cortex_agent._cortex_eval_unwrap_empty_ref(dataset['table_name'] | string) -%}
  {%- set query_col = mapping['query_text'] | string -%}
  {%- set truth_col = mapping['ground_truth'] | string -%}

  {%- set columns = run_query('describe table ' ~ table_name) -%}
  {%- set ns = namespace(truth_type='') -%}
  {%- for row in columns.rows -%}
    {%- if row[0] | upper == truth_col | upper -%}
      {%- set ns.truth_type = row[1] | upper -%}
    {%- endif -%}
  {%- endfor -%}
  {%- if ns.truth_type == '' -%}
    {{ exceptions.raise_compiler_error("cortex_agent_eval: ground_truth column '" ~ truth_col
       ~ "' not found in " ~ table_name ~ ".") }}
  {%- endif -%}

  {%- set source = table_name -%}
  {%- if not (ns.truth_type.startswith('VARIANT') or ns.truth_type.startswith('OBJECT')) -%}
    {%- set source = dataset_name ~ '_source' -%}
    {%- do run_query('create or replace view ' ~ source ~ ' as select ' ~ query_col ~ ' as query_text, try_parse_json('
          ~ truth_col ~ ') as ground_truth from ' ~ table_name) -%}
    {%- set query_col = 'query_text' -%}
    {%- set truth_col = 'ground_truth' -%}
  {%- endif -%}

  {%- do run_query('drop dataset if exists ' ~ dataset_name) -%}
  {#- the SQL interface calls the ground truth column mapping `expected_tools`; the YAML calls it `ground_truth` -#}
  {%- do run_query("call system$create_evaluation_dataset('Cortex Agent', '" ~ source ~ "', '" ~ dataset_name
        ~ "', object_construct('query_text', '" ~ query_col ~ "', 'expected_tools', '" ~ truth_col ~ "'))") -%}
  {{- return(dataset_name) -}}
{%- endmacro %}


{% macro snowflake__get_create_cortex_agent_eval_sql(relation, sql, config_path) -%}
{#-
--  Produce the COPY INTO statement that writes the evaluation YAML to a stage
--  file.
--
--  Args:
--  - relation:    SnowflakeRelation or str (for context)
--  - sql:         str - compiled model body (the evaluation YAML)
--  - config_path: str - full stage path of the file,
--                       e.g. '@my_db.my_schema.eval_stage/evals/support_eval/config.yaml'
--
--  Unlike cortex_skill, no local file is needed: the rendered YAML is unloaded
--  straight from a literal, so Jinja in the body (ref(), var(), ...) is
--  resolved and the same statement works under dbt Core and dbt Fusion. The
--  file format writes the string verbatim (no delimiters, quoting, escaping or
--  compression), which EXECUTE_AI_EVALUATION can read back as YAML.
--
--  The YAML is embedded in a $$-quoted literal, so it must not contain '$$'.
--
--  Returns: a valid Snowflake COPY INTO statement.
-#}
  {%- if '$$' in sql -%}
    {{ exceptions.raise_compiler_error(
        "cortex_agent_eval: the evaluation YAML must not contain '$$' (it is embedded in a $$-quoted string)."
    ) }}
  {%- endif -%}

  copy into {{ config_path }}
  from (select $${{ sql | trim }}
$$)
  file_format = (
    type                     = 'CSV'
    compression              = 'NONE'
    field_delimiter          = none
    record_delimiter         = none
    field_optionally_enclosed_by = none
    escape_unenclosed_field  = none
  )
  single    = true
  overwrite = true
  header    = false

{%- endmacro %}


{% macro cortex_agent_eval_config_path(eval_ref) -%}
{#-
--  Returns the stage path of the config file for a cortex_agent_eval model
--  given its ref() or its model name, so it can be passed to
--  EXECUTE_AI_EVALUATION.
--
--  Calling ref() as the argument registers the DAG dependency, and the macro
--  derives the path from the eval model's `stage` config.
--
--  Args:
--  - eval_ref: Relation returned by ref(), or a model name string
--
--  Returns: e.g. '@my_db.my_schema.eval_stage/evals/support_eval/config.yaml'
-#}
  {%- set model_name = eval_ref.identifier if eval_ref is not string else eval_ref -%}
  {%- if execute -%}
    {%- set ns = namespace(stage='') -%}
    {%- for node in graph.nodes.values() -%}
      {%- if node.resource_type == 'model' and node.name == model_name
             and node.config.materialized == 'cortex_agent_eval' -%}
        {%- set ns.stage = node.config.get('meta', {}).get('stage') or node.config.get('stage', '') -%}
      {%- endif -%}
    {%- endfor -%}
    {%- if ns.stage == '' -%}
      {{ exceptions.raise_compiler_error(
          "cortex_agent_eval_config_path: no cortex_agent_eval model named '" ~ model_name
          ~ "' with a stage config was found."
      ) }}
    {%- endif -%}
    {{- dbt_cortex_agent.cortex_agent_eval__config_path(ns.stage, model_name) -}}
  {%- else -%}
    {{- '@__eval_stage_placeholder__/evals/' ~ model_name ~ '/config.yaml' -}}
  {%- endif -%}
{%- endmacro %}
