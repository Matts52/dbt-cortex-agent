# `cortex_agent_eval` materialization

Full reference for Cortex Agent evaluations in dbt.

[Cortex Agent evaluations](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations)
score an agent against a golden question set with system and custom LLM-judge metrics.
Snowflake has no `CREATE EVALUATION` statement. An evaluation is an **evaluation dataset**, a
**YAML config file on a stage**, and the `EXECUTE_AI_EVALUATION` procedure.

The package follows the same deploy model as skills: `dbt build` deploys the dataset and the
config (in dependency order, after the agent they point at), and running an evaluation is a
separate, explicit step. Runs call LLM judges and are billed, and they are asynchronous, so
they are deliberately **not** part of `dbt build`.

| Piece | dbt construct | What it does |
|-------|---------------|--------------|
| Evaluation (dataset + config) | `cortex_agent_eval` model | Registers the dataset and writes the evaluation YAML to a stage file |
| Run / poll / cancel / delete | `run-operation` macros | Wrap `EXECUTE_AI_EVALUATION` |
| Results | `cortex_agent_eval_results()` macro | Returns a `SELECT` over `GET_AI_EVALUATION_DATA` |

---

## Where the questions live

The questions and ground truths live in **any table or view in your project**: a seed, a
source, or a model. The package never copies or rebuilds them; it registers the dataset over
whatever `table_name` points at. The usual shape is a seed CSV:

`seeds/support_agent_questions.csv`:

```csv
question,expected
What is our refund window?,"{""ground_truth_output"": ""30 days""}"
Which tool answers revenue questions?,"{""ground_truth_invocations"": [{""tool_name"": ""Analyst1"", ""tool_input"": ""revenue by quarter"", ""tool_output"": ""revenue table""}]}"
```

The ground truth is JSON with any of `ground_truth_output` (expected answer),
`ground_truth_invocations` (expected tool calls) and any keys read by custom metrics.
Snowflake needs the column to be a `VARIANT`. If yours is text (as it is for a seed), the
package casts it with `TRY_PARSE_JSON` through a view named `<dataset_name>_source`, and your
table is left untouched.

---

## Defining an evaluation

The model body **is** Snowflake's evaluation YAML. Jinja is rendered first, so `ref()`,
`source()`, `var()` and `this` all work. The `dataset:` block uses the same keys as Snowflake's
YAML; the package registers it and then removes it from the uploaded file, so it is safe to
run the evaluation repeatedly.

`support_agent_eval.sql` (any `.sql` file in your models path):

```sql
{{
  config(
    materialized = 'cortex_agent_eval',
    stage        = '@my_db.my_schema.eval_stage'
  )
}}
dataset:
  table_name: "{{ ref('support_agent_questions') }}"   # seed, source, or model
  dataset_name: "support_agent_golden"                 # qualified with this model's db.schema if bare
  column_mapping:
    query_text: question
    ground_truth: expected
evaluation:
  agent_params:
    agent_name: "{{ ref('support_agent') }}"
    agent_type: "CORTEX AGENT"
    agent_version: "{{ var('agent_version', 'LIVE') }}"
  run_params:
    label: "nightly"
    description: "Golden-set regression for the support agent"
  source_metadata:
    type: "dataset"
    dataset_name: "support_agent_golden"
metrics:
  - "logical_consistency"
  - name: "answer_correctness"
    version: "v3"
  - name: "tool_selection_accuracy"
    version: "v3"
  - name: "polite_tone"
    model: "claude-sonnet-4-6"
    score_ranges:
      min_score: [0, 3]
      median_score: [4, 6]
      max_score: [7, 10]
    prompt: |
      {% raw %}Rate how polite {{output}} is for the question {{input}}.{% endraw %}
```

At runtime the materialization:

1. registers the dataset with `SYSTEM$CREATE_EVALUATION_DATASET` (dropping any existing dataset
   with the same name first, since Snowflake refuses to re-create one, and because the dataset is
   a snapshot this also refreshes it after the table changes),
2. runs `CREATE STAGE IF NOT EXISTS`, then
3. writes the YAML, minus the `dataset:` block and with the qualified dataset name filled in, to
   `<stage>/evals/<model_alias>/config.yaml` with a single `COPY INTO` (no local file, so it also
   works under dbt Fusion).

Omit the `dataset:` block to point `source_metadata.dataset_name` at a dataset you manage
yourself. See the
[YAML specification](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations)
for every supported key.

