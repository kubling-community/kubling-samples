#!/bin/sh

set -eu

kubling_base_url="${KUBLING_BASE_URL:-http://kubling:8282}"
kubling_vdb="${KUBLING_VDB:-FunctionsVDB}"

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

studio_status="$(
  curl --silent --show-error --location \
    --output /dev/null \
    --write-out '%{http_code}' \
    "${kubling_base_url}/console"
)"
if [ "${studio_status}" != "200" ]; then
  fail "Kubling Studio returned HTTP ${studio_status}, expected 200"
fi

sql_result="$(execute_sql "SELECT id, task_label(id, title) AS label FROM provider.TASK WHERE id = 'task-2'")"
assert_contains "${sql_result}" '"containsRows":true' "SQL function query returned no rows"
assert_contains "${sql_result}" '"id":"task-2"' "SQL function query did not return task-2"
assert_contains "${sql_result}" '"label":"task-2: Build in-memory provider"' "task_label returned an unexpected value"

endpoint_result="$(
  curl --fail --silent --show-error \
    --header 'Content-Type: application/json' \
    --data '{"task_id":"task-2"}' \
    "${kubling_base_url}/api/v1/query/perform/get_task_label"
)"
assert_contains "${endpoint_result}" '"containsError":false' "function query endpoint returned an error"
assert_contains "${endpoint_result}" '"id":"task-2"' "function query endpoint did not return task-2"
assert_contains "${endpoint_result}" '"label":"task-2: Build in-memory provider"' "function query endpoint returned an unexpected label"

printf 'Functions smoke test passed.\n'
