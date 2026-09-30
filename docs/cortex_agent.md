# `cortex_agent` materialization

Full reference for creating and managing Snowflake Cortex Agents from dbt models.

---

## Usage modes

### 1. Specification mode (default)

The model body **is the agent specification YAML**. The package wraps it in
`FROM SPECIFICATION $$ ... $$` and emits the optional `COMMENT` and `PROFILE` clauses from config.

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

> **Tip — wiring tools to your DAG.** Because the body is rendered through Jinja, you can use
> `{{ ref(...) }}` and `{{ source(...) }}` inside `tool_resources` to point a tool at a semantic
> view or Cortex Search service managed elsewhere in your project.

### 2. Raw DDL mode (`raw_ddl=true`)

The body is **everything that follows `CREATE OR REPLACE AGENT <name>`** — a direct pass-through
to Snowflake. Use this when you want to control the exact clause ordering or adopt new
`CREATE AGENT` syntax before the package models it.

> **Note:** The `comment`, `profile`, `web_search_tool`, `analytical_search`, and
> `code_execution_tool` configs are silently ignored in raw DDL mode — a compile-time warning is
> emitted if any of them are set alongside `raw_ddl=true`.

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

By default, every `dbt run` issues `CREATE OR REPLACE AGENT` — the new spec is live the instant
the run finishes, with no version history and no rollback path.

Set `versioning=true` to use Snowflake's [agent versioning](https://docs.snowflake.com/en/sql-reference/sql/alter-agent)
instead. Snowflake names committed versions itself (`VERSION$1`, `VERSION$2`, …); the package
tracks whether the agent already exists and issues the appropriate DDL:

- **First run (agent absent):** `CREATE AGENT ... FROM SPECIFICATION $$...$$` — Snowflake commits
  it as `VERSION$1`, which the package always pins as the default (Snowflake's initial default is
  the floating `LAST`).
- **Subsequent runs (agent present):**
  1. `ALTER AGENT ... ADD LIVE VERSION FROM LAST` (only if no live version is open)
  2. `ALTER AGENT ... MODIFY LIVE VERSION SET SPECIFICATION = $$...$$`
  3. `ALTER AGENT ... SET COMMENT = ..., PROFILE = ...` (when configured)
  4. `ALTER AGENT ... COMMIT` — **skipped when the spec is unchanged**, so re-running an unchanged
     model does not pile up identical versions.
- **Promotion (when `set_default=true`, the default):** `ALTER AGENT ... SET DEFAULT_VERSION = 'VERSION$<n>'`.
- **Tagging:** the new version gets `version_name` as its alias.

The agent is never dropped or replaced on this path, so its version history and grants survive
every run.

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

When `version_name` is omitted, each run tags the new version with an alias generated from
`run_started_at` as `v_YYYYMMDD_HHMMSS` — deterministic within a run.

`version_name` must be a valid unquoted Snowflake identifier (`^[A-Za-z_][A-Za-z0-9_$]*$`);
an invalid name fails the run at compile time. Aliases are unique per agent: reusing one moves it
to the new version, so a floating tag like `canary` works naturally.

#### Staging a canary version

Deploy a new spec without affecting live traffic by setting `set_default=false`:

```sql
{{
  config(
    materialized = 'cortex_agent',
    versioning   = true,
    version_name = 'canary',
    set_default  = false
  )
}}
```

After validating the canary out of band, promote it by flipping `set_default` back to `true` and
re-running (no new version is committed if the spec is unchanged — the newest version is just
promoted), or directly:

```bash
dbt run-operation set_cortex_agent_default_version --args '{agent: my_db.my_schema.my_agent, version: canary}'
```

#### Rollback

Point the default at any earlier version, by alias or by Snowflake version name:

```bash
dbt run-operation set_cortex_agent_default_version --args '{agent: my_db.my_schema.my_agent, version: v_20250101_120000}'
dbt run-operation set_cortex_agent_default_version --args '{agent: my_db.my_schema.my_agent, version: VERSION$3}'
```

A later `dbt run` with `set_default=true` promotes the newest version again, so make the rollback
permanent by reverting the spec in git.

> **Warning:** switching a model from `versioning=true` back to `false` makes the next run issue
> `CREATE OR REPLACE AGENT`, which wipes the agent's entire version history and all aliases.

> **Note:** `versioning=true` is incompatible with `raw_ddl=true`. If both are set, a
> compile-time warning is emitted and the materialization falls back to `CREATE OR REPLACE`
> behavior.

---

## Config shorthands

### `analytical_search` (Preview)

[Analytical search](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-analytical-search)
tells the Cortex Agent orchestrator to run an extended analytics loop over Cortex Search results:
after narrowing the candidate set with Cortex Search, the agent applies `AI_FILTER`,
`AI_EXTRACT`, and `AI_AGG` to support filtered lists, aggregates, and temporal analysis queries.
It is off by default and **billed through AI functions** in addition to standard Cortex Search
costs.

Add `analytical_search = true` to enable it. The package merges
`orchestration.capabilities.analytical_search: true` into the spec via YAML parse-and-merge,
so it composes correctly with any `orchestration:` block already in the body and with the
`budget` config shorthand.

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

> **Tip:** Snowflake's analytical search documentation recommends `max_results: 1000` to give the
> analytics loop a large enough candidate set to aggregate over. The default (`5`) is appropriate
> for retrieval but too small for aggregation queries.

