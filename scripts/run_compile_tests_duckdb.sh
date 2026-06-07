#!/usr/bin/env bash
# Compile all agent models against DuckDB to validate Jinja and DDL output
# without needing Snowflake credentials. Compiled SQL lands in
# integration_tests/target/compiled/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTEGRATION_TESTS_DIR="$(cd "$SCRIPT_DIR/../integration_tests" && pwd)"

export DBT_PROFILES_DIR="$INTEGRATION_TESTS_DIR"

cd "$INTEGRATION_TESTS_DIR"

echo "==> Installing dbt dependencies"
dbt deps --target duckdb

echo "==> Compiling agent models"
dbt compile --select "agent_*" --target duckdb

echo "==> Compiled SQL written to target/compiled/"
find target/compiled -name "agent_*.sql" | sort | while read -r f; do
    echo ""
    echo "--- $f ---"
    cat "$f"
done
