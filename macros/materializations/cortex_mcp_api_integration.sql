{#-
--  cortex_mcp_api_integration materialization
--
--  Creates (or, if missing, creates — see if_not_exists note below) a
--  Snowflake API INTEGRATION for an external MCP server from a dbt model.
--  The model body is empty (config-only); all parameters are supplied via
--  config(). This is the account-level object a `cortex_mcp_server` model's
--  `api_integration` config points at.
--
--  Required config:
--      allowed_prefixes  list[string]  Base URL(s) of the MCP server, matched as a prefix.
--
--  Optional config: auth_type, oauth_resource_url, oauth_client_id,
--  oauth_client_secret, oauth_token_endpoint, oauth_authorization_endpoint,
--  oauth_client_auth_method, oauth_discovery_url,
--  oauth_refresh_token_validity, enabled, if_not_exists, comment.
--
--  Example:
--
--      {{ config(
--          materialized      = 'cortex_mcp_api_integration',
--          allowed_prefixes  = ['https://mcp.atlassian.com'],
--          auth_type         = 'OAUTH_DYNAMIC_CLIENT',
--          oauth_resource_url = 'https://mcp.atlassian.com/v1/mcp'
--      ) }}
--
--  To wire this integration into a cortex_mcp_server model, use:
--
--      {{ config(
--          materialized    = 'cortex_mcp_server',
--          display_name    = 'Atlassian (Jira & Confluence)',
--          url             = 'https://mcp.atlassian.com/v1/mcp',
--          api_integration = dbt_cortex_agent.cortex_mcp_api_integration_name(ref('jira_mcp_api_integration'))
--      ) }}
--
--  Requires ACCOUNTADMIN or CREATE INTEGRATION account-level privilege on the
--  executing role — the same requirement as the `create_mcp_api_integration`
--  run-operation this materialization supersedes for `dbt build`-tracked use.
--
--  Note on `if_not_exists`: this materialization defaults to `if_not_exists=true`
--  (not `CREATE OR REPLACE`) so that a routine `dbt build` sweep (a broad
--  selector, `state:modified.body`, `--full-refresh`) never silently rotates a
--  live OAuth-authenticated integration as a side effect. Pass
--  `if_not_exists=false` explicitly to opt into replace-in-place semantics.
--
--  See macros/relations/cortex_mcp_api_integration/create.sql for the DDL
--  construction and the README for usage and config options.
-#}

{% materialization cortex_mcp_api_integration, adapter='snowflake' -%}

    {% set original_query_tag = set_query_tag() %}

    {% do dbt_cortex_agent.snowflake__create_or_replace_cortex_mcp_api_integration() %}

    {#-
    --  Snowflake API INTEGRATION objects are account-level (no database/schema),
    --  so they don't fit dbt's Relation model any more naturally than
    --  cortex_mcp_server's own EXTERNAL MCP SERVER does. We incorporate the
    --  node as a `view` purely so that dbt can track it in the graph and
    --  downstream `ref()`s resolve. dbt never issues view DDL for this node.
    -#}
    {% set target_relation = this.incorporate(type='view') %}

    {% do unset_query_tag(original_query_tag) %}

    {% do return({'relations': [target_relation]}) %}

{%- endmaterialization %}


{#-
--  Default (non-Snowflake) stub materialization.
--
--  Renders the CREATE API INTEGRATION DDL without executing it, so
--  `dbt compile` works on any adapter (e.g. DuckDB) and the compiled SQL is
--  inspectable in target/compiled/.
-#}
{% materialization cortex_mcp_api_integration, default -%}

    {%- set identifier = model['alias'] -%}
    {%- set target_relation = api.Relation.create(
        identifier=identifier, schema=schema, database=database,
        type='view') -%}

    {% call statement('main') -%}
        {{ dbt_cortex_agent.snowflake__get_create_cortex_mcp_api_integration_sql(target_relation) }}
    {%- endcall %}

    {% do return({'relations': [target_relation]}) %}

{%- endmaterialization %}
