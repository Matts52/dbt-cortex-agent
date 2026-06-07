#!/usr/bin/env bash
# Run the dbt_cortex_agent integration tests against a live Snowflake account.
#
# Required env vars (set before running):
#   SNOWFLAKE_TEST_ACCOUNT
#   SNOWFLAKE_TEST_USER
#   SNOWFLAKE_TEST_PASSWORD   (or use SNOWFLAKE_TEST_AUTHENTICATOR=externalbrowser)
#   SNOWFLAKE_TEST_ROLE
#   SNOWFLAKE_TEST_DATABASE
#   SNOWFLAKE_TEST_WAREHOUSE
#   SNOWFLAKE_TEST_SCHEMA
#
# Optional:
#   SNOWFLAKE_TEST_AUTHENTICATOR  (default: snowflake)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INTEGRATION_TESTS_DIR="$REPO_ROOT/integration_tests"

: "${SNOWFLAKE_TEST_ACCOUNT:?SNOWFLAKE_TEST_ACCOUNT must be set}"
: "${SNOWFLAKE_TEST_USER:?SNOWFLAKE_TEST_USER must be set}"
: "${SNOWFLAKE_TEST_ROLE:?SNOWFLAKE_TEST_ROLE must be set}"
: "${SNOWFLAKE_TEST_DATABASE:?SNOWFLAKE_TEST_DATABASE must be set}"
: "${SNOWFLAKE_TEST_WAREHOUSE:?SNOWFLAKE_TEST_WAREHOUSE must be set}"
: "${SNOWFLAKE_TEST_SCHEMA:?SNOWFLAKE_TEST_SCHEMA must be set}"

export DBT_PROFILES_DIR="$INTEGRATION_TESTS_DIR"

cd "$INTEGRATION_TESTS_DIR"

echo "==> Installing dbt dependencies"
dbt deps --target snowflake

echo "==> Running dbt build"
dbt build --target snowflake

echo "==> Asserting agents exist"
dbt run-operation assert_agents_exist --target snowflake

echo "==> All integration tests passed."
