# Integration tests — dbt_cortex_agent

End-to-end tests that build real Cortex Agents (and a supporting Semantic View)
against a live Snowflake account.

## What gets built

| Model                      | Materialization  | Purpose |
|----------------------------|------------------|---------|
| `orders_seed`              | seed             | Sample data. |
| `orders_base`              | table            | Base table over the seed. |
| `orders_semantic_view`     | semantic_view    | Semantic view (via `dbt_semantic_view`) the agent references. |
| `agent_minimal`            | cortex_agent     | Spec mode, instructions only, with `comment` + `profile`. |
| `agent_with_semantic_view` | cortex_agent     | Spec mode, Analyst tool wired to `orders_semantic_view` via `ref()`. |
| `agent_raw_ddl`            | cortex_agent     | `raw_ddl=true` pass-through mode. |

## Prerequisites

- Python 3.9+
- A Snowflake account/role with privileges to create agents, semantic views,
  tables, and to use Cortex.

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

## Clean up

```sql
DROP AGENT IF EXISTS <database>.<schema>.AGENT_MINIMAL;
DROP AGENT IF EXISTS <database>.<schema>.AGENT_WITH_SEMANTIC_VIEW;
DROP AGENT IF EXISTS <database>.<schema>.AGENT_RAW_DDL;
```
