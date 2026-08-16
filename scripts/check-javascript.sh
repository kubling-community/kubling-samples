#!/usr/bin/env bash

set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
cd "${repository_root}"

compose_file="javascript/compose.yaml"
vdb_file="javascript/descriptor/vdb/JavaScriptVDB.yaml"
module_info="javascript/module/bundle-script-info.yaml"

required_files=(
  "${compose_file}"
  javascript/README.md
  javascript/app-config.yaml
  javascript/descriptor/bundle-info.yaml
  "${vdb_file}"
  "${module_info}"
  javascript/module/schema.sql
  javascript/module/translator-config.yaml
  javascript/module/data/tasks.js
  javascript/module/handler/TASK.js
  javascript/scripts/smoke-test.sh
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "${required_file}" ]]; then
    printf 'ERROR: required JavaScript sample file is missing: %s\n' "${required_file}" >&2
    exit 1
  fi
done

if [[ -d minimal ]] && find minimal -type f -print -quit | grep -q .; then
  printf 'ERROR: legacy minimal sample files must not coexist with javascript/.\n' >&2
  exit 1
fi

docker compose -f "${compose_file}" config --quiet
sh -n javascript/scripts/smoke-test.sh

mapfile -t images < <(docker compose -f "${compose_file}" config --images | sort -u)
expected_images=(
  docker.io/curlimages/curl:8.16.0
  docker.io/kubling/kubling-cli:26.2
  docker.io/kubling/kubling:26.4
)

for expected_image in "${expected_images[@]}"; do
  if ! printf '%s\n' "${images[@]}" | grep -Fqx "${expected_image}"; then
    printf 'ERROR: JavaScript sample image is missing or changed: %s\n' "${expected_image}" >&2
    exit 1
  fi
done

for image in "${images[@]}"; do
  image_name="${image%@*}"
  image_last_component="${image_name##*/}"
  if [[ "${image}" == *:latest ]] ||
    { [[ "${image}" != *@sha256:* ]] && [[ "${image_last_component}" != *:* ]]; }; then
    printf 'ERROR: JavaScript sample image is not pinned: %s\n' "${image}" >&2
    exit 1
  fi

  if ! printf '%s\n' "${expected_images[@]}" | grep -Fqx "${image}"; then
    printf 'ERROR: unexpected JavaScript sample image: %s\n' "${image}" >&2
    exit 1
  fi
done

grep -Fq 'name: "JavaScriptVDB"' "${vdb_file}"
grep -Fq 'name: "javascript"' "${vdb_file}"
grep -Fq 'dataSourceType: "SCRIPT_DOCUMENT_JS"' "${vdb_file}"
grep -Fq 'zipFilePath: "{{ JAVASCRIPT_MODULE_BUNDLE }}"' "${vdb_file}"
grep -Fq '"module:/schema.sql"' "${vdb_file}"
grep -Fq 'handlersAutoDiscoveryPath: "handler"' "${module_info}"
grep -Fq 'innerDDLFilePath: "schema.sql"' "${module_info}"
grep -Fq 'innerTranslatorConfigFilePath: "translator-config.yaml"' "${module_info}"
grep -Fq 'updatable true' javascript/module/schema.sql
grep -Fq 'insert(insertOperation, affectedRows)' javascript/module/handler/TASK.js

if find javascript -type f -name '*.zip' -print -quit | grep -q .; then
  printf 'ERROR: generated JavaScript bundles must not be stored in the sample directory.\n' >&2
  exit 1
fi

printf 'JavaScript static checks passed.\n'
