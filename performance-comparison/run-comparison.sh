#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${BASE_DIR}/.." && pwd)"
WORKLOADS_FILE="${BASE_DIR}/workloads.json"
APP_CONFIG_FILE="${BASE_DIR}/app-config.yaml"
DESCRIPTOR_DIR="${BASE_DIR}/descriptor"
RESULTS_ROOT="${PERFORMANCE_COMPARE_RESULTS_DIR:-${BASE_DIR}/target}"
CLIENT_LIB_DIR="${PERFORMANCE_COMPARE_CLIENT_LIB_DIR:-${BASE_DIR}/target/client-libs}"
CLI_IMAGE="${KUBLING_CLI_IMAGE:-docker.io/kubling/kubling-cli:latest}"

baseline_reference=""
candidate_reference=""
group="all"
rounds="4"
scale="1"
cpu_limit="2"
memory_limit="2g"
host_label=""
pull_images="true"

usage() {
  cat <<'USAGE'
Usage:
  ./run-comparison.sh --baseline IMAGE --candidate IMAGE [options]

Required:
  --baseline IMAGE       Baseline Kubling image reference
  --candidate IMAGE      Candidate Kubling image reference

Options:
  --group GROUP          Workload group or "all" (default: all)
  --rounds COUNT         Number of alternating A/B rounds (default: 4)
  --scale FACTOR         Scale warmup and measured iterations (default: 1)
  --cpus COUNT           Docker CPU limit for each runtime (default: 2)
  --memory LIMIT         Docker memory limit for each runtime (default: 2g)
  --host-label LABEL     Optional label such as "pi-5" or "mac-m3"
  --no-pull              Use images already loaded in Docker
  --help                 Show this help

Results are written below performance-comparison/target by default.
USAGE
}

die() {
  echo "$*" >&2
  exit 1
}

require_commands() {
  local required_command
  for required_command in "$@"; do
    command -v "${required_command}" >/dev/null 2>&1 \
      || die "Required command not found: ${required_command}"
  done
}

