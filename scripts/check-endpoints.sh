#!/usr/bin/env bash

set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
cd "${repository_root}"

compose_file="endpoints/compose.yaml"
vdb_file="endpoints/descriptor/vdb/EndpointsVDB.yaml"
bundle_file="endpoints/descriptor/bundle-info.yaml"

required_files=(
  "${compose_file}"
  endpoints/README.md
  endpoints/app-config.yaml
  "${bundle_file}"
  "${vdb_file}"
  endpoints/descriptor/endpoint/queries/get_task.yaml
  endpoints/descriptor/endpoint/actions/create_task.yaml
  endpoints/scripts/smoke-test.sh
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "${required_file}" ]]; then
    printf 'ERROR: required Endpoints file is missing: %s\n' "${required_file}" >&2
    exit 1
  fi
done

docker compose -f "${compose_file}" config --quiet
sh -n endpoints/scripts/smoke-test.sh
grep -Fq '"8282:8282"' "${compose_file}"

mapfile -t images < <(docker compose -f "${compose_file}" config --images | sort -u)
expected_images=(
  docker.io/curlimages/curl:latest
  docker.io/fullstorydev/grpcurl:latest
  docker.io/kubling/inmemory-provider:latest
  docker.io/kubling/kubling-cli:latest
  docker.io/kubling/kubling:latest
)

for expected_image in "${expected_images[@]}"; do
  if ! printf '%s\n' "${images[@]}" | grep -Fqx "${expected_image}"; then
    printf 'ERROR: Endpoints image is missing or changed: %s\n' "${expected_image}" >&2
    exit 1
  fi
done

for image in "${images[@]}"; do
  if ! printf '%s\n' "${expected_images[@]}" | grep -Fqx "${image}"; then
    printf 'ERROR: unexpected Endpoints image: %s\n' "${image}" >&2
    exit 1
  fi
done

grep -Fq 'name: "EndpointsVDB"' "${vdb_file}"
grep -Fq 'name: "provider"' "${vdb_file}"
grep -Fq 'dataSourceType: "PROVIDER_GRPC"' "${vdb_file}"
grep -Fq 'queryEndpointsDirectory: "endpoint/queries"' "${bundle_file}"
grep -Fq 'actionsDirectory: "endpoint/actions"' "${bundle_file}"

if grep -Eiq '^[[:space:]]*ddl(FilePaths)?[[:space:]]*:' "${vdb_file}"; then
  printf 'ERROR: Endpoints VDB must import its physical schema from GetSchema.\n' >&2
  exit 1
fi

if grep -Rq 'dataSourceType: "KUBERNETES"' endpoints/descriptor; then
  printf 'ERROR: Endpoints must not use the retired built-in Kubernetes adapter.\n' >&2
  exit 1
fi

printf 'Endpoints static checks passed.\n'
