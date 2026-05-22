#!/usr/bin/env bash
# Run dbt with .env loaded and --target from DBT_TARGET.
# Usage:  ./scripts/dbt.sh run

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/load_env.sh"
TARGET="${DBT_TARGET:-dev}"
echo "dbt $* --target $TARGET"
exec dbt --target "$TARGET" "$@"
