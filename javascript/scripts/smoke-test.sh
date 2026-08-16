#!/bin/sh

set -eu

kubling_base_url="${KUBLING_BASE_URL:-http://kubling:8282}"
kubling_vdb="${KUBLING_VDB:-JavaScriptVDB}"

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

tasks="$(execute_sql "SELECT id, title, priority, completed FROM javascript.TASK ORDER BY id")"
assert_contains "${tasks}" '"containsRows":true' "TASK query returned no rows"
assert_contains "${tasks}" '"id":"task-1"' "task-1 is missing"
assert_contains "${tasks}" '"title":"Learn module bundles"' "task-1 title is incorrect"
assert_contains "${tasks}" '"id":"task-2"' "task-2 is missing"
assert_contains "${tasks}" '"title":"Inspect queryFilter"' "task-2 title is incorrect"
assert_contains "${tasks}" '"id":"task-3"' "task-3 is missing"
assert_contains "${tasks}" '"title":"Handle a mutation"' "task-3 title is incorrect"

mutation="$(execute_sql "INSERT INTO javascript.TASK (id, title, priority, completed) VALUES ('task-ci', 'Created by the smoke test', 4, false)")"
assert_contains "${mutation}" '"affectedRows":1' "TASK insert did not affect one row"

after="$(execute_sql "SELECT id FROM javascript.TASK WHERE id = 'task-ci'")"
assert_contains "${after}" '"rows":[]' "stateless TASK handler unexpectedly persisted task-ci"

printf 'JavaScript smoke test passed.\n'
