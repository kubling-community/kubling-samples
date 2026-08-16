#!/bin/sh

set -eu

kubling_base_url="${KUBLING_BASE_URL:-http://kubling:8282}"
kubling_vdb="${KUBLING_VDB:-InitializerVDB}"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  value="$1"
  expected="$2"
  description="$3"

  case "${value}" in
    *"${expected}"*) ;;
    *) fail "${description}; expected ${expected} in ${value}" ;;
  esac
}

encode_query() {
  printf '%s' "$1" |
    base64 |
    tr -d '\n' |
    sed -e 's/+/%2B/g' -e 's#/#%2F#g' -e 's/=/%3D/g'
}

execute_sql() {
  query="$1"
  encoded_query="$(encode_query "${query}")"
  curl --fail --silent --show-error \
    "${kubling_base_url}/api/v1/admin/query/${kubling_vdb}/${encoded_query}"
}

read_state() {
  execute_sql "SELECT id, generation, token FROM initializer.SCHEDULER_STATE"
}

read_generation() {
  printf '%s' "$1" |
    sed -n \
      -e 's/.*"generation":"\([0-9][0-9]*\)".*/\1/p' \
      -e 's/.*"generation":\([0-9][0-9]*\).*/\1/p'
}

studio_status="$(
  curl --silent --show-error --location \
    --output /dev/null \
    --write-out '%{http_code}' \
    "${kubling_base_url}/console"
)"
if [ "${studio_status}" != "200" ]; then
  fail "Kubling Studio returned HTTP ${studio_status}, expected 200"
fi

initial_state="$(read_state)"
assert_contains "${initial_state}" '"containsRows":true' "initializer query returned no rows"
assert_contains "${initial_state}" '"id":"scheduler"' "initializer row is missing"

initial_generation="$(read_generation "${initial_state}")"
if [ -z "${initial_generation}" ]; then
  fail "could not read the initial scheduler generation from ${initial_state}"
fi
assert_contains "${initial_state}" "\"token\":\"token-${initial_generation}\"" "initial token and generation do not match"

attempt=0
while [ "${attempt}" -lt 15 ]; do
  current_state="$(read_state)"
  current_generation="$(read_generation "${current_state}")"

  if [ -n "${current_generation}" ] && [ "${current_generation}" -gt "${initial_generation}" ]; then
    assert_contains "${current_state}" "\"token\":\"token-${current_generation}\"" "scheduled token and generation do not match"
    printf 'Initializer smoke test passed: generation advanced from %s to %s.\n' \
      "${initial_generation}" "${current_generation}"
    exit 0
  fi

  attempt=$((attempt + 1))
  sleep 1
done

fail "scheduled generation did not advance from ${initial_generation} within 15 seconds"