now_ns() {
  python3 -c 'import time; print(time.time_ns())'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --baseline) [[ $# -ge 2 ]] || die "--baseline requires an image reference"; baseline_reference="$2"; shift 2 ;;
    --candidate) [[ $# -ge 2 ]] || die "--candidate requires an image reference"; candidate_reference="$2"; shift 2 ;;
    --group) [[ $# -ge 2 ]] || die "--group requires a value"; group="$2"; shift 2 ;;
    --rounds) [[ $# -ge 2 ]] || die "--rounds requires a value"; rounds="$2"; shift 2 ;;
    --scale) [[ $# -ge 2 ]] || die "--scale requires a value"; scale="$2"; shift 2 ;;
    --cpus) [[ $# -ge 2 ]] || die "--cpus requires a value"; cpu_limit="$2"; shift 2 ;;
    --memory) [[ $# -ge 2 ]] || die "--memory requires a value"; memory_limit="$2"; shift 2 ;;
    --host-label) [[ $# -ge 2 ]] || die "--host-label requires a value"; host_label="$2"; shift 2 ;;
    --no-pull) pull_images="false"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; die "Unknown argument: $1" ;;
  esac
done

[[ -n "${baseline_reference}" ]] || { usage >&2; die "--baseline is required"; }
[[ -n "${candidate_reference}" ]] || { usage >&2; die "--candidate is required"; }
[[ "${rounds}" =~ ^[1-9][0-9]*$ ]] || die "--rounds must be a positive integer"

require_commands awk curl date docker git id jq python3 sed uname
if [[ -d "${CLIENT_LIB_DIR}" ]]; then
  export PYTHONPATH="${CLIENT_LIB_DIR}${PYTHONPATH:+:${PYTHONPATH}}"
fi
python3 "${BASE_DIR}/benchmark.py" validate \
  --workloads "${WORKLOADS_FILE}" \
  --group "${group}" \
  --scale "${scale}"
python3 -c 'from kubling_sqlalchemy import dbapi' >/dev/null 2>&1 \
  || die "Install the Kubling gRPC client with: python3 -m pip install --target performance-comparison/target/client-libs -r performance-comparison/requirements.txt"
grpc_client_version="$(python3 -c 'from importlib.metadata import version; print(version("kubling-sqlalchemy"))')"
client_runtime_json="$(python3 -c 'import json, platform; from importlib.metadata import version; print(json.dumps({"python": {"implementation": platform.python_implementation(), "version": platform.python_version()}, "distributions": {name: version(name) for name in ("kubling-sqlalchemy", "kubling-grpc", "grpcio", "protobuf", "SQLAlchemy")}}))')"

run_timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
run_token="${run_timestamp}-$$"
run_dir="${RESULTS_ROOT}/${run_token}"
mkdir -p "${run_dir}/images" "${run_dir}/samples" "${run_dir}/bundle"

current_container=""
current_volume=""
cleanup() {
  local container_id volume_name
  if [[ -n "${current_container}" ]]; then
    docker rm -f "${current_container}" >/dev/null 2>&1 || true
    current_container=""
  fi
  while IFS= read -r container_id; do
    [[ -n "${container_id}" ]] || continue
    docker rm -f "${container_id}" >/dev/null 2>&1 || true
  done < <(docker ps --all --quiet --filter "label=com.kubling.performance-compare.run=${run_token}")
  if [[ -n "${current_volume}" ]]; then
    docker volume rm -f "${current_volume}" >/dev/null 2>&1 || true
    current_volume=""
  fi
  while IFS= read -r volume_name; do
    [[ -n "${volume_name}" ]] || continue
    docker volume rm -f "${volume_name}" >/dev/null 2>&1 || true
  done < <(docker volume ls --quiet --filter "label=com.kubling.performance-compare.run=${run_token}")
}
trap cleanup EXIT INT TERM

normalize_architecture() {
  case "$1" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    armv7l|arm) echo arm ;;
    *) echo "$1" ;;
  esac
}

read_cpu_model() {
  local value=""
  case "$(uname -s)" in
    Linux)
      value="$(awk -F: '/^(model name|Model)[[:space:]]*:/ {
        value = $2
        sub(/^[[:space:]]*/, "", value)
        print value
        exit
      }' /proc/cpuinfo 2>/dev/null)"
      ;;
    Darwin)
      value="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
      [[ -n "${value}" ]] || value="$(sysctl -n hw.model 2>/dev/null || true)"
      ;;
  esac
  printf '%s\n' "${value}"
}

server_architecture="$(normalize_architecture "$(docker version --format '{{.Server.Arch}}')")"

resolve_image() {
  local variant="$1" reference="$2" output_file="$3"
  local image_id image_os image_architecture repo_digests

  if [[ "${pull_images}" == "true" ]]; then
    docker pull "${reference}" >"${run_dir}/images/${variant}-pull.log" 2>&1 \
      || { tail -n 120 "${run_dir}/images/${variant}-pull.log" >&2; die "Could not pull ${reference}"; }
  else
    docker image inspect "${reference}" >/dev/null 2>&1 \
      || die "Image is not loaded locally: ${reference}"
  fi

  image_id="$(docker image inspect --format '{{.Id}}' "${reference}")"
  image_os="$(docker image inspect --format '{{.Os}}' "${reference}")"
  image_architecture="$(normalize_architecture "$(docker image inspect --format '{{.Architecture}}' "${reference}")")"
  repo_digests="$(docker image inspect --format '{{json .RepoDigests}}' "${reference}")"
  [[ "${repo_digests}" != "<no value>" && "${repo_digests}" != "null" ]] || repo_digests='[]'

  [[ "${image_os}" == "linux" ]] || die "${reference} is ${image_os}/${image_architecture}; Linux is required"
  [[ "${image_architecture}" == "${server_architecture}" ]] \
    || die "${reference} is ${image_architecture}, Docker server is ${server_architecture}. Cross-architecture emulation would invalidate the comparison."

  jq -n \
    --arg variant "${variant}" \
    --arg requestedReference "${reference}" \
    --arg imageId "${image_id}" \
    --arg os "${image_os}" \
    --arg architecture "${image_architecture}" \
    --argjson repoDigests "${repo_digests}" \
    '{label: $variant, requestedReference: $requestedReference, imageId: $imageId,
      repoDigests: $repoDigests, os: $os, architecture: $architecture}' >"${output_file}"
}

echo "Resolving baseline image: ${baseline_reference}"
resolve_image baseline "${baseline_reference}" "${run_dir}/images/baseline.json"
echo "Resolving candidate image: ${candidate_reference}"
resolve_image candidate "${candidate_reference}" "${run_dir}/images/candidate.json"

baseline_id="$(jq -r '.imageId' "${run_dir}/images/baseline.json")"
candidate_id="$(jq -r '.imageId' "${run_dir}/images/candidate.json")"
[[ "${baseline_id}" != "${candidate_id}" ]] \
  || die "Baseline and candidate resolve to the same immutable image ID: ${baseline_id}"

echo "Generating benchmark descriptor bundle with ${CLI_IMAGE}"
docker run --rm \
  --user "$(id -u):$(id -g)" \
  --volume "${DESCRIPTOR_DIR}:/descriptor:ro" \
  --volume "${run_dir}/bundle:/output" \
  "${CLI_IMAGE}" \
  bundle genmod /descriptor \
  --output /output/performance-comparison-bundle.zip \
  >"${run_dir}/bundle-generation.log" 2>&1 \
  || { cat "${run_dir}/bundle-generation.log" >&2; die "Descriptor bundle generation failed"; }

bundle_path="${run_dir}/bundle/performance-comparison-bundle.zip"
[[ -s "${bundle_path}" ]] || die "CLI did not create ${bundle_path}"

git_revision="$(git -C "${REPO_DIR}" rev-parse HEAD)"
git_dirty="false"
[[ -z "$(git -C "${REPO_DIR}" status --porcelain)" ]] || git_dirty="true"
docker_version="$(docker version --format '{{.Server.Version}}')"
docker_operating_system="$(docker info --format '{{.OperatingSystem}}')"
docker_kernel_version="$(docker info --format '{{.KernelVersion}}')"
docker_logical_cpus="$(docker info --format '{{.NCPU}}')"
docker_memory_bytes="$(docker info --format '{{.MemTotal}}')"
host_operating_system="$(uname -s)"
host_cpu_model="$(read_cpu_model)"

jq -n \
  --arg startedAt "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --arg runToken "${run_token}" \
  --arg group "${group}" \
  --argjson rounds "${rounds}" \
  --arg scale "${scale}" \
  --arg cpus "${cpu_limit}" \
  --arg memory "${memory_limit}" \
  --arg hostLabel "${host_label}" \
  --arg hostOperatingSystem "${host_operating_system}" \
  --arg cpuModel "${host_cpu_model}" \
  --arg architecture "${server_architecture}" \
  --arg dockerVersion "${docker_version}" \
  --arg dockerOperatingSystem "${docker_operating_system}" \
  --arg dockerKernelVersion "${docker_kernel_version}" \
  --argjson dockerLogicalCpus "${docker_logical_cpus}" \
  --argjson dockerMemoryBytes "${docker_memory_bytes}" \
  --arg cliImage "${CLI_IMAGE}" \
  --arg grpcClientVersion "${grpc_client_version}" \
  --argjson clientRuntime "${client_runtime_json}" \
  --arg gitRevision "${git_revision}" \
  --argjson gitDirty "${git_dirty}" \
  --slurpfile baseline "${run_dir}/images/baseline.json" \
  --slurpfile candidate "${run_dir}/images/candidate.json" \
  '{format: "kubling-performance-comparison", formatVersion: 1,
    startedAt: $startedAt, runToken: $runToken, group: $group, rounds: $rounds,
    scale: ($scale | tonumber), limits: {cpus: $cpus, memory: $memory},
    host: {label: $hostLabel, operatingSystem: $hostOperatingSystem, cpuModel: $cpuModel,
      architecture: $architecture},
    docker: {serverVersion: $dockerVersion, operatingSystem: $dockerOperatingSystem,
      kernelVersion: $dockerKernelVersion, logicalCpus: $dockerLogicalCpus,
      memoryBytes: $dockerMemoryBytes},
    harness: {gitRevision: $gitRevision, gitDirty: $gitDirty, cliImage: $cliImage,
      queryTransport: "grpc",
      grpcClient: {distribution: "kubling-sqlalchemy", version: $grpcClientVersion},
      clientRuntime: $clientRuntime},
    baseline: $baseline[0], candidate: $candidate[0]}' >"${run_dir}/manifest.json"

declare -a sample_files=()

wait_for_health() {
  local container_name="$1" startup_log="$2"
  local deadline=$((SECONDS + 120)) mapped_port=""
  while (( SECONDS < deadline )); do
    if [[ "$(docker inspect --format '{{.State.Running}}' "${container_name}" 2>/dev/null)" != "true" ]]; then
      break
    fi
    mapped_port="$(docker port "${container_name}" 8282/tcp 2>/dev/null | sed -n 's/.*://p' | tail -n 1)"
    if [[ -n "${mapped_port}" ]] \
        && curl --silent --fail --max-time 1 \
          "http://127.0.0.1:${mapped_port}/observe/health" \
          | jq -e '.status == "UP"' >/dev/null 2>&1; then
      printf '%s\n' "${mapped_port}"
      return 0
    fi
    sleep 0.1
  done
  docker logs "${container_name}" >"${startup_log}" 2>&1 || true
  tail -n 160 "${startup_log}" >&2 || true
  return 1
}

run_sample() {
  local label="$1" round="$2" image_reference image_id
  local sample_key sample_dir volume_name container_name control_port grpc_port
  local start_ns ready_ns startup_ms
  local benchmark_status=0

  if [[ "${label}" == "baseline" ]]; then
    image_reference="${baseline_reference}"
    image_id="${baseline_id}"
  else
    image_reference="${candidate_reference}"
    image_id="${candidate_id}"
  fi

  sample_key="${label}-r$(printf '%02d' "${round}")"
  sample_dir="${run_dir}/samples/${sample_key}"
  container_name="kubling-perf-${run_token}-${sample_key}"
  volume_name="${container_name}-runtime"
  mkdir -p "${sample_dir}"
  docker volume create \
    --label "com.kubling.performance-compare.run=${run_token}" \
    "${volume_name}" >/dev/null
  current_volume="${volume_name}"

  echo "Running ${sample_key}: ${image_reference}"
  start_ns="$(now_ns)"
  current_container="${container_name}"
  docker run --detach \
    --name "${container_name}" \
    --label "com.kubling.performance-compare.run=${run_token}" \
    --cpus "${cpu_limit}" \
    --memory "${memory_limit}" \
    -e APP_CONFIG=/kbl/app-config.yaml \
    -e DESCRIPTOR_BUNDLE=/kbl/performance-comparison-bundle.zip \
    -e ENABLE_WEB_CONSOLE=false \
    -e MAIN_HTTP_PORT=8282 \
    -e GRPC_PORT=50051 \
    -e PERF_COMPARE_RUNTIME_DIR=/kbl/runtime \
    -e PERF_COMPARE_DB_PATH=/kbl/runtime/portable/performance-comparison \
    -e PERF_TRACER_RUN_ID="${sample_key}" \
    -p 127.0.0.1::8282 \
    -p 127.0.0.1::50051 \
    -v "${APP_CONFIG_FILE}:/kbl/app-config.yaml:ro" \
    -v "${bundle_path}:/kbl/performance-comparison-bundle.zip:ro" \
    -v "${volume_name}:/kbl/runtime" \
    "${image_id}" \
    >/dev/null

  control_port="$(wait_for_health "${container_name}" "${sample_dir}/container-startup-failure.log")" \
    || die "${sample_key} did not become healthy"
  grpc_port="$(docker port "${container_name}" 50051/tcp 2>/dev/null | sed -n 's/.*://p' | tail -n 1)"
  [[ -n "${grpc_port}" ]] || die "${sample_key} did not publish its gRPC port"
  ready_ns="$(now_ns)"
  startup_ms="$(( (ready_ns - start_ns) / 1000000 ))"

  set +e
  python3 "${BASE_DIR}/benchmark.py" execute \
    --grpc-target "127.0.0.1:${grpc_port}" \
    --control-url "http://127.0.0.1:${control_port}" \
    --run-id "${sample_key}" \
    --label "${label}" \
    --round "${round}" \
    --group "${group}" \
    --scale "${scale}" \
    --startup-ms "${startup_ms}" \
    --image-reference "${image_reference}" \
    --image-id "${image_id}" \
    --workloads "${WORKLOADS_FILE}" \
    --output "${sample_dir}/sample.json" \
    >"${sample_dir}/benchmark.log" 2>&1
  benchmark_status=$?
  set -e

  if [[ ${benchmark_status} -ne 0 ]]; then
    docker logs "${container_name}" >"${sample_dir}/container.log" 2>&1 || true
  fi

  docker stop --time 20 "${container_name}" >/dev/null 2>&1 || true
  docker rm -f "${container_name}" >/dev/null 2>&1 || true
  current_container=""
  docker volume rm -f "${volume_name}" >/dev/null 2>&1 || true
  current_volume=""

  if [[ ${benchmark_status} -ne 0 ]]; then
    cat "${sample_dir}/benchmark.log" >&2
    tail -n 160 "${sample_dir}/container.log" >&2 || true
    die "Benchmark execution failed for ${sample_key}"
  fi

  rm -f "${sample_dir}/benchmark.log"
  sample_files+=("${sample_dir}/sample.json")
}

for ((round = 1; round <= rounds; round++)); do
  if (( round % 2 == 1 )); then
    run_sample baseline "${round}"
    run_sample candidate "${round}"
  else
    run_sample candidate "${round}"
    run_sample baseline "${round}"
  fi
done

python3 "${BASE_DIR}/benchmark.py" compare \
  --manifest "${run_dir}/manifest.json" \
  --output-json "${run_dir}/summary.json" \
  --output-markdown "${run_dir}/comparison.md" \
  "${sample_files[@]}"

cat "${run_dir}/comparison.md"
echo
echo "Performance comparison evidence: ${run_dir}"
