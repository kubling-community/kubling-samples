#!/usr/bin/env bash

set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
cd "${repository_root}"

errors=0

report_error() {
  printf 'ERROR: %s\n' "$1" >&2
  errors=$((errors + 1))
}

required_files=(
  .editorconfig
  .gitattributes
  .gitignore
  CONTRIBUTING.md
  LICENSE
  README.md
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "${required_file}" ]]; then
    report_error "required repository file is missing: ${required_file}"
  fi
done

while IFS= read -r generated_file; do
  if [[ -e "${generated_file}" ]]; then
    report_error "generated artifact is tracked: ${generated_file}"
  fi
done < <(git ls-files '*.zip' '*.jar' '*.class')

while IFS= read -r shell_script; do
  if [[ -e "${shell_script}" ]] && ! bash -n "${shell_script}"; then
    report_error "invalid shell syntax: ${shell_script}"
  fi
done < <(git ls-files '*.sh')

private_registry="europe-southwest1-docker.pkg"".dev/bluelone""-repos"
while IFS= read -r private_reference; do
  report_error "private registry reference must not be committed: ${private_reference}"
done < <(
  {
    git grep -n -F "${private_registry}" -- . || true
    git grep --cached -n -F "${private_registry}" -- . || true
  } | sort -u
)

internal_runtime_flag="RUNNING_IN_KUBLING_""ENV"
while IFS= read -r internal_reference; do
  report_error "internal runtime configuration must not be committed: ${internal_reference}"
done < <(
  {
    git grep -n -F "${internal_runtime_flag}" -- . || true
    git grep --cached -n -F "${internal_runtime_flag}" -- . || true
  } | sort -u
)

if (( errors > 0 )); then
  printf 'Repository checks failed with %d error(s).\n' "${errors}" >&2
  exit 1
fi

printf 'Repository checks passed.\n'
