#!/usr/bin/env bash

set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
cd "${repository_root}"

compose_file="rbac/compose.yaml"
vdb_file="rbac/descriptor/vdb/RbacVDB.yaml"
bundle_file="rbac/descriptor/bundle-info.yaml"

required_files=(
  "${compose_file}"
  rbac/README.md
  rbac/app-config.yaml
  "${bundle_file}"
  "${vdb_file}"
  rbac/descriptor/auth/authenticator.js
  rbac/scripts/smoke-test.sh
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "${required_file}" ]]; then
    printf 'ERROR: required RBAC file is missing: %s\n' "${required_file}" >&2
    exit 1
  fi
done

docker compose -f "${compose_file}" config --quiet
sh -n rbac/scripts/smoke-test.sh

mapfile -t images < <(
  docker compose -f "${compose_file}" --profile client --profile test config --images | sort -u
)
expected_images=(
  docker.io/curlimages/curl:latest
  docker.io/fullstorydev/grpcurl:latest
  docker.io/kubling/inmemory-provider:latest
  docker.io/kubling/kubling-cli:latest
  docker.io/kubling/kubling:latest
  docker.io/library/postgres:latest
)

for expected_image in "${expected_images[@]}"; do
  if ! printf '%s\n' "${images[@]}" | grep -Fqx "${expected_image}"; then
    printf 'ERROR: RBAC image is missing or changed: %s\n' "${expected_image}" >&2
    exit 1
  fi
done

for image in "${images[@]}"; do
  if ! printf '%s\n' "${expected_images[@]}" | grep -Fqx "${image}"; then
    printf 'ERROR: unexpected RBAC image: %s\n' "${image}" >&2
    exit 1
  fi
done

grep -Fq 'name: "RbacVDB"' "${vdb_file}"
grep -Fq 'name: "provider"' "${vdb_file}"
grep -Fq 'dataSourceType: "PROVIDER_GRPC"' "${vdb_file}"
grep -Fq 'ROLE_TASK_READER' "${vdb_file}"
grep -Fq 'ROLE_TASK_EDITOR' "${vdb_file}"
if [[ "$(grep -Fc -- '- "provider"' "${vdb_file}")" -ne 2 ]]; then
  printf 'ERROR: both RBAC roles must be scoped to the provider schema.\n' >&2
  exit 1
fi
grep -Fq 'allowUpdate: false' "${vdb_file}"
grep -Fq 'allowUpdate: true' "${vdb_file}"
grep -Fq 'scriptFilePath: "auth/authenticator.js"' "${bundle_file}"

if ! awk '
  /pgProtocol:/ { in_pg = 1; next }
  in_pg && /enable:/ { exit($2 == "true" ? 0 : 1) }
  END { if (!in_pg) exit 1 }
' rbac/app-config.yaml; then
  printf 'ERROR: RBAC must enable Kubling PostgreSQL client transport.\n' >&2
  exit 1
fi

if grep -Fq 'endpointScripts:' "${bundle_file}"; then
  printf 'ERROR: RBAC must exercise authenticated PostgreSQL client sessions directly.\n' >&2
  exit 1
fi

if [[ "$(grep -Fc 'PGCONNECT_TIMEOUT: "8"' "${compose_file}")" -ne 2 ]]; then
  printf 'ERROR: both RBAC SQL clients must fail fast when the client transport is unavailable.\n' >&2
  exit 1
fi

if grep -Eiq '^[[:space:]]*ddl(FilePaths)?[[:space:]]*:' "${vdb_file}"; then
  printf 'ERROR: RBAC VDB must import its physical schema from GetSchema.\n' >&2
  exit 1
fi

if grep -Rq 'dataSourceType: "SCRIPT_JS"' rbac/descriptor; then
  printf 'ERROR: RBAC must use the official gRPC provider, not the legacy JavaScript data source.\n' >&2
  exit 1
fi

printf 'RBAC static checks passed.\n'
