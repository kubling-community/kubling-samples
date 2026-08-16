#!/bin/sh

set -eu

kubling_base_url="${KUBLING_BASE_URL:-http://kubling:8282}"
kubling_vdb="${KUBLING_VDB:-ProviderQuickstartVDB}"

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

projects="$(execute_sql "SELECT id, name, status, active FROM provider.PROJECT ORDER BY id")"
assert_contains "${projects}" '"containsRows":true' "project query returned no rows"
assert_contains "${projects}" '"id":"project-1"' "project-1 is missing"
assert_contains "${projects}" '"name":"Provider SDK"' "project-1 name is incorrect"
assert_contains "${projects}" '"id":"project-2"' "project-2 is missing"
assert_contains "${projects}" '"name":"Engine Integration"' "project-2 name is incorrect"

reset="$(execute_sql "UPDATE provider.TASK SET completed = false WHERE id = 'task-2'")"
assert_contains "${reset}" '"affectedRows":1' "task-2 reset did not affect one row"

before="$(execute_sql "SELECT id, completed FROM provider.TASK WHERE id = 'task-2'")"
assert_contains "${before}" '"id":"task-2"' "task-2 is missing before mutation"
assert_contains "${before}" '"completed":"false"' "task-2 did not start incomplete"

mutation="$(execute_sql "UPDATE provider.TASK SET completed = true WHERE id = 'task-2'")"
assert_contains "${mutation}" '"affectedRows":1' "task-2 mutation did not affect one row"

after="$(execute_sql "SELECT id, completed FROM provider.TASK WHERE id = 'task-2'")"
assert_contains "${after}" '"id":"task-2"' "task-2 is missing after mutation"
assert_contains "${after}" '"completed":"true"' "task-2 mutation was not persisted by the provider"

printf 'Quickstart smoke test passed.\n'
