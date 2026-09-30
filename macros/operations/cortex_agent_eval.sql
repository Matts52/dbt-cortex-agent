{#-
--  Run-operations for executing Cortex Agent evaluations.
--
--  Evaluations are paid (LLM-judge inference) and asynchronous, so they are
--  deliberately operations rather than materializations: `dbt build` deploys the
--  dataset and config, and an explicit `dbt run-operation` starts a run.
--
--      dbt run-operation run_cortex_agent_eval \
--        --args '{eval: support_agent_eval, run_name: nightly-1, wait: true}'
--
--  `eval` is either the name of a cortex_agent_eval model or a full stage path
--  to a config file ('@db.schema.stage/path/config.yaml').
-#}

{% macro _cortex_eval_resolve_config_path(eval) -%}
  {%- if eval is string and eval.startswith('@') -%}
    {{- eval -}}
  {%- else -%}
    {{- dbt_cortex_agent.cortex_agent_eval_config_path(eval) -}}
  {%- endif -%}
{%- endmacro %}


{% macro _cortex_eval_check_run_name(run_name) -%}
  {%- if not modules.re.match('^[A-Za-z0-9_.-]+$', run_name | string) -%}
    {{ exceptions.raise_compiler_error("Invalid run_name '" ~ run_name
       ~ "': use only letters, digits, '_', '.' and '-'.") }}
  {%- endif -%}
{%- endmacro %}


{% macro _cortex_eval_call(job, run_name, config_path) -%}
  {#- Returns the agate table from EXECUTE_AI_EVALUATION. -#}
  {%- do dbt_cortex_agent._cortex_eval_check_run_name(run_name) -%}
  {{- return(run_query(
      "call execute_ai_evaluation('" ~ job ~ "', object_construct('run_name', '" ~ run_name
      ~ "'), '" ~ config_path ~ "')")) -}}
{%- endmacro %}


{% macro _cortex_eval_status_row(run_name, config_path) -%}
  {#- Returns {'status': ..., 'details': ..., 'agent': ...} for a run. -#}
  {%- set result = dbt_cortex_agent._cortex_eval_call('STATUS', run_name, config_path) -%}
  {%- if result.rows | length == 0 -%}
    {{ exceptions.raise_compiler_error("No status returned for run '" ~ run_name ~ "'.") }}
  {%- endif -%}
  {%- set row = result.rows[0] -%}
  {{- return({
      'status':  row[result.column_names.index('STATUS')],
      'details': row[result.column_names.index('STATUS_DETAILS')],
      'agent':   row[result.column_names.index('AGENT_NAME')]
  }) -}}
{%- endmacro %}


{% macro run_cortex_agent_eval(eval, run_name=none, wait=false, timeout_seconds=1800, poll_seconds=15) -%}
{#-
--  Run-operation: start a Cortex Agent evaluation run.
--
--    dbt run-operation run_cortex_agent_eval \
--      --args '{eval: support_agent_eval, run_name: nightly-1, wait: true}'
--
--  Args:
--  - eval:            cortex_agent_eval model name, or a stage path to a config
--  - run_name:        unique run name (default: <eval>_<UTC timestamp>). Reusing
--                     a name for the same agent fails in Snowflake.
--  - wait:            poll until the run reaches a terminal state, and fail
--                     (non-zero exit) unless it is COMPLETED. Use in CI.
--  - timeout_seconds: max time to wait when wait=true (default 1800)
--  - poll_seconds:    seconds between status checks (default 15)
--
--  Results are read afterwards with cortex_agent_eval_results().
-#}
  {%- if execute -%}
    {%- set config_path = dbt_cortex_agent._cortex_eval_resolve_config_path(eval) | trim -%}
    {%- if run_name is none -%}
      {%- set run_name = (eval | string).split('/')[-1] | replace('@', '') | replace('.', '_')
            ~ '_' ~ modules.datetime.datetime.utcnow().strftime('%Y%m%d_%H%M%S') -%}
    {%- endif -%}

    {%- set started = dbt_cortex_agent._cortex_eval_call('START', run_name, config_path) -%}
    {{ log('run_cortex_agent_eval: ' ~ started.rows[0][0] ~ ' (run_name=' ~ run_name ~ ', config=' ~ config_path ~ ')', info=true) }}

    {%- if wait -%}
      {%- set terminal = ['COMPLETED', 'PARTIALLY_COMPLETED', 'CANCELLED', 'FAILED'] -%}
      {%- set max_polls = ((timeout_seconds | int) / (poll_seconds | int)) | round(0, 'ceil') | int -%}
      {%- set ns = namespace(status='', details='', polls=0) -%}
      {%- for i in range(max_polls) -%}
        {%- if ns.status not in terminal -%}
          {%- set st = dbt_cortex_agent._cortex_eval_status_row(run_name, config_path) -%}
          {%- set ns.status = st.status -%}
          {%- set ns.details = st.details -%}
          {%- set ns.polls = i + 1 -%}
          {{ log('run_cortex_agent_eval: ' ~ run_name ~ ' status=' ~ ns.status, info=true) }}
          {%- if ns.status not in terminal -%}
            {%- do run_query('call system$wait(' ~ (poll_seconds | int) ~ ')') -%}
          {%- endif -%}
        {%- endif -%}
      {%- endfor -%}
      {%- if ns.status not in terminal -%}
        {{ exceptions.raise_compiler_error("run_cortex_agent_eval: run '" ~ run_name
           ~ "' did not finish within " ~ timeout_seconds ~ "s (last status: " ~ ns.status
           ~ "). It is still running; check it with cortex_agent_eval_status.") }}
      {%- elif ns.status != 'COMPLETED' -%}
        {{ exceptions.raise_compiler_error("run_cortex_agent_eval: run '" ~ run_name
           ~ "' finished with status " ~ ns.status ~ ". Details: " ~ ns.details) }}
      {%- endif -%}
      {{ log('run_cortex_agent_eval: run ' ~ run_name ~ ' COMPLETED', info=true) }}
    {%- endif -%}
  {%- endif -%}
{%- endmacro %}


{% macro cortex_agent_eval_status(eval, run_name) -%}
{#-
--  Run-operation: print the status of an evaluation run.
--
--    dbt run-operation cortex_agent_eval_status \
--      --args '{eval: support_agent_eval, run_name: nightly-1}'
--
--  Status is one of CREATED, INVOCATION_IN_PROGRESS, INVOCATION_COMPLETED,
--  INVOCATION_PARTIALLY_COMPLETED, COMPUTATION_IN_PROGRESS, COMPLETED,
--  PARTIALLY_COMPLETED, CANCELLED, or FAILED (not in Snowflake's documented
--  list, but returned when the agent invocation fails).
-#}
  {%- if execute -%}
    {%- set config_path = dbt_cortex_agent._cortex_eval_resolve_config_path(eval) | trim -%}
    {%- set st = dbt_cortex_agent._cortex_eval_status_row(run_name, config_path) -%}
    {{ log('cortex_agent_eval_status: ' ~ run_name ~ ' agent=' ~ st.agent ~ ' status=' ~ st.status
           ~ ' details=' ~ st.details, info=true) }}
  {%- endif -%}
{%- endmacro %}


{% macro cancel_cortex_agent_eval(eval, run_name) -%}
{#-
--  Run-operation: cancel an in-progress evaluation run.
--
--    dbt run-operation cancel_cortex_agent_eval \
--      --args '{eval: support_agent_eval, run_name: nightly-1}'
-#}
  {%- if execute -%}
    {%- set config_path = dbt_cortex_agent._cortex_eval_resolve_config_path(eval) | trim -%}
    {%- set res = dbt_cortex_agent._cortex_eval_call('CANCEL', run_name, config_path) -%}
    {{ log('cancel_cortex_agent_eval: ' ~ res.rows[0][0], info=true) }}
  {%- endif -%}
{%- endmacro %}


{% macro delete_cortex_agent_eval_run(eval, run_name) -%}
{#-
--  Run-operation: delete an evaluation run and its results.
--
--    dbt run-operation delete_cortex_agent_eval_run \
--      --args '{eval: support_agent_eval, run_name: nightly-1}'
-#}
  {%- if execute -%}
    {%- set config_path = dbt_cortex_agent._cortex_eval_resolve_config_path(eval) | trim -%}
    {%- set res = dbt_cortex_agent._cortex_eval_call('DELETE', run_name, config_path) -%}
    {{ log('delete_cortex_agent_eval_run: ' ~ res.rows[0][0], info=true) }}
  {%- endif -%}
{%- endmacro %}


{% macro cortex_agent_eval_results(agent, run_name) -%}
{#-
--  Returns a SELECT over the per-record results of an evaluation run
--  (SNOWFLAKE.LOCAL.GET_AI_EVALUATION_DATA), for use in a model to land or trend
--  results, or in an ad hoc query.
--
--    select * from ({{ dbt_cortex_agent.cortex_agent_eval_results(ref('support_agent'), 'nightly-1') }})
--
--  Args:
--  - agent:    Relation returned by ref() for the evaluated cortex_agent model
--  - run_name: the run to read
-#}
  {%- do dbt_cortex_agent._cortex_eval_check_run_name(run_name) -%}
  select *
  from table(snowflake.local.get_ai_evaluation_data(
    '{{ agent.database }}', '{{ agent.schema }}', '{{ agent.identifier }}', 'CORTEX AGENT', '{{ run_name }}'))
{%- endmacro %}
