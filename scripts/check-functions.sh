#!/usr/bin/env bash

set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
cd "${repository_root}"

compose_file="functions/compose.yaml"
descriptor_info="functions/descriptor/bundle-info.yaml"
vdb_file="functions/descriptor/vdb/FunctionsVDB.yaml"
sql_module_info="functions/sql-functions/bundle-sql-function-info.yaml"
template_module_info="functions/template-functions/bundle-function-info.yaml"

required_files=(
  "${compose_file}"
  functions/README.md
  functions/app-config.yaml
  "${descriptor_info}"
  "${vdb_file}"
  functions/descriptor/endpoint/queries/get_task_label.yaml
  "${sql_module_info}"
  functions/sql-functions/fn/task_label.js
  "${template_module_info}"
  functions/template-functions/fn/validate_task_id.js
  functions/scripts/smoke-test.sh
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "${required_file}" ]]; then
    printf 'ERROR: required Functions sample file is missing: %s\n' "${required_file}" >&2
    exit 1
  fi
done

docker compose -f "${compose_file}" config --quiet
sh -n functions/scripts/smoke-test.sh

mapfile -t images < <(docker compose -f "${compose_file}" config --images | sort -u)
expected_images=(
  docker.io/curlimages/curl:latest
  docker.io/fullstorydev/grpcurl:latest
  docker.io/kubling/kubling-cli:latest
  docker.io/kubling/kubling:latest
  docker.io/kubling/inmemory-provider:latest
)

for expected_image in "${expected_images[@]}"; do
  if ! printf '%s\n' "${images[@]}" | grep -Fqx "${expected_image}"; then
    printf 'ERROR: Functions sample image is missing or changed: %s\n' "${expected_image}" >&2
    exit 1
  fi
done

for image in "${images[@]}"; do
  if ! printf '%s\n' "${expected_images[@]}" | grep -Fqx "${image}"; then
    printf 'ERROR: unexpected Functions sample image: %s\n' "${image}" >&2
    exit 1
  fi
done

grep -Fq 'name: "FunctionsVDB"' "${vdb_file}"
grep -Fq 'name: "provider"' "${vdb_file}"
grep -Fq 'dataSourceType: "PROVIDER_GRPC"' "${vdb_file}"
grep -Fq 'sqlFunctionModules:' "${descriptor_info}"
grep -Fq 'actionTemplatesFunctionModules:' "${descriptor_info}"
grep -Fq 'name: "task_label"' "${sql_module_info}"
grep -Fq 'isDeterministic: true' "${sql_module_info}"
grep -Fq 'name: "validate_task_id"' "${template_module_info}"
grep -Fq 'parallelContexts: 2' "${template_module_info}"
grep -Fq 'maxWaitMilliseconds: 10000' "${template_module_info}"
grep -Fq 'templates__validate_task_id' functions/descriptor/endpoint/queries/get_task_label.yaml
grep -Fq 'task_label(id, title)' functions/descriptor/endpoint/queries/get_task_label.yaml

if find functions -type f -name '*.zip' -print -quit | grep -q .; then
  printf 'ERROR: generated Functions bundles must not be stored in the sample directory.\n' >&2
  exit 1
fi

printf 'Functions static checks passed.\n'
