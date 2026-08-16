#!/usr/bin/env bash

set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
cd "${repository_root}"

compose_file="initializer/compose.yaml"
vdb_file="initializer/descriptor/vdb/InitializerVDB.yaml"
module_info="initializer/module/bundle-script-info.yaml"

required_files=(
  "${compose_file}"
  initializer/README.md
  initializer/app-config.yaml
  initializer/descriptor/bundle-info.yaml
  "${vdb_file}"
  "${module_info}"
  initializer/module/schema.sql
  initializer/module/translator-config.yaml
  initializer/module/init/initialize_state.js
  initializer/module/scheduled/advance_state.js
  initializer/module/handler/SCHEDULER_STATE.js
  initializer/scripts/smoke-test.sh
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "${required_file}" ]]; then
    printf 'ERROR: required Initializer sample file is missing: %s\n' "${required_file}" >&2
    exit 1
  fi
done

legacy_paths=(
  initializer/gen-bundles.sh
  initializer/descriptor/vdb/ApplicationVDB.yaml
  initializer/descriptor/vdb/scripting
  initializer/descriptor/vdb/translator
  initializer/modules
)

for legacy_path in "${legacy_paths[@]}"; do
  if [[ -e "${legacy_path}" ]]; then
    printf 'ERROR: legacy Initializer path still exists: %s\n' "${legacy_path}" >&2
    exit 1
  fi
done

docker compose -f "${compose_file}" config --quiet
sh -n initializer/scripts/smoke-test.sh

mapfile -t images < <(docker compose -f "${compose_file}" config --images | sort -u)
expected_images=(
  docker.io/curlimages/curl:8.16.0
  docker.io/kubling/kubling-cli:26.2
  docker.io/kubling/kubling:26.4
)

for expected_image in "${expected_images[@]}"; do
  if ! printf '%s\n' "${images[@]}" | grep -Fqx "${expected_image}"; then
    printf 'ERROR: Initializer sample image is missing or changed: %s\n' "${expected_image}" >&2
    exit 1
  fi
done

for image in "${images[@]}"; do
  image_name="${image%@*}"
  image_last_component="${image_name##*/}"
  if [[ "${image}" == *:latest ]] ||
    { [[ "${image}" != *@sha256:* ]] && [[ "${image_last_component}" != *:* ]]; }; then
    printf 'ERROR: Initializer sample image is not pinned: %s\n' "${image}" >&2
    exit 1
  fi

  if ! printf '%s\n' "${expected_images[@]}" | grep -Fqx "${image}"; then
    printf 'ERROR: unexpected Initializer sample image: %s\n' "${image}" >&2
    exit 1
  fi
done

grep -Fq 'name: "InitializerVDB"' "${vdb_file}"
grep -Fq 'name: "initializer"' "${vdb_file}"
grep -Fq 'dataSourceType: "SCRIPT_DOCUMENT_JS"' "${vdb_file}"
grep -Fq 'zipFilePath: "{{ INITIALIZER_MODULE_BUNDLE }}"' "${vdb_file}"
grep -Fq 'handlersAutoDiscoveryPath: "handler"' "${module_info}"
grep -Fq 'scriptFilePath: "init/initialize_state.js"' "${module_info}"
grep -Fq 'scriptFilePath: "scheduled/advance_state.js"' "${module_info}"
grep -Fq 'cron: "0/2 * * * * *"' "${module_info}"
grep -Fq 'initResult.initialized();' initializer/module/init/initialize_state.js
grep -Fq 'global.put("scheduler_state"' initializer/module/scheduled/advance_state.js

if find initializer -type f -name '*.zip' -print -quit | grep -q .; then
  printf 'ERROR: generated Initializer bundles must not be stored in the sample directory.\n' >&2
  exit 1
fi

printf 'Initializer static checks passed.\n'
