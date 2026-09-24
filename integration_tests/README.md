# Integration tests — dbt_cortex_agent

End-to-end tests that build real Cortex Agents (and a supporting Semantic View)
against a live Snowflake account.

## What gets built

| Model                      | Materialization    | Purpose |
|----------------------------|--------------------|---------|
| `orders_seed`              | seed               | Sample data. |
| `orders_base`              | table              | Base table over the seed. |
| `orders_semantic_view`     | semantic_view      | Semantic view (via `dbt_semantic_view`) the agent references. |
| `agent_minimal`            | cortex_agent       | Spec mode, instructions only, with `comment` + `profile`. |
| `agent_with_semantic_view` | cortex_agent       | Spec mode, Analyst tool wired to `orders_semantic_view` via `ref()`. |
| `agent_raw_ddl`            | cortex_agent       | `raw_ddl=true` pass-through mode. |
| `jira_mcp_api_integration` | cortex_mcp_api_integration | API integration backing the Atlassian MCP endpoint. |
| `atlassian_mcp_server`     | cortex_mcp_server  | External MCP server for the Atlassian Jira/Confluence endpoint, wired to `jira_mcp_api_integration` via `ref()`. |
| `agent_with_mcp_server`    | cortex_agent       | Agent wired to `atlassian_mcp_server` via `cortex_mcp_server_name(ref(...))`. |

## Prerequisites

- Python 3.9+
- A Snowflake account/role with privileges to create agents, semantic views,
  tables, and to use Cortex.
- **ACCOUNTADMIN or CREATE INTEGRATION** privilege on the role running
  `dbt build` — `jira_mcp_api_integration` creates a Snowflake API INTEGRATION,
  an account-level object, and needs this privilege the same as any other
  model in this project needs privileges on its own target schema. There is
  no separate manual bootstrap step; `dbt build` creates it in DAG order
  before `atlassian_mcp_server` runs.

If your role does not have this privilege, either switch to ACCOUNTADMIN for
the run or fall back to the `create_mcp_api_integration` run-operation from an
admin-privileged session before building (see the main README's
`cortex_mcp_api_integration` section for both paths).

## Run

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -U pip dbt-snowflake

# Point dbt at the bundled profiles.yml
export DBT_PROFILES_DIR="$(pwd)"

export SNOWFLAKE_TEST_ACCOUNT=<account>
export SNOWFLAKE_TEST_USER=<user>
export SNOWFLAKE_TEST_PASSWORD=<password>          # or use externalbrowser
export SNOWFLAKE_TEST_AUTHENTICATOR=snowflake      # snowflake | externalbrowser
export SNOWFLAKE_TEST_ROLE=<role>
export SNOWFLAKE_TEST_DATABASE=<database>
export SNOWFLAKE_TEST_WAREHOUSE=<warehouse>
export SNOWFLAKE_TEST_SCHEMA=<schema>

dbt deps --target snowflake
dbt build --target snowflake
```

## Verify the agents exist

Agents aren't exposed via `INFORMATION_SCHEMA`, so existence is checked with a
run-operation (uses `SHOW AGENTS` + `RESULT_SCAN`):

```bash
dbt run-operation assert_agents_exist --target snowflake
```

Or manually in Snowflake:

```sql
SHOW AGENTS IN SCHEMA <database>.<schema>;
DESCRIBE AGENT <database>.<schema>.AGENT_WITH_SEMANTIC_VIEW;
```

## Validate bootstrap macro DDL output

The `assert_create_mcp_api_integration_ddl` operation validates that
`create_mcp_api_integration` produces correct DDL for both `OAUTH_DYNAMIC_CLIENT`
and `OAUTH2` auth types using `dry_run=true` (no Snowflake privileges required):

```bash
dbt run-operation assert_create_mcp_api_integration_ddl --target snowflake
```

## Clean up

```sql
DROP AGENT IF EXISTS <database>.<schema>.AGENT_MINIMAL;
DROP AGENT IF EXISTS <database>.<schema>.AGENT_WITH_SEMANTIC_VIEW;
DROP AGENT IF EXISTS <database>.<schema>.AGENT_RAW_DDL;
```
