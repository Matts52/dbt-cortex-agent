# dbt_cortex_agent

A dbt package that adds **`cortex_agent`** and **`cortex_skill`** materializations
for creating and managing [Snowflake Cortex Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents)
and [Agent Skills](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-skills)
directly from dbt — the same way the
[`dbt_semantic_view`](https://github.com/Snowflake-Labs/dbt_semantic_view) package
manages Semantic Views.

Define agents and skills as dbt models, wire tools to other dbt models (semantic
views, Cortex Search services) with `ref()` / `source()`, and let
`dbt build` deploy everything in dependency order — fully integrated into your
DAG, lineage, and orchestration.

Currently, as Cortex Agents are only available on the Snowflake adapter, this package is only available to be used on the Snowflake adapter.

---

## At a glance

- **Materializations:** `cortex_agent`, `cortex_skill`, `cortex_agent_eval`, `cortex_mcp_server`, `cortex_mcp_api_integration`
- **Warehouse:** Snowflake (Cortex Agents)
- **dbt compatibility:** dbt 1.5+
- **Underlying DDL:** [`CREATE AGENT`](https://docs.snowflake.com/en/sql-reference/sql/create-agent) / `PUT 'file://...' @stage`

> **Full SQL API coverage.** The default mode wraps your model body in
> `FROM SPECIFICATION $$ ... $$`, so the entire agent specification grammar is
> available with no package change. For total control of every clause, switch
> on `raw_ddl` and the package becomes a pure pass-through to Snowflake SQL.

---

## Installation

### From dbt Hub (recommended)

Add the package to your project's `packages.yml`:

```yaml
packages:
  - package: Matts52/dbt_cortex_agent
    version: 1.0.0
```

Then install:

```bash
dbt deps
```

### From GitHub

Alternatively, install directly from GitHub:

```yaml
packages:
  - git: "https://github.com/Matts52/dbt-cortex-agent.git"
    revision: 1.0.0
```

```bash
dbt deps
```

---

## Usage

### 1. Specification mode (default)

The body of the model **is the agent specification YAML**. The package wraps
it in `FROM SPECIFICATION $$ ... $$` and emits the optional `COMMENT` and
`PROFILE` clauses from config.

`models/sales_agent.sql`:

```sql
{{
  config(
    materialized = 'cortex_agent',
    comment      = 'Sales analytics assistant',
    profile      = {
      'display_name': 'Sales Assistant',
      'avatar': 'sales-icon.png',
      'color': 'blue'
    }
  )
}}
models:
  orchestration: claude-4-sonnet
orchestration:
  budget:
    seconds: 30
    tokens: 16000
instructions:
  response: "Respond in a friendly but concise manner."
  orchestration: "Use Analyst for revenue questions; use Search for policy questions."
  sample_questions:
    - question: "What was our revenue last quarter?"
tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "Analyst1"
      description: "Converts natural language to SQL for financial analysis."
  - tool_spec:
      type: "cortex_search"
      name: "Search1"
      description: "Searches company policy and documentation."
tool_resources:
  Analyst1:
    semantic_view: "{{ ref('sales_semantic_view') }}"
    execution_environment:
      type: "warehouse"
      warehouse: "MY_WAREHOUSE"
  Search1:
    name: "{{ source('cortex', 'policy_search_service') }}"
    max_results: 5
    filter:
      "@eq":
        region: "North America"
    title_column: "title"
    id_column: "doc_id"
```

This compiles to roughly:

```sql
create or replace agent MY_DB.MY_SCHEMA.SALES_AGENT
comment = 'Sales analytics assistant'
profile = '{"display_name": "Sales Assistant", "avatar": "sales-icon.png", "color": "blue"}'
from specification
$$
models:
  orchestration: claude-4-sonnet
...
$$
```

> **Tip — wiring tools to your DAG.** Because the body is rendered through
> Jinja, you can use `{{ ref(...) }}` and `{{ source(...) }}` inside
> `tool_resources` to point a tool at a semantic view or Cortex Search service
> managed elsewhere in your project. This makes the agent a proper downstream
> node in your lineage graph.

### Enabling analytical search (Preview)

[Analytical search](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-analytical-search)
is a capability flag that tells the Cortex Agent orchestrator to run an extended analytics loop
over Cortex Search results: after narrowing the candidate set with Cortex Search, the agent
applies `AI_FILTER`, `AI_EXTRACT`, and `AI_AGG` SQL functions to support filtered lists,
aggregates, and temporal analysis queries. It is off by default and **billed through AI
functions** in addition to standard Cortex Search costs.

> **Preview.** Analytical search is available in Snowflake Public Preview. Feature availability
> and syntax may change before GA.

Add `analytical_search = true` to enable it. The package merges
`orchestration.capabilities.analytical_search: true` into the spec via YAML parse-and-merge,
so it composes correctly with any `orchestration:` block already in the body and with the
`budget` config shorthand — no duplicate YAML keys.

```sql
{{
  config(
    materialized      = 'cortex_agent',
    analytical_search = true,
    budget            = {'seconds': 30, 'tokens': 16000}
  )
}}
instructions:
  response: "Analyze search results thoroughly."
tools:
  - tool_spec:
      type: "cortex_search"
      name: "PolicySearch"
      description: "Searches policy documents."
tool_resources:
  PolicySearch:
    name: "{{ source('cortex', 'policy_search_service') }}"
    max_results: 1000
```

This compiles `analytical_search` and `budget` into a single `orchestration:` block:

```yaml
orchestration:
  budget:
    seconds: 30
    tokens: 16000
  capabilities:
    analytical_search: true
```

> **Tip — `max_results`.** Snowflake's analytical search documentation recommends setting
> `max_results: 1000` on the search tool to give the analytics loop a large enough candidate
> set to aggregate over. The default (`5`) is appropriate for retrieval but too small for
> aggregation queries.

A compile-time warning is emitted if `analytical_search = true` is set but the spec has no
`cortex_search` tool, since the flag has no effect without one. The config is ignored (with a
warning) under `raw_ddl = true`.

### Enabling web search

Add `web_search_tool = true` to the config block to give the agent access to
Snowflake's built-in web search capability:

```sql
{{
  config(
    materialized    = 'cortex_agent',
    web_search_tool = true
  )
}}
models:
  orchestration: claude-4-sonnet
instructions:
  response: "Be concise."
  orchestration: "Use web search to answer questions about current events."
```

This injects a `tool_spec` entry into the agent specification YAML:

```sql
create or replace agent MY_DB.MY_SCHEMA.MY_AGENT
from specification
$$
...
tools:
  - tool_spec:
      type: "web_search"
      name: "web_search"
$$
```

Omitting the config key (or setting it to `false`) produces no `tools` entry.

> **Note:** If your spec already contains a `tools:` block (e.g. for `cortex_search` or `cortex_analyst_text_to_sql`), set `web_search_tool = false` and add the entry directly in your spec's `tools:` list to avoid a duplicate key.

### Enabling code execution

> **Preview:** The code execution tool is in Public Preview as of August 20, 2026. Check the [Snowflake release notes](https://docs.snowflake.com/en/release-notes/2026/ui/2026-08-20) for any changes before using in production.

Add `code_execution_tool = true` to give the agent a Python sandbox that can run calculations, process data with numpy/pandas/scipy, and generate matplotlib/plotly charts:

```sql
{{
  config(
    materialized        = 'cortex_agent',
    code_execution_tool = true
  )
}}
models:
  orchestration: claude-4-sonnet
instructions:
  response: "Be concise."
  orchestration: "Use the code execution tool to perform calculations and data analysis."
```

This injects a `tool_spec` entry and an empty `tool_resources.code_execution` block into the spec:

```yaml
tools:
  - tool_spec:
      type: "code_execution"
      name: "code_execution"
tool_resources:
  code_execution: {}
```

**Map form** — pass a dict to configure `permission_policy` or allow PyPI packages via `artifact_repositories`:

```sql
{{
  config(
    materialized        = 'cortex_agent',
    code_execution_tool = {
      'permission_policy':      'always_allow',
      'artifact_repositories':  ['SNOWFLAKE.SNOWPARK.PYPI_SHARED_REPOSITORY']
    }
  )
}}
```

- `permission_policy`: `'always_ask'` (default — prompts before state-modifying operations) or `'always_allow'`.
- `artifact_repositories`: list of repository identifiers. To use `SNOWFLAKE.SNOWPARK.PYPI_SHARED_REPOSITORY`, the agent owner needs the `SNOWFLAKE.PYPI_REPOSITORY_USER` role.

**Composing with other tools** — unlike `web_search_tool`, the `code_execution_tool` shorthand uses YAML parse-and-merge, so it is safe to use alongside an existing `tools:` block in the spec body. The two tool entries are merged into a single `tools:` list with no duplicate keys:

```sql
{{
  config(
    materialized        = 'cortex_agent',
    code_execution_tool = true
  )
}}
tools:
  - tool_spec:
      type: "cortex_search"
      name: "PolicySearch"
      description: "Searches policy documents."
tool_resources:
  PolicySearch:
    name: "my_db.my_schema.my_search_service"
    max_results: 5
```

**Required privileges:** `MODIFY` on the agent to configure the tool; `USAGE` to invoke it at runtime.

**Limitation:** `code_execution` and `code_toolset_all` are mutually exclusive. Setting `code_execution_tool = true` while the spec body declares a `code_toolset_all` tool raises a compile-time error.

> **Note:** `code_execution_tool` is ignored with a warning when `raw_ddl=true`. Add the tool entries directly in the spec's `tools:` and `tool_resources:` blocks instead.

### 2. Raw DDL mode (`raw_ddl=true`)

The body is **everything that follows `CREATE OR REPLACE AGENT <name>`** — a
direct pass-through to Snowflake. Use this when you want to control the exact
clause ordering or adopt new `CREATE AGENT` syntax before the package models
it.

> **Note:** The `comment`, `profile`, and `web_search_tool` configs are silently
> ignored in raw DDL mode — a compile-time warning is emitted if any of them are
> set alongside `raw_ddl=true`. Add web search support directly in the spec's
> `tools:` list:
> ```yaml
> tools:
>   - tool_spec:
>       type: "web_search"
>       name: "web_search"
> ```

`models/raw_agent.sql`:

```sql
{{ config(materialized='cortex_agent', raw_ddl=true) }}
comment = 'Fully hand-written DDL'
profile = '{"display_name": "Raw Agent"}'
from specification
$$
models:
  orchestration: claude-4-sonnet
instructions:
  response: "Be concise."
$$
```

### 3. Versioned publish / canary rollout (`versioning=true`)

By default, every `dbt run` issues `CREATE OR REPLACE AGENT` — the new spec is live the instant the run finishes, with no version history and no rollback path.

Set `versioning=true` to use Snowflake's [agent versioning](https://docs.snowflake.com/en/sql-reference/sql/alter-agent) instead. Snowflake names committed versions itself (`VERSION$1`, `VERSION$2`, …); the package tracks whether the agent already exists and issues the appropriate DDL:

- **First run (agent absent):** `CREATE AGENT ... FROM SPECIFICATION $$...$$` — Snowflake commits it as `VERSION$1`, which the package always pins as the default (Snowflake's initial default is the floating `LAST`).
- **Subsequent runs (agent present):**
  1. `ALTER AGENT ... ADD LIVE VERSION FROM LAST` (only if no live version is open)
  2. `ALTER AGENT ... MODIFY LIVE VERSION SET SPECIFICATION = $$...$$`
  3. `ALTER AGENT ... SET COMMENT = ..., PROFILE = ...` (when configured)
  4. `ALTER AGENT ... COMMIT` — **skipped when the spec is unchanged**, so re-running an unchanged model does not pile up identical versions.
- **Promotion (when `set_default=true`, the default):** `ALTER AGENT ... SET DEFAULT_VERSION = 'VERSION$<n>'`.
- **Tagging:** the new version gets `version_name` as its alias: `ALTER AGENT ... MODIFY VERSION VERSION$<n> SET ALIAS = <version_name>`.

The agent is never dropped or replaced on this path, so its version history and grants survive every run. `ALTER AGENT` needs `OWNERSHIP` or `MODIFY` on the agent.

#### Minimal example

```sql
{{
  config(
    materialized = 'cortex_agent',
    versioning   = true
  )
}}
models:
  orchestration: claude-4-sonnet
instructions:
  response: "Be concise."
```

When `version_name` is omitted, each run tags its new version with an alias generated from `run_started_at` in the format `v_YYYYMMDD_HHMMSS`. All models versioned in the same `dbt run` share one alias, so rolling back a full run means pointing each agent's default back at the previous timestamp alias.

`version_name` must be a valid unquoted Snowflake identifier (`^[A-Za-z_][A-Za-z0-9_$]*$` — so not `v1.2`, `v-1` or `2024_01`); an invalid name fails the run at compile time, before any DDL. Snowflake stores aliases uppercased. Aliases are unique per agent: reusing one moves it to the new version, which makes a floating tag such as `canary` work naturally.

#### Staging a canary version

Deploy a new spec without affecting live traffic by setting `set_default=false`:

```sql
{{
  config(
    materialized = 'cortex_agent',
    versioning   = true,
    version_name = 'canary',
    set_default  = false          -- commit a new version but keep the current default live
  )
}}
```

With `set_default=false` the package pins the current default before committing, so the commit cannot move it.

After validating the canary out of band, promote it either by flipping `set_default` back to `true` and re-running (the spec is unchanged, so no new version is committed — the newest version is just promoted), or directly:

```bash
dbt run-operation set_cortex_agent_default_version --args '{agent: my_db.my_schema.my_agent, version: canary}'
```

#### Rollback

Point the default at any earlier version, by alias or by Snowflake version name:

```bash
dbt run-operation set_cortex_agent_default_version --args '{agent: my_db.my_schema.my_agent, version: v_20250101_120000}'
dbt run-operation set_cortex_agent_default_version --args '{agent: my_db.my_schema.my_agent, version: VERSION$3}'
```

A later `dbt run` with `set_default=true` promotes the newest version again, so make the rollback permanent by reverting the spec in git (which commits it as a new version).

> **Warning:** switching a model from `versioning=true` back to `false` makes the next run issue `CREATE OR REPLACE AGENT`, which wipes the agent's entire version history and all aliases.

> **Note:** `versioning=true` is incompatible with `raw_ddl=true`. If both are set, a compile-time warning is emitted and the materialization falls back to `CREATE OR REPLACE` behavior. Use specification mode (`raw_ddl=false`) to enable versioning.

---

## Skills (`cortex_skill` materialization)

[Agent skills](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-skills)
are modular packages of instructions (and optional scripts) that give agents repeatable,
task-specific capabilities. Snowflake stores them as files on a named stage — there is no
`CREATE SKILL` SQL statement.

The `cortex_skill` materialization uploads a skill's `SKILL.md` file to a Snowflake stage
automatically during `dbt build`, before any agent that depends on it is created.

### Defining a skill

Skill files live in a directory alongside the `.sql` model — same name as the model, no
extension. The directory must contain at least `SKILL.md` and may include any companion
scripts (e.g. `.py` files for the code execution tool). The `.sql` model is config only:

```
models/
  skills/
    forecaster_skill.sql       ← dbt model (config only)
    forecaster_skill/          ← skill directory (all files uploaded to stage)
      SKILL.md                 ← required
      forecaster.py            ← optional companion scripts
```

`models/skills/forecaster_skill.sql`:

```sql
{{
  config(
    materialized = 'cortex_skill',
    stage        = '@my_db.my_schema.skill_stage'
  )
}}
```

At runtime the materialization runs:

```sql
CREATE STAGE IF NOT EXISTS my_db.my_schema.skill_stage;

PUT 'file:///absolute/path/to/forecaster_skill/*'
    @my_db.my_schema.skill_stage/skills/forecaster_skill/
AUTO_COMPRESS = FALSE
OVERWRITE = TRUE;
```

Every file in the directory is uploaded in a single `PUT`. Filenames on the stage exactly
match the local filenames — no suffix is appended.

### Wiring a skill to an agent

Use the `cortex_skill_path()` macro with `ref()` to wire a skill to an agent. This both
registers the DAG dependency (so the skill file is deployed before the agent is created) and
derives the correct stage path from the skill model's `stage` config automatically — no
hard-coded paths or variables needed:

`models/my_agent.sql`:

```sql
{{
  config(materialized = 'cortex_agent')
}}
models:
  orchestration: claude-4-sonnet
instructions:
  response: "Be concise."
  orchestration: "Use the forecaster skill to answer forecasting questions."
skills:
  - name: forecaster
    source:
      type: STAGE
      path: "{{ dbt_cortex_agent.cortex_skill_path(ref('forecaster_skill')) }}"
```

`dbt build` will deploy `forecaster_skill` first (writing `SKILL.md` to the stage), then create
or replace the agent with the resolved path in the spec.

### `cortex_skill` configuration reference

| Config  | Required | Type   | Description |
|---------|----------|--------|-------------|
| `stage` | Yes      | string | Fully-qualified stage path, e.g. `@my_db.my_schema.skill_stage`. |

Standard dbt configs (`database`, `schema`, `alias`, `tags`, `pre_hook`, `post_hook`, …) work
as usual. The model `alias` becomes the skill folder name on the stage.

> **Notes.**
> - The stage is created automatically with `CREATE STAGE IF NOT EXISTS` if it does not already exist.
> - The `SKILL.md` content must not contain `$$` (used as the SQL dollar-quote delimiter internally).
> - To remove a deployed skill file, run `REMOVE @<stage>/skills/<name>/SKILL.md` in Snowflake directly.

---

---

## Evaluations (`cortex_agent_eval` materialization)

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

### Where the questions live

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

### One evaluation per agent

Each evaluation is its own model, so different agents (or different eval sets for the same
agent) each get their own model, dataset name and table. Several evaluations can point at the
same table. Nothing is shared unless you choose to share it.

### Defining an evaluation

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
   with the same name first, since Snowflake refuses to re-create one, and because the dataset is a
   snapshot this also refreshes it after the table changes),
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

### Running an evaluation

```bash
dbt seed --select support_agent_questions
dbt build --select support_agent_eval

# start a run and block until it finishes (non-zero exit unless COMPLETED)
dbt run-operation run_cortex_agent_eval \
  --args '{eval: support_agent_eval, run_name: nightly-1, wait: true}'
```

| Operation | Args | Description |
|-----------|------|-------------|
| `run_cortex_agent_eval` | `eval`, `run_name` (default `<eval>_<UTC timestamp>`), `wait` (default `false`), `timeout_seconds` (default `1800`), `poll_seconds` (default `15`) | Starts a run. With `wait: true` it polls until a terminal state and fails the operation unless the run is `COMPLETED`, so it can gate CI. |
| `cortex_agent_eval_status` | `eval`, `run_name` | Prints the run's status. |
| `cancel_cortex_agent_eval` | `eval`, `run_name` | Cancels an in-progress run. |
| `delete_cortex_agent_eval_run` | `eval`, `run_name` | Deletes a run and its results. |

`eval` is a `cortex_agent_eval` model name, or a full stage path to a config file
(`@db.schema.stage/path/config.yaml`). `run_name` may contain letters, digits, `_`, `.` and `-`, and
must be unique per agent. Statuses progress `CREATED`, `INVOCATION_IN_PROGRESS`,
`INVOCATION_COMPLETED`, `COMPUTATION_IN_PROGRESS`, `COMPLETED`. The terminal states are
`COMPLETED`, `PARTIALLY_COMPLETED`, `CANCELLED` and `FAILED`. `FAILED` is not in Snowflake's
documented list but is returned when the agent invocation fails.

To evaluate a specific agent version in CI, template `agent_version` in the YAML (as above) and
rebuild the config with `dbt build --select support_agent_eval --vars '{agent_version: VERSION$3}'`
before running it.

### Reading results

```sql
select metric_name, avg(eval_agg_score) as avg_score
from ({{ dbt_cortex_agent.cortex_agent_eval_results(ref('support_agent'), 'nightly-1') }})
group by 1
```

This wraps `SNOWFLAKE.LOCAL.GET_AI_EVALUATION_DATA`. Land the output in an incremental model to
trend scores per run or agent version.

### Configuration reference

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

> **Notes.**
> - **Privileges.** Running evaluations needs `SNOWFLAKE.CORTEX_USER`, `USAGE` and `MONITOR` (or
>   `OWNERSHIP`) on the agent, `CREATE DATASET` and `CREATE STAGE` on the schema, and
>   **`EXECUTE TASK ON ACCOUNT`**. Without `EXECUTE TASK`, `START` succeeds but the run stays in
>   `CREATED` indefinitely, so `wait: true` will time out. See the
>   [access control requirements](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations).
> - The evaluation YAML must not contain `$$` (used as the SQL dollar-quote delimiter internally).
> - The uploaded YAML is re-serialized when a `dataset:` block is present, so comments and key order
>   are not preserved in the staged copy (its meaning is unchanged).
> - Evaluations run in the agent's database and schema, and are not supported for agents that use
>   row access policies or MCP connectors. See Snowflake's limitations for tool metrics.
> - `timeout_seconds` is approximate: it is converted to a number of polls, and each poll also
>   spends time on the status query.
> - To remove a deployed config, run `REMOVE @<stage>/evals/<name>/config.yaml`. To drop a dataset,
>   run `DROP DATASET <name>`.

---

## `cortex_mcp_server` — External MCP servers

The `cortex_mcp_server` materialization creates a Snowflake **External MCP Server**
object (`CREATE EXTERNAL MCP SERVER`) from a config-only dbt model. Once created,
the MCP server can be wired into a `cortex_agent` model with `ref()` so that the
DAG enforces correct build order.

### Create the API integration with `cortex_mcp_api_integration` (recommended)

An External MCP Server references a Snowflake **API INTEGRATION** object that
authenticates Snowflake's outbound calls to the MCP endpoint. API integrations
are account-level objects that require **ACCOUNTADMIN** (or **CREATE INTEGRATION**)
privilege to create — the same as any other privilege a `dbt build` role
needs on its own target objects, just scoped to the account instead of a schema.

The `cortex_mcp_api_integration` materialization makes the integration a
first-class dbt model, the same way `cortex_mcp_server` and `cortex_skill`
already are: it's a real DAG node, so a `cortex_mcp_server` model can `ref()`
it and `dbt build` enforces creation order automatically, and it shows up in
`dbt ls`/lineage graphs instead of being a config string that has to match an
object created out-of-band.

`models/jira_mcp_api_integration.sql` — model body is empty, all parameters via `config()`:

```sql
{{
  config(
    materialized       = 'cortex_mcp_api_integration',
    allowed_prefixes   = ['https://mcp.atlassian.com'],
    auth_type          = 'OAUTH_DYNAMIC_CLIENT',
    oauth_resource_url = 'https://mcp.atlassian.com/v1/mcp'
  )
}}
```

For OAuth2 client credentials (providers without Dynamic Client Registration):

```sql
{{
  config(
    materialized                  = 'cortex_mcp_api_integration',
    allowed_prefixes              = ['https://api.example.com/mcp'],
    auth_type                     = 'OAUTH2',
    oauth_client_id               = 'abc123',
    oauth_client_secret           = 's3cr3t',
    oauth_token_endpoint          = 'https://api.example.com/oauth/token',
    oauth_authorization_endpoint  = 'https://api.example.com/oauth/authorize'
  )
}}
```

The integration's Snowflake object name is the model's alias (same convention
`cortex_mcp_server` uses). `dbt build` creates it with **`CREATE API INTEGRATION
IF NOT EXISTS`** by default (`if_not_exists=true`) rather than `CREATE OR REPLACE`
— a broad selector, `state:modified.body` sweep, or `--full-refresh` shouldn't be
able to silently rotate a live OAuth-authenticated integration as a side effect
of an unrelated rebuild. Pass `if_not_exists=false` explicitly if you do want
replace-in-place semantics (e.g. to deliberately rotate configuration).

### Alternative: `create_mcp_api_integration` operation

If you'd rather bootstrap the integration manually outside of `dbt build` —
e.g. from a session that only holds ACCOUNTADMIN for the duration of the
bootstrap — the original run-operation still works and behaves exactly as
before (including its `if_not_exists=false` / `CREATE OR REPLACE` default):

```bash
# Dynamic Client Registration (recommended for DCR-capable providers, e.g. Atlassian):
dbt run-operation create_mcp_api_integration --args '{
  integration_name: jira_mcp_api_integration,
  allowed_prefixes: ["https://mcp.atlassian.com"],
  auth_type: OAUTH_DYNAMIC_CLIENT,
  oauth_resource_url: "https://mcp.atlassian.com/v1/mcp"
}'

# OAuth2 client credentials (for providers without DCR):
dbt run-operation create_mcp_api_integration --args '{
  integration_name: my_mcp_api_integration,
  allowed_prefixes: ["https://api.example.com/mcp"],
  auth_type: OAUTH2,
  oauth_client_id: "abc123",
  oauth_client_secret: "s3cr3t",
  oauth_token_endpoint: "https://api.example.com/oauth/token",
  oauth_authorization_endpoint: "https://api.example.com/oauth/authorize"
}'
```

Use `dry_run=true` to preview the DDL without executing it:

```bash
dbt run-operation create_mcp_api_integration --args '{
  integration_name: jira_mcp_api_integration,
  allowed_prefixes: ["https://mcp.atlassian.com"],
  auth_type: OAUTH_DYNAMIC_CLIENT,
  oauth_resource_url: "https://mcp.atlassian.com/v1/mcp",
  dry_run: true
}'
```

Whichever path creates it, if the API integration does not exist when
`dbt build` reaches a `cortex_mcp_server` model, the materialization fails
immediately with a clear error message that names the missing integration and
shows both bootstrap options.

### Defining an MCP server model

The model body is empty — all parameters are supplied via `config()`. Use
`cortex_mcp_api_integration_name(ref(...))` to wire in an integration created
by the materialization above (registers the DAG dependency); pass a plain
string instead if the integration was created out-of-band via the
run-operation.

`models/atlassian_mcp_server.sql`:

```sql
{{
  config(
    materialized    = 'cortex_mcp_server',
    display_name    = 'Atlassian (Jira & Confluence)',
    url             = 'https://mcp.atlassian.com/v1/mcp',
    api_integration = dbt_cortex_agent.cortex_mcp_api_integration_name(ref('jira_mcp_api_integration'))
  )
}}
```

### Wiring an MCP server to an agent

Use the `cortex_mcp_server_name()` macro with `ref()` to wire the server into an
agent model body. This both registers the DAG dependency (the agent will not be
created until the MCP server object exists) and derives the correct
`database.schema.name` automatically:

`models/my_agent.sql`:

```sql
{{
  config(materialized = 'cortex_agent')
}}
models:
  orchestration: claude-4-sonnet
instructions:
  response: "Be concise."
  orchestration: "Use the Atlassian MCP server for Jira and Confluence questions."
mcp_servers:
  - server_spec:
      name: "{{ dbt_cortex_agent.cortex_mcp_server_name(ref('atlassian_mcp_server')) }}"
```

### `cortex_mcp_server` configuration reference

| Config            | Required | Type   | Description |
|-------------------|----------|--------|-------------|
| `display_name`    | Yes      | string | Human-readable label shown in Snowflake. |
| `url`             | Yes      | string | MCP server endpoint URL. |
| `api_integration` | Yes      | string | Name of the Snowflake API integration object — pass `dbt_cortex_agent.cortex_mcp_api_integration_name(ref('...'))` to wire a DAG dependency, or a plain string for an out-of-band integration. |

### `cortex_mcp_api_integration` configuration reference

| Config                         | Required                    | Type         | Description |
|--------------------------------|-----------------------------|--------------|-------------|
| `allowed_prefixes`             | Yes                         | list[string] | Base URL(s) of the MCP server, matched as a prefix. |
| `auth_type`                    | No (default `OAUTH_DYNAMIC_CLIENT`) | string | `OAUTH_DYNAMIC_CLIENT` or `OAUTH2`. |
| `oauth_resource_url`           | Yes (OAUTH_DYNAMIC_CLIENT)  | string       | MCP server URL used for DCR. |
| `oauth_client_id`              | Yes (OAUTH2)                | string       | OAuth2 client ID. |
| `oauth_client_secret`          | Yes (OAUTH2)                | string       | OAuth2 client secret. |
| `oauth_token_endpoint`         | Yes (OAUTH2)                | string       | OAuth2 token endpoint URL. |
| `oauth_authorization_endpoint` | Yes (OAUTH2)                | string       | OAuth2 authorization endpoint URL. |
| `oauth_client_auth_method`     | No (OAUTH2 only)            | string       | `CLIENT_SECRET_BASIC` or `CLIENT_SECRET_POST`. |
| `oauth_discovery_url`          | No (OAUTH2 only)            | string       | OIDC discovery URL. |
| `oauth_refresh_token_validity` | No (OAUTH2 only)            | int          | Refresh token validity in seconds. |
| `enabled`                      | No (default `true`)         | bool         | Whether the integration is enabled. |
| `if_not_exists`                | No (default **`true`**)     | bool         | Use `IF NOT EXISTS` instead of `OR REPLACE`. Defaults opposite to the `create_mcp_api_integration` operation — see the note above on why. |
| `comment`                      | No                          | string       | Optional `COMMENT` clause. |

The integration's Snowflake object name is always the model's alias — there is
no `integration_name` config (unlike the operation below), since the model
identity already provides it.

### `create_mcp_api_integration` operation reference

| Parameter                    | Required                    | Type         | Description |
|------------------------------|-----------------------------|--------------|-------------|
| `integration_name`           | Yes                         | string       | Snowflake object name for the API integration. |
| `allowed_prefixes`           | Yes                         | list[string] | Base URL(s) of the MCP server, matched as a prefix. |
| `auth_type`                  | No (default `OAUTH_DYNAMIC_CLIENT`) | string | `OAUTH_DYNAMIC_CLIENT` or `OAUTH2`. |
| `oauth_resource_url`         | Yes (OAUTH_DYNAMIC_CLIENT)  | string       | MCP server URL used for DCR. |
| `oauth_client_id`            | Yes (OAUTH2)                | string       | OAuth2 client ID. |
| `oauth_client_secret`        | Yes (OAUTH2)                | string       | OAuth2 client secret. |
| `oauth_token_endpoint`       | Yes (OAUTH2)                | string       | OAuth2 token endpoint URL. |
| `oauth_authorization_endpoint` | Yes (OAUTH2)              | string       | OAuth2 authorization endpoint URL. |
| `oauth_client_auth_method`   | No (OAUTH2 only)            | string       | `CLIENT_SECRET_BASIC` or `CLIENT_SECRET_POST`. |
| `oauth_discovery_url`        | No (OAUTH2 only)            | string       | OIDC discovery URL. |
| `oauth_refresh_token_validity` | No (OAUTH2 only)          | int          | Refresh token validity in seconds. |
| `enabled`                    | No (default `true`)         | bool         | Whether the integration is enabled. |
| `if_not_exists`              | No (default `false`)        | bool         | Use `IF NOT EXISTS` instead of `OR REPLACE`. |
| `dry_run`                    | No (default `false`)        | bool         | Log DDL without executing. |
| `comment`                    | No                          | string       | Optional `COMMENT` clause. |

> **Privilege note.** `create_mcp_api_integration` requires **ACCOUNTADMIN** or the
> **CREATE INTEGRATION** account-level privilege. This is a one-time admin operation;
> normal dbt runs do not need elevated privileges once the integration exists.

---

## `cortex_agent` configuration reference

| Config            | Mode            | Type           | Description |
|-------------------|-----------------|----------------|-------------|
| `comment`         | specification   | string         | Sets the agent-level `COMMENT` clause. Single quotes are escaped automatically. |
| `profile`         | specification   | dict or string | Sets the `PROFILE` clause. A dict is serialized to JSON for you (`display_name`, `avatar`, `color`); a string is used verbatim. |
| `web_search_tool`     | specification   | bool (default `false`) | When `true`, injects a `tool_spec` entry for web search into the agent specification YAML, enabling live web search for the agent. If your spec already has a `tools:` block, add the entry there directly instead. |
| `analytical_search`   | specification   | bool (default `false`) | When `true`, merges `orchestration.capabilities.analytical_search: true` into the spec via YAML parse-and-merge. Composes correctly with the `budget` config and with an `orchestration:` block in the body. Requires a `cortex_search` tool in the spec (a warning is emitted if none is found). **Preview** — additional AI function charges apply. Ignored under `raw_ddl = true`. |
| `code_execution_tool` | specification   | bool or dict (default `false`) | When `true`, injects a `code_execution` tool entry and an empty `tool_resources.code_execution` block into the spec using YAML parse-and-merge (safe with existing `tools:` blocks). Pass a dict to set `permission_policy` (`'always_ask'` or `'always_allow'`) and/or `artifact_repositories`. Mutually exclusive with `code_toolset_all` in the spec body. Preview feature as of August 2026. |
| `raw_ddl`             | both            | bool (default `false`) | When `true`, the model body is treated as raw DDL appended after `CREATE OR REPLACE AGENT <name>`, and `comment` / `profile` / `web_search_tool` / `analytical_search` / `code_execution_tool` configs are ignored (a compile-time warning is emitted if any of these are set). |
| `versioning`      | specification   | bool (default `false`) | Master switch for versioned mode. When `true`, creates the agent once and then commits each changed spec as a new version (`MODIFY LIVE VERSION` + `COMMIT`) instead of `CREATE OR REPLACE`. Incompatible with `raw_ddl=true` (a warning is emitted and the run falls back to `CREATE OR REPLACE`). Switching back to `false` runs `CREATE OR REPLACE`, which wipes the version history and aliases. |
| `version_name`    | specification (versioning=true) | string | Alias to tag the newly committed version with (Snowflake names the version itself, `VERSION$<n>`). Must be a valid unquoted identifier (`^[A-Za-z_][A-Za-z0-9_$]*$`, checked at compile time); stored uppercased; unique per agent — reusing one moves it to the new version. When omitted, auto-generated as `v_YYYYMMDD_HHMMSS` from `run_started_at` — deterministic within a run. |
| `set_default`     | specification (versioning=true) | bool (default `true`) | When `true`, pins the agent's `DEFAULT VERSION` to the newly committed version (or to the newest version, if the spec is unchanged). Set `false` to commit a staging/canary version without affecting live traffic — the current default is pinned first. |

Standard dbt configs (`database`, `schema`, `alias`, `tags`, `pre_hook`,
`post_hook`, `grants`, `enabled`, …) all work as usual. The agent is created
in the model's target database/schema with the model's `alias` as its name.

---

## How it works

- **`cortex_skill` materialization** (`macros/materializations/cortex_skill.sql`) — runs
  pre-hooks, creates the stage if needed, issues `PUT 'file://dir/*' @stage/skills/<name>/`
  to upload all skill files, runs post-hooks, and returns the relation.
- **`cortex_agent` materialization** (`macros/materializations/cortex_agent.sql`) — sets the
  query tag, runs pre-hooks, issues a single `CREATE OR REPLACE AGENT`
  statement, runs post-hooks, and returns the relation.
- **DDL builder** (`macros/relations/cortex_agent/create.sql`) — constructs the
  statement for both specification and raw modes.
- **Drop / rename** (`macros/relations/cortex_agent/{drop,rename}.sql`) —
  provide `drop agent if exists` and `alter agent ... rename to` DDL.
- **`cortex_mcp_api_integration` materialization**
  (`macros/materializations/cortex_mcp_api_integration.sql`) — sets the query
  tag, runs pre-hooks, issues a single `CREATE API INTEGRATION IF NOT EXISTS`
  (or `CREATE OR REPLACE` with `if_not_exists=false`) statement, runs
  post-hooks, and returns the relation.
- **Shared DDL builder** (`macros/operations/create_mcp_api_integration.sql`,
  `_mcp_api_integration_ddl`) — validates arguments and constructs the
  `CREATE API INTEGRATION` statement. Both the `cortex_mcp_api_integration`
  materialization and the `create_mcp_api_integration` run-operation call this
  same macro, so they can never drift on DDL shape or validation rules — only
  on their own `if_not_exists` default and whether they execute immediately or
  log/return.
- **Drop / rename** (`macros/relations/cortex_mcp_api_integration/{drop,rename}.sql`) —
  provide `drop api integration if exists` and `alter api integration ... rename to` DDL.

Every run issues `CREATE OR REPLACE AGENT`, which is idempotent and atomic, so
re-running a model simply replaces the agent in place.

---

## Limitations & notes

- **Relation type.** Snowflake Agents are not yet a first-class dbt relation
  type, so the node is tracked internally as a `view` for graph/lineage
  purposes only. dbt never issues `CREATE VIEW` for it — the materialization only
  ever runs `CREATE OR REPLACE AGENT`.
- **`persist_docs` is not supported.** Use the inline `comment` config (or
  `COMMENT` clause in raw mode) instead. This mirrors the `dbt_semantic_view`
  package's behavior for the same underlying reason.
- **Name collisions.** `CREATE OR REPLACE AGENT` fails if a non-agent object of
  the same name already exists in the schema. Choose a name/alias that does not
  collide with an existing table or view.
- **Privileges.** The executing role needs the privileges to create agents
  (e.g. `CREATE AGENT` on the schema) and to reference any semantic views or
  Cortex Search services named in `tool_resources`. See the
  [Cortex Agents docs](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-manage).
- **`cortex_mcp_api_integration` is account-level, like `cortex_mcp_server`.**
  Snowflake API INTEGRATION objects have no database/schema, so (same as
  `cortex_mcp_server`) the node is tracked internally as a `view` for
  graph/lineage purposes only — dbt never issues `CREATE VIEW` for it. The
  executing role needs **ACCOUNTADMIN** or **CREATE INTEGRATION** account-level
  privilege, which is broader than what most other models in a project need;
  scope which role runs this model accordingly (e.g. a separate `dbt build
  --select cortex_mcp_api_integration:*` step under an elevated role, if your
  normal service account shouldn't hold that privilege day-to-day).
- **`if_not_exists` default differs by entry point.** The
  `cortex_mcp_api_integration` materialization defaults to `if_not_exists=true`;
  the `create_mcp_api_integration` operation defaults to `if_not_exists=false`
  (`CREATE OR REPLACE`), preserved for backward compatibility with existing
  callers. See the config reference tables above.

---

## Integration tests

A runnable integration-test project lives in `integration_tests/`. See
`integration_tests/README.md` for setup (Snowflake env vars, `dbt deps`,
`dbt build`).

---

## References

- [CREATE AGENT — Snowflake SQL reference](https://docs.snowflake.com/en/sql-reference/sql/create-agent)
- [Cortex Agents — overview](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents)
- [Configure and interact with Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-manage)
- [Cortex Agent evaluations](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations)
- [dbt_semantic_view (design inspiration)](https://github.com/Snowflake-Labs/dbt_semantic_view)

## License

MIT License. See [`LICENSE`](LICENSE).
