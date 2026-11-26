#!/usr/bin/env bash
# Runs once, on the first start of an empty data directory (docker-entrypoint-initdb.d).
# Creates a least-privilege login for postgres_exporter: pg_monitor can read the
# statistics views and settings, but no table data.
set -euo pipefail

: "${PG_EXPORTER_PASSWORD:?PG_EXPORTER_PASSWORD is not set}"

psql -v ON_ERROR_STOP=1 -qAt \
    --username "${POSTGRES_USER:-postgres}" --dbname "${POSTGRES_DB:-postgres}" \
    -v pw="$PG_EXPORTER_PASSWORD" <<'SQL'
CREATE ROLE postgres_exporter LOGIN PASSWORD :'pw' CONNECTION LIMIT 3;
GRANT pg_monitor TO postgres_exporter;
SQL

echo "monitoring role postgres_exporter created"
