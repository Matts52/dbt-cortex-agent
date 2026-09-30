# `cortex_mcp_server` and `cortex_mcp_api_integration` materializations

Full reference for managing External MCP Servers and their API integrations from dbt models.

The `cortex_mcp_server` materialization creates a Snowflake **External MCP Server** object
(`CREATE EXTERNAL MCP SERVER`) from a config-only dbt model. Once created, the MCP server can
be wired into a `cortex_agent` model with `ref()` so that the DAG enforces correct build order.

---

## Creating the API integration

An External MCP Server references a Snowflake **API INTEGRATION** object that authenticates
Snowflake's outbound calls to the MCP endpoint. API integrations are account-level objects
that require **ACCOUNTADMIN** (or **CREATE INTEGRATION**) privilege to create.

### Option 1: `cortex_mcp_api_integration` materialization (recommended)

Makes the integration a first-class dbt model — a real DAG node that shows up in `dbt ls` and
lineage graphs.

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

The integration's Snowflake object name is the model's alias. `dbt build` creates it with
`CREATE API INTEGRATION IF NOT EXISTS` by default (`if_not_exists=true`) rather than
`CREATE OR REPLACE` — a broad selector or `--full-refresh` shouldn't silently rotate a live
OAuth-authenticated integration as a side effect. Pass `if_not_exists=false` explicitly to
get replace-in-place semantics.

### Option 2: `create_mcp_api_integration` run-operation

Bootstrap the integration manually outside of `dbt build` — e.g. from a session that only
holds ACCOUNTADMIN for the duration of the bootstrap:

```bash
# Dynamic Client Registration (recommended for DCR-capable providers):
dbt run-operation create_mcp_api_integration --args '{
  integration_name: jira_mcp_api_integration,
  allowed_prefixes: ["https://mcp.atlassian.com"],
  auth_type: OAUTH_DYNAMIC_CLIENT,
  oauth_resource_url: "https://mcp.atlassian.com/v1/mcp"
}'

# OAuth2 client credentials:
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

Use `dry_run=true` to preview the DDL without executing it.

If the API integration does not exist when `dbt build` reaches a `cortex_mcp_server` model,
the materialization fails immediately with a clear error message that names the missing
integration and shows both bootstrap options.

---

## Defining an MCP server model

The model body is empty — all parameters are supplied via `config()`. Use
`cortex_mcp_api_integration_name(ref(...))` to wire in an integration created by the
materialization above (registers the DAG dependency); pass a plain string instead if the
integration was created out-of-band via the run-operation.

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

---

## Wiring an MCP server to an agent

Use the `cortex_mcp_server_name()` macro with `ref()` to wire the server into an agent model
body. This both registers the DAG dependency and derives the correct
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

---

## Configuration reference

### `cortex_mcp_server`

| Config            | Required | Type   | Description |
|-------------------|----------|--------|-------------|
| `display_name`    | Yes      | string | Human-readable label shown in Snowflake. |
| `url`             | Yes      | string | MCP server endpoint URL. |
| `api_integration` | Yes      | string | Name of the Snowflake API integration object — pass `dbt_cortex_agent.cortex_mcp_api_integration_name(ref('...'))` to wire a DAG dependency, or a plain string for an out-of-band integration. |

### `cortex_mcp_api_integration` materialization

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
| `if_not_exists`                | No (default **`true`**)     | bool         | Use `IF NOT EXISTS` instead of `OR REPLACE`. |
| `comment`                      | No                          | string       | Optional `COMMENT` clause. |

The integration's Snowflake object name is always the model's alias.

### `create_mcp_api_integration` run-operation

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

> **`if_not_exists` default differs by entry point.** The `cortex_mcp_api_integration`
> materialization defaults to `true`; the run-operation defaults to `false` (`CREATE OR REPLACE`)
> for backward compatibility with existing callers.

> **Privilege note.** Creating API integrations requires **ACCOUNTADMIN** or the
> **CREATE INTEGRATION** account-level privilege. This is a one-time admin operation; normal
> dbt runs do not need elevated privileges once the integration exists. Consider a separate
> `dbt build --select cortex_mcp_api_integration:*` step under an elevated role if your normal
> service account shouldn't hold that privilege day-to-day.