> **Custom metric prompts need `{% raw %}`.** Placeholders like `{{output}}`, `{{input}}` and
> `{{ground_truth}}` are filled in by Snowflake, so wrap the prompt in `{% raw %} ... {% endraw %}`
> or dbt will try to render them.

---

## Running an evaluation

```bash
dbt seed --select support_agent_questions
dbt build --select support_agent_eval

# start a run and block until it finishes (non-zero exit unless COMPLETED)
dbt run-operation run_cortex_agent_eval \
  --args '{eval: support_agent_eval, run_name: nightly-1, wait: true}'
```

| Operation | Args | Description |
|-----------|------|-------------|
| `run_cortex_agent_eval` | `eval`, `run_name` (default `<eval>_<UTC timestamp>`), `wait` (default `false`), `timeout_seconds` (default `1800`), `poll_seconds` (default `15`) | Starts a run. With `wait: true` it polls until a terminal state and fails the operation unless the run is `COMPLETED`. |
| `cortex_agent_eval_status` | `eval`, `run_name` | Prints the run's status. |
| `cancel_cortex_agent_eval` | `eval`, `run_name` | Cancels an in-progress run. |
| `delete_cortex_agent_eval_run` | `eval`, `run_name` | Deletes a run and its results. |

`eval` is a `cortex_agent_eval` model name, or a full stage path to a config file
(`@db.schema.stage/path/config.yaml`). `run_name` may contain letters, digits, `_`, `.` and `-`,
and must be unique per agent.

Statuses: `CREATED` → `INVOCATION_IN_PROGRESS` → `INVOCATION_COMPLETED` →
`COMPUTATION_IN_PROGRESS` → `COMPLETED`. Terminal states: `COMPLETED`, `PARTIALLY_COMPLETED`,
`CANCELLED`, `FAILED`.

To evaluate a specific agent version in CI, template `agent_version` in the YAML and rebuild the
config with `dbt build --select support_agent_eval --vars '{agent_version: VERSION$3}'` before
running it.

---

## Reading results

```sql
select metric_name, avg(eval_agg_score) as avg_score
from ({{ dbt_cortex_agent.cortex_agent_eval_results(ref('support_agent'), 'nightly-1') }})
group by 1
```

This wraps `SNOWFLAKE.LOCAL.GET_AI_EVALUATION_DATA`. Land the output in an incremental model to
trend scores per run or agent version.

---

## Configuration reference

`cortex_agent_eval`:

| Config  | Required | Type   | Description |
|---------|----------|--------|-------------|
| `stage` | Yes      | string | Fully-qualified stage path, e.g. `@my_db.my_schema.eval_stage`. |

Configs can be set top-level or under `meta`. Standard dbt configs (`alias`, `tags`, `pre_hook`,
`post_hook`, ...) work as usual. The model `alias` becomes the folder name on the stage.

`dataset:` block keys (all from Snowflake's YAML):

| Key | Required | Description |
|-----|----------|-------------|
| `table_name` | Yes | Any table or view holding the questions, typically `{{ ref(...) }}` or `{{ source(...) }}`. |
| `dataset_name` | Yes | Dataset object name. A bare name is created in this model's database and schema. |
| `column_mapping.query_text` | Yes | Column holding the question. |
| `column_mapping.ground_truth` | Yes | Column holding the ground-truth JSON (`VARIANT`, or text that is cast for you). |

---

## Notes

- **Privileges.** Running evaluations needs `SNOWFLAKE.CORTEX_USER`, `USAGE` and `MONITOR` (or
  `OWNERSHIP`) on the agent, `CREATE DATASET` and `CREATE STAGE` on the schema, and
  **`EXECUTE TASK ON ACCOUNT`**. Without `EXECUTE TASK`, `START` succeeds but the run stays in
  `CREATED` indefinitely, so `wait: true` will time out. See the
  [access control requirements](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations).
- The evaluation YAML must not contain `$$` (used as the SQL dollar-quote delimiter internally).
- The uploaded YAML is re-serialized when a `dataset:` block is present, so comments and key
  order are not preserved in the staged copy (its meaning is unchanged).
- Evaluations run in the agent's database and schema, and are not supported for agents that use
  row access policies or MCP connectors.
- `timeout_seconds` is approximate: it is converted to a number of polls, and each poll also
  spends time on the status query.
- To remove a deployed config, run `REMOVE @<stage>/evals/<name>/config.yaml`. To drop a
  dataset, run `DROP DATASET <name>`.
