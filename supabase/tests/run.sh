#!/usr/bin/env bash
# Disposable PostgreSQL test only. Do not run fixture.sql against real Supabase.
set -euo pipefail
schema_test_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
schema_test_name="ogretmen-sql-test-$$"
docker_local() {
  env -u DOCKER_HOST -u DOCKER_CONTEXT -u DOCKER_TLS -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH \
    docker --host=unix:///var/run/docker.sock "$@"
}
docker_local run -d --name "$schema_test_name" --network none \
  -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17-alpine -c wal_level=logical >/dev/null
trap 'docker_local rm -f "$schema_test_name" >/dev/null' EXIT
schema_test_ready=false
for schema_test_attempt in {1..30}; do
  if docker_local exec "$schema_test_name" pg_isready -U postgres >/dev/null 2>&1; then
    schema_test_ready=true
    break
  fi
  sleep 1
done
if [[ "$schema_test_ready" != true ]]; then
  echo 'PostgreSQL did not become ready' >&2
  exit 1
fi
docker_local exec "$schema_test_name" mkdir -p /work
docker_local cp "$schema_test_dir" "$schema_test_name:/work/supabase"
for schema_test_file in tests/fixture.sql schema.sql applications.sql applications.sql tests/policies.sql; do
  docker_local exec "$schema_test_name" psql -X -q -U postgres -v ON_ERROR_STOP=1 \
    -f "/work/supabase/$schema_test_file"
done
