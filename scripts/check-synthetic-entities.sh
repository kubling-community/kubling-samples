#!/usr/bin/env bash

set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
cd "${repository_root}"

compose_file="synthetic-entities/compose.yaml"
vdb_file="synthetic-entities/descriptor/vdb/SyntheticEntitiesVDB.yaml"
module_info="synthetic-entities/module/bundle-script-info.yaml"
schema_file="synthetic-entities/module/schema.sql"

required_files=(
  "${compose_file}"
  synthetic-entities/README.md
  synthetic-entities/app-config.yaml
  synthetic-entities/descriptor/bundle-info.yaml
  "${vdb_file}"
  "${module_info}"
  "${schema_file}"
  synthetic-entities/module/translator-config.yaml
  synthetic-entities/module/data/projects.js
  synthetic-entities/module/handler/PROJECT.js
  synthetic-entities/scripts/smoke-test.sh
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "${required_file}" ]]; then
    printf 'ERROR: required Synthetic Entities sample file is missing: %s\n' "${required_file}" >&2
    exit 1
  fi
done

if [[ -e documents ]]; then
  printf 'ERROR: legacy documents sample must not coexist with synthetic-entities/.\n' >&2
  exit 1
fi

docker compose -f "${compose_file}" config --quiet
sh -n synthetic-entities/scripts/smoke-test.sh

mapfile -t images < <(docker compose -f "${compose_file}" config --images | sort -u)
expected_images=(
  docker.io/curlimages/curl:latest
  docker.io/kubling/kubling-cli:latest
  docker.io/kubling/kubling:latest
)

for expected_image in "${expected_images[@]}"; do
  if ! printf '%s\n' "${images[@]}" | grep -Fqx "${expected_image}"; then
    printf 'ERROR: Synthetic Entities sample image is missing or changed: %s\n' "${expected_image}" >&2
    exit 1
  fi
done

for image in "${images[@]}"; do
  if ! printf '%s\n' "${expected_images[@]}" | grep -Fqx "${image}"; then
    printf 'ERROR: unexpected Synthetic Entities sample image: %s\n' "${image}" >&2
    exit 1
  fi
done

grep -Fq 'name: "SyntheticEntitiesVDB"' "${vdb_file}"
grep -Fq 'name: "synthetic"' "${vdb_file}"
grep -Fq 'dataSourceType: "SCRIPT_DOCUMENT_JS"' "${vdb_file}"
grep -Fq 'zipFilePath: "{{ SYNTHETIC_ENTITIES_MODULE_BUNDLE }}"' "${vdb_file}"
grep -Fq 'handlersAutoDiscoveryPath: "handler"' "${module_info}"
grep -Fq 'CREATE FOREIGN TABLE PROJECT_MEMBER' "${schema_file}"
grep -Fq "identifier string OPTIONS(val_pk 'project_id')" "${schema_file}"
grep -Fq 'UNIQUE(project_id)' "${schema_file}"
grep -Fq "synthetic_parent 'synthetic.PROJECT'" "${schema_file}"
grep -Fq "synthetic_path 'members'" "${schema_file}"
grep -Fq "synthetic_type 'parent'" "${schema_file}"
grep -Fq 'update(updateOperation, affectedRows)' synthetic-entities/module/handler/PROJECT.js

if find synthetic-entities -type f -name '*.zip' -print -quit | grep -q .; then
  printf 'ERROR: generated Synthetic Entities bundles must not be stored in the sample directory.\n' >&2
  exit 1
fi

printf 'Synthetic Entities static checks passed.\n'
