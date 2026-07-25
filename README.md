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

- **Materializations:** `cortex_agent`, `cortex_skill`
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

## `cortex_agent` configuration reference

| Config            | Mode            | Type           | Description |
|-------------------|-----------------|----------------|-------------|
| `comment`         | specification   | string         | Sets the agent-level `COMMENT` clause. Single quotes are escaped automatically. |
| `profile`         | specification   | dict or string | Sets the `PROFILE` clause. A dict is serialized to JSON for you (`display_name`, `avatar`, `color`); a string is used verbatim. |
| `web_search_tool` | specification   | bool (default `false`) | When `true`, injects a `tool_spec` entry for web search into the agent specification YAML, enabling live web search for the agent. If your spec already has a `tools:` block, add the entry there directly instead. |
| `raw_ddl`         | both            | bool (default `false`) | When `true`, the model body is treated as raw DDL appended after `CREATE OR REPLACE AGENT <name>`, and `comment` / `profile` / `web_search_tool` configs are ignored (a compile-time warning is emitted if any of these are set). |

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
- [dbt_semantic_view (design inspiration)](https://github.com/Snowflake-Labs/dbt_semantic_view)

## License

MIT License. See [`LICENSE`](LICENSE).