A compile-time warning is emitted if `analytical_search = true` is set but the spec has no
`cortex_search` tool. The config is ignored (with a warning) under `raw_ddl = true`.

### `web_search_tool`

Add `web_search_tool = true` to give the agent access to Snowflake's built-in web search:

```sql
{{
  config(
    materialized    = 'cortex_agent',
    web_search_tool = true
  )
}}
models:
  orchestration: claude-4-sonnet
```

This injects into the compiled spec:

```yaml
tools:
  - tool_spec:
      type: "web_search"
      name: "web_search"
```

> **Note:** If your spec already contains a `tools:` block, set `web_search_tool = false` and
> add the entry directly in your spec's `tools:` list to avoid a duplicate key.

### `code_execution_tool` (Preview)

> **Preview:** The code execution tool is in Public Preview as of August 20, 2026. Check the
> [Snowflake release notes](https://docs.snowflake.com/en/release-notes/2026/ui/2026-08-20) for
> any changes before using in production.

Add `code_execution_tool = true` to give the agent a Python sandbox that can run calculations,
process data with numpy/pandas/scipy, and generate matplotlib/plotly charts:

```sql
{{
  config(
    materialized        = 'cortex_agent',
    code_execution_tool = true
  )
}}
```

This injects into the compiled spec:

```yaml
tools:
  - tool_spec:
      type: "code_execution"
      name: "code_execution"
tool_resources:
  code_execution: {}
```

**Map form** — pass a dict to configure `permission_policy` or allow PyPI packages via
`artifact_repositories`:

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

- `permission_policy`: `'always_ask'` (default — prompts before state-modifying operations) or
  `'always_allow'`.
- `artifact_repositories`: list of repository identifiers. Using
  `SNOWFLAKE.SNOWPARK.PYPI_SHARED_REPOSITORY` requires the `SNOWFLAKE.PYPI_REPOSITORY_USER` role.

**Composing with other tools:** unlike `web_search_tool`, `code_execution_tool` uses YAML
parse-and-merge, so it is safe to use alongside an existing `tools:` block in the spec body.

**Limitation:** `code_execution` and `code_toolset_all` are mutually exclusive — setting
`code_execution_tool = true` while the spec body declares `code_toolset_all` raises a
compile-time error.

Required privileges: `MODIFY` on the agent to configure the tool; `USAGE` to invoke it at runtime.

---

## Configuration reference

| Config                | Mode                            | Type                     | Description |
|-----------------------|---------------------------------|--------------------------|-------------|
| `comment`             | specification                   | string                   | Sets the agent-level `COMMENT` clause. Single quotes are escaped automatically. |
| `profile`             | specification                   | dict or string           | Sets the `PROFILE` clause. A dict is serialized to JSON (`display_name`, `avatar`, `color`); a string is used verbatim. |
| `web_search_tool`     | specification                   | bool (default `false`)   | Injects a `web_search` tool spec entry. If your spec already has a `tools:` block, add the entry there directly instead. |
| `analytical_search`   | specification                   | bool (default `false`)   | Merges `orchestration.capabilities.analytical_search: true` via YAML parse-and-merge. Requires a `cortex_search` tool. **Preview** — additional AI function charges apply. |
| `code_execution_tool` | specification                   | bool or dict (default `false`) | Injects a `code_execution` tool and empty `tool_resources.code_execution` block via YAML parse-and-merge. Pass a dict to set `permission_policy` and/or `artifact_repositories`. Mutually exclusive with `code_toolset_all`. Preview feature. |
| `raw_ddl`             | both                            | bool (default `false`)   | When `true`, the model body is treated as raw DDL appended after `CREATE OR REPLACE AGENT <name>`. All other configs except standard dbt configs are ignored. |
| `versioning`          | specification                   | bool (default `false`)   | When `true`, uses `ALTER AGENT ... MODIFY LIVE VERSION ... COMMIT` instead of `CREATE OR REPLACE`. Incompatible with `raw_ddl=true`. Switching back to `false` wipes version history. |
| `version_name`        | specification (`versioning=true`) | string                 | Alias for the newly committed version. Must be a valid unquoted Snowflake identifier. Auto-generated as `v_YYYYMMDD_HHMMSS` when omitted. |
| `set_default`         | specification (`versioning=true`) | bool (default `true`)  | When `true`, pins `DEFAULT VERSION` to the newest committed version. Set `false` to stage a canary without affecting live traffic. |
| `budget`              | specification                   | dict                     | Shorthand to set `orchestration.budget`. Merged via YAML parse-and-merge; composes with `analytical_search` and `orchestration:` blocks in the body. |

Standard dbt configs (`database`, `schema`, `alias`, `tags`, `pre_hook`, `post_hook`, `grants`,
`enabled`, …) all work as usual. The agent is created in the model's target database/schema with
the model's `alias` as its name.

---

## How it works

- **Materialization** (`macros/materializations/cortex_agent.sql`) — sets the query tag, runs
  pre-hooks, issues a single `CREATE OR REPLACE AGENT` statement (or the `ALTER AGENT` sequence
  for versioned mode), runs post-hooks, and returns the relation.
- **DDL builder** (`macros/relations/cortex_agent/create.sql`) — constructs the statement for
  both specification and raw modes.
- **Drop / rename** (`macros/relations/cortex_agent/{drop,rename}.sql`) — provide
  `DROP AGENT IF EXISTS` and `ALTER AGENT ... RENAME TO` DDL.

Every non-versioned run issues `CREATE OR REPLACE AGENT`, which is idempotent and atomic.
