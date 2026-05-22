#!/usr/bin/env bash
# Load .env for dbt / BigQuery (bash / Git Bash / WSL).
# Usage:  source scripts/load_env.sh

set -a
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ ! -f "$ROOT/.env" ]]; then
  echo "error: $ROOT/.env not found. Copy .env.example to .env" >&2
  return 1 2>/dev/null || exit 1
fi
# shellcheck source=/dev/null
source "$ROOT/.env"
set +a
echo "Loaded .env from $ROOT/.env"
echo "  BQ_PROJECT_ID=$BQ_PROJECT_ID"
echo "  BQ_DATASET_RAW=$BQ_DATASET_RAW"
echo "  BQ_DATASET_STG=$BQ_DATASET_STG"
echo "  BQ_DATASET_INT=$BQ_DATASET_INT"
echo "  BQ_DATASET_MART=$BQ_DATASET_MART"
echo "  DBT_TARGET=$DBT_TARGET"
