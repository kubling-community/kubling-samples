#!/usr/bin/env bash

set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
cd "${repository_root}"

printf 'Validating Performance Comparison static contract (no containers will be started).\n'

required_files=(
  performance-comparison/README.md
  performance-comparison/app-config.yaml
  performance-comparison/benchmark.py
  performance-comparison/requirements.txt
  performance-comparison/run-comparison.sh
  performance-comparison/workloads.json
  performance-comparison/descriptor/bundle-info.yaml
  performance-comparison/descriptor/vdb/PerformanceComparisonVDB.yaml
  performance-comparison/descriptor/vdb/schema.ddl
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "${required_file}" ]]; then
    printf 'ERROR: required Performance Comparison file is missing: %s\n' "${required_file}" >&2
    exit 1
  fi
done

bash -n performance-comparison/run-comparison.sh
python3 -c 'compile(open("performance-comparison/benchmark.py", encoding="utf-8").read(), "performance-comparison/benchmark.py", "exec")'
python3 performance-comparison/benchmark.py validate \
  --workloads performance-comparison/workloads.json \
  --group all \
  --scale 1
jq -e '.format == "kubling-performance-workloads" and .formatVersion == 1' \
  performance-comparison/workloads.json >/dev/null

grep -Fq 'docker.io/kubling/kubling-cli:latest' performance-comparison/run-comparison.sh
grep -Fxq 'kubling-sqlalchemy==26.6.0' performance-comparison/requirements.txt
grep -Fq -- '--grpc-target' performance-comparison/benchmark.py
grep -Fq 'PERFORMANCE_COMPARE_CLIENT_LIB_DIR' performance-comparison/run-comparison.sh
grep -Fq 'queryTransport: "grpc"' performance-comparison/run-comparison.sh
grep -Fq 'clientRuntime: $clientRuntime' performance-comparison/run-comparison.sh
grep -Fq '"kubling-grpc", "grpcio", "protobuf", "SQLAlchemy"' \
  performance-comparison/run-comparison.sh
grep -Fq 'performanceTracer:' performance-comparison/app-config.yaml
grep -Fq 'enabled: true' performance-comparison/app-config.yaml
grep -Fq 'dataSourceType: "PORTABLE_LOCAL"' \
  performance-comparison/descriptor/vdb/PerformanceComparisonVDB.yaml
grep -Fq '"id": "sql"' performance-comparison/workloads.json
grep -Fq '"id": "portable"' performance-comparison/workloads.json

if grep -Fq '/api/v1/admin/query/' performance-comparison/benchmark.py; then
  printf 'ERROR: timed SQL must use the gRPC client, not the HTTP query endpoint.\n' >&2
  exit 1
fi

if [[ -d performance-comparison/descriptor/auth ]]; then
  printf 'ERROR: Performance Comparison must not require an authentication fixture.\n' >&2
  exit 1
fi

if find performance-comparison -type f \( -name '*.zip' -o -name '*.db' -o -name '*.log' \) \
    -not -path 'performance-comparison/target/*' -print -quit | grep -q .; then
  printf 'ERROR: generated Performance Comparison artifacts must not be stored in the sample.\n' >&2
  exit 1
fi

printf 'Performance Comparison static checks passed.\n'
