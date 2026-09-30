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

Currently only available on the Snowflake adapter.

---

## At a glance

- **Materializations:** `cortex_agent`, `cortex_skill`, `cortex_agent_eval`, `cortex_mcp_server`, `cortex_mcp_api_integration`
- **Warehouse:** Snowflake (Cortex Agents)
- **dbt compatibility:** dbt 1.5+
- **Underlying DDL:** [`CREATE AGENT`](https://docs.snowflake.com/en/sql-reference/sql/create-agent) / `PUT 'file://...' @stage`

---

## Installation

Add to `packages.yml`:

```yaml
packages:
  - package: Matts52/dbt_cortex_agent
    version: 1.0.0
```

```bash
dbt deps
```

Or install directly from GitHub:

```yaml
packages:
  - git: "https://github.com/Matts52/dbt-cortex-agent.git"
    revision: 1.0.0
```

---

## Usage

### `cortex_agent`

The model body is the agent specification YAML. The package wraps it in
`FROM SPECIFICATION $$ ... $$`. Use `ref()` / `source()` inside `tool_resources` to wire
tools to other models in your DAG.

```sql
{{
  config(
    materialized = 'cortex_agent',
    comment      = 'Sales analytics assistant'
  )
}}
models:
  orchestration: claude-4-sonnet
instructions:
  response: "Be concise."
tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "Analyst"
      description: "Text-to-SQL for financial analysis."
tool_resources:
  Analyst:
    semantic_view: "{{ ref('sales_semantic_view') }}"
    execution_environment:
      type: "warehouse"
      warehouse: "MY_WAREHOUSE"
```

Config shorthands: `web_search_tool`, `analytical_search`, `code_execution_tool`, `budget`,
`versioning` (canary rollout / version history), `raw_ddl` (pass-through DDL).

→ [Full reference: docs/cortex_agent.md](docs/cortex_agent.md)

### `cortex_skill`

Upload a skill directory to a Snowflake stage as part of `dbt build`. Place the skill files
in a directory with the same name as the model (no extension), then reference the skill from
an agent with `cortex_skill_path(ref(...))`.

```
models/skills/
  forecaster_skill.sql        ← config only
  forecaster_skill/
    SKILL.md                  ← required
    forecaster.py             ← optional scripts
```

```sql
-- forecaster_skill.sql
{{ config(materialized='cortex_skill', stage='@my_db.my_schema.skill_stage') }}
```

```sql
-- my_agent.sql (referencing the skill)
skills:
  - name: forecaster
    source:
      type: STAGE
      path: "{{ dbt_cortex_agent.cortex_skill_path(ref('forecaster_skill')) }}"
```

→ [Full reference: docs/cortex_skill.md](docs/cortex_skill.md)

### `cortex_agent_eval`

Deploy an evaluation dataset and YAML config to a stage with `dbt build`, then run
evaluations explicitly via `run-operation`.

```sql
{{
  config(
    materialized = 'cortex_agent_eval',
    stage        = '@my_db.my_schema.eval_stage'
  )
}}
dataset:
  table_name: "{{ ref('support_agent_questions') }}"
  dataset_name: "support_agent_golden"
  column_mapping:
    query_text: question
    ground_truth: expected
evaluation:
  agent_params:
    agent_name: "{{ ref('support_agent') }}"
    agent_type: "CORTEX AGENT"
```

```bash
dbt run-operation run_cortex_agent_eval \
  --args '{eval: support_agent_eval, run_name: nightly-1, wait: true}'
```

→ [Full reference: docs/cortex_agent_eval.md](docs/cortex_agent_eval.md)

### `cortex_mcp_server` and `cortex_mcp_api_integration`

Create a Snowflake External MCP Server as a DAG node, with its API integration managed either
as a sibling dbt model or bootstrapped via run-operation.

```sql
-- jira_mcp_api_integration.sql
{{
  config(
    materialized       = 'cortex_mcp_api_integration',
    allowed_prefixes   = ['https://mcp.atlassian.com'],
    auth_type          = 'OAUTH_DYNAMIC_CLIENT',
    oauth_resource_url = 'https://mcp.atlassian.com/v1/mcp'
  )
}}
```

```sql
-- atlassian_mcp_server.sql
{{
  config(
    materialized    = 'cortex_mcp_server',
    display_name    = 'Atlassian (Jira & Confluence)',
    url             = 'https://mcp.atlassian.com/v1/mcp',
    api_integration = dbt_cortex_agent.cortex_mcp_api_integration_name(ref('jira_mcp_api_integration'))
  )
}}
```

→ [Full reference: docs/cortex_mcp_server.md](docs/cortex_mcp_server.md)

---

## Limitations & notes

- **Relation type.** Snowflake Agents are not yet a first-class dbt relation type, so nodes are
  tracked internally as `view` for graph/lineage purposes only. dbt never issues `CREATE VIEW`.
- **`persist_docs` is not supported.** Use the inline `comment` config (or `COMMENT` clause in
  raw mode) instead.
- **Name collisions.** `CREATE OR REPLACE AGENT` fails if a non-agent object of the same name
  already exists in the schema.
- **Privileges.** The executing role needs `CREATE AGENT` on the schema and `USAGE` on any
  semantic views or Cortex Search services named in `tool_resources`. See the
  [Cortex Agents docs](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-manage).
- **`cortex_mcp_api_integration` is account-level.** Requires ACCOUNTADMIN or CREATE INTEGRATION
  privilege. Consider a separate `dbt build --select cortex_mcp_api_integration:*` step under an
  elevated role if your normal service account shouldn't hold that privilege day-to-day.

---

## Integration tests

A runnable integration-test project lives in `integration_tests/`. See
[`integration_tests/README.md`](integration_tests/README.md) for setup.

---

## References

- [CREATE AGENT — Snowflake SQL reference](https://docs.snowflake.com/en/sql-reference/sql/create-agent)
- [Cortex Agents — overview](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents)
- [Configure and interact with Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-manage)
- [Cortex Agent evaluations](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations)
- [dbt_semantic_view (design inspiration)](https://github.com/Snowflake-Labs/dbt_semantic_view)

## License

MIT License. See [`LICENSE`](LICENSE).
