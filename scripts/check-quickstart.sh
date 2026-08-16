#!/usr/bin/env bash

set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
cd "${repository_root}"

compose_file="quickstart/compose.yaml"
vdb_file="quickstart/descriptor/vdb/ProviderQuickstartVDB.yaml"

required_files=(
  "${compose_file}"
  quickstart/README.md
  quickstart/app-config.yaml
  quickstart/descriptor/bundle-info.yaml
  "${vdb_file}"
  quickstart/scripts/smoke-test.sh
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "${required_file}" ]]; then
    printf 'ERROR: required Quickstart file is missing: %s\n' "${required_file}" >&2
    exit 1
  fi
done

docker compose -f "${compose_file}" config --quiet
sh -n quickstart/scripts/smoke-test.sh

mapfile -t images < <(docker compose -f "${compose_file}" config --images | sort -u)
expected_images=(
  docker.io/curlimages/curl:8.16.0
  docker.io/fullstorydev/grpcurl:v1.9.3
  docker.io/kubling/kubling-cli:26.2
  docker.io/kubling/kubling:26.4
  docker.io/kubling/inmemory-provider:v0.0.1
)

for expected_image in "${expected_images[@]}"; do
  if ! printf '%s\n' "${images[@]}" | grep -Fqx "${expected_image}"; then
    printf 'ERROR: Quickstart image is missing or changed: %s\n' "${expected_image}" >&2
    exit 1
  fi
done

for image in "${images[@]}"; do
  image_name="${image%@*}"
  image_last_component="${image_name##*/}"
  if [[ "${image}" == *:latest ]] ||
    { [[ "${image}" != *@sha256:* ]] && [[ "${image_last_component}" != *:* ]]; }; then
    printf 'ERROR: Quickstart image is not pinned: %s\n' "${image}" >&2
    exit 1
  fi

  if ! printf '%s\n' "${expected_images[@]}" | grep -Fqx "${image}"; then
    printf 'ERROR: unexpected Quickstart image: %s\n' "${image}" >&2
    exit 1
  fi
done

grep -Fq 'name: "ProviderQuickstartVDB"' "${vdb_file}"
grep -Fq 'name: "provider"' "${vdb_file}"
grep -Fq 'dataSourceType: "PROVIDER_GRPC"' "${vdb_file}"

if grep -Eiq '^[[:space:]]*ddl(FilePaths)?[[:space:]]*:' "${vdb_file}"; then
  printf 'ERROR: Quickstart VDB must import its physical schema from GetSchema.\n' >&2
  exit 1
fi

printf 'Quickstart static checks passed.\n'
