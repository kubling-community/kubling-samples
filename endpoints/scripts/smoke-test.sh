#!/bin/sh

set -eu

kubling_base_url="${KUBLING_BASE_URL:-http://kubling:8282}"
kubling_vdb="${KUBLING_VDB:-EndpointsVDB}"
sample_task_id="task-endpoint-sample"

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

cleanup() {
  execute_sql "DELETE FROM provider.TASK WHERE id = '${sample_task_id}'" >/dev/null 2>&1 || true
}

query_sample_task() {
  curl --fail --silent --show-error \
    --header 'Content-Type: application/json' \
    --data "{\"task_id\":\"${sample_task_id}\"}" \
    "${kubling_base_url}/api/v1/query/perform/get_task"
}

trap cleanup 0
cleanup

before="$(
  curl --fail --silent --show-error \
    --header 'Content-Type: application/json' \
    --data '{"task_id":"task-2"}' \
    "${kubling_base_url}/api/v1/query/perform/get_task"
)"
assert_contains "${before}" '"containsError":false' "query endpoint returned an error"
assert_contains "${before}" '"id":"task-2"' "query endpoint did not return task-2"
assert_contains "${before}" '"title":"Build in-memory provider"' "query endpoint returned the wrong title"
assert_contains "${before}" '"completed":false' "task-2 has an unexpected initial state"

missing="$(query_sample_task)"
assert_contains "${missing}" '"containsError":false' "query endpoint returned an error for the absent sample task"
assert_contains "${missing}" '"object":[]' "sample task exists before the action"

action="$(
  curl --fail --silent --show-error \
    --header 'Content-Type: application/json' \
    --data "{\"task_id\":\"${sample_task_id}\"}" \
    "${kubling_base_url}/api/v1/actions/run/create_task"
)"
assert_contains "${action}" '"containsError":false' "create_task returned an error"

after="$(query_sample_task)"
assert_contains "${after}" '"containsError":false' "query endpoint returned an error after the action"
assert_contains "${after}" '"id":"task-endpoint-sample"' "created task is missing after the action"
assert_contains "${after}" '"title":"Created through an action"' "created task has the wrong title"
assert_contains "${after}" '"completed":false' "created task has the wrong completed state"

cleanup
cleaned="$(query_sample_task)"
assert_contains "${cleaned}" '"containsError":false' "query endpoint returned an error after cleanup"
assert_contains "${cleaned}" '"object":[]' "sample task remains after cleanup"
trap - 0

printf 'Endpoints smoke test passed.\n'
