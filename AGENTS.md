# AGENTS.md

Quick reference for AI coding assistants working in this dbt package.

## What this package does

`dbt_cortex_agent` adds five materializations for managing Snowflake Cortex objects from dbt
models, with full DAG integration via `ref()` and `source()`.

| Materialization | Creates | Key macro |
|---|---|---|
| `cortex_agent` | `CREATE OR REPLACE AGENT` | — |
| `cortex_skill` | `PUT` files to a Snowflake stage | `dbt_cortex_agent.cortex_skill_path(ref('...'))` |
| `cortex_agent_eval` | evaluation dataset + YAML config on a stage | — |
| `cortex_mcp_server` | `CREATE EXTERNAL MCP SERVER` | `dbt_cortex_agent.cortex_mcp_server_name(ref('...'))` |
| `cortex_mcp_api_integration` | `CREATE API INTEGRATION` | `dbt_cortex_agent.cortex_mcp_api_integration_name(ref('...'))` |

## Key constraints

- **Snowflake only.** All materializations require the Snowflake adapter.
- **`$$` is forbidden** in model bodies for `cortex_agent`, `cortex_skill`, and
  `cortex_agent_eval` — it's used internally as the SQL dollar-quote delimiter.
- **Relation type.** Agents, MCP servers, and API integrations are tracked internally as
  `view` for graph/lineage purposes only. dbt never issues `CREATE VIEW` for them.
- **`versioning=true` is incompatible with `raw_ddl=true`.** If both are set, a compile-time
  warning is emitted and the run falls back to `CREATE OR REPLACE`.
- **`persist_docs` is not supported** for `cortex_agent`. Use the inline `comment` config instead.
- **`cortex_mcp_api_integration` is account-level** and requires ACCOUNTADMIN or CREATE
  INTEGRATION privilege.

## Macro reference

### `cortex_skill_path(node)`
Returns the stage path for a skill. Use inside an agent spec's `skills[].source.path` field.
Registers the DAG dependency so the skill is uploaded before the agent is created.

```sql
path: "{{ dbt_cortex_agent.cortex_skill_path(ref('my_skill')) }}"
```

### `cortex_mcp_server_name(node)`
Returns the fully-qualified `database.schema.name` for an MCP server object.
Use inside an agent spec's `mcp_servers[].server_spec.name` field.

```sql
name: "{{ dbt_cortex_agent.cortex_mcp_server_name(ref('my_mcp_server')) }}"
```

### `cortex_mcp_api_integration_name(node)`
Returns the object name for an API integration created by the `cortex_mcp_api_integration`
materialization. Use as the `api_integration` config of a `cortex_mcp_server` model.

```sql
api_integration = dbt_cortex_agent.cortex_mcp_api_integration_name(ref('my_api_integration'))
```

## Materialization locations

| File | Purpose |
|---|---|
| `macros/materializations/cortex_agent.sql` | `cortex_agent` materialization |
| `macros/materializations/cortex_skill.sql` | `cortex_skill` materialization |
| `macros/materializations/cortex_agent_eval.sql` | `cortex_agent_eval` materialization |
| `macros/materializations/cortex_mcp_server.sql` | `cortex_mcp_server` materialization |
| `macros/materializations/cortex_mcp_api_integration.sql` | `cortex_mcp_api_integration` materialization |
| `macros/relations/cortex_agent/create.sql` | DDL builder for agents |
| `macros/operations/create_mcp_api_integration.sql` | Shared DDL builder for API integrations |

## Full reference docs

- [`docs/cortex_agent.md`](docs/cortex_agent.md) — spec mode, raw DDL, versioning, config shorthands, config reference
- [`docs/cortex_skill.md`](docs/cortex_skill.md) — skill directory layout, wiring to agents, config reference
- [`docs/cortex_agent_eval.md`](docs/cortex_agent_eval.md) — dataset setup, defining evals, running, reading results
- [`docs/cortex_mcp_server.md`](docs/cortex_mcp_server.md) — API integration options, MCP server model, wiring to agents, config reference
