#!/bin/sh

set -eu

kubling_base_url="${KUBLING_BASE_URL:-http://kubling:8282}"
kubling_vdb="${KUBLING_VDB:-SyntheticEntitiesVDB}"

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

members="$(execute_sql "SELECT project_id, member_id, display_name, role FROM synthetic.PROJECT_MEMBER ORDER BY member_id")"
assert_contains "${members}" '"containsRows":true' "synthetic member query returned no rows"
assert_contains "${members}" '"project_id":"project-1"' "synthetic parent field is missing"
assert_contains "${members}" '"member_id":"user-1"' "user-1 is missing from the members array"
assert_contains "${members}" '"display_name":"Ada"' "user-1 display name is incorrect"
assert_contains "${members}" '"role":"owner"' "user-1 role is incorrect"
assert_contains "${members}" '"member_id":"user-2"' "user-2 is missing from the members array"
assert_contains "${members}" '"display_name":"Linus"' "user-2 display name is incorrect"

mutation="$(execute_sql "UPDATE synthetic.PROJECT_MEMBER SET role = 'maintainer' WHERE project_id = 'project-1' AND member_id = 'user-2'")"
assert_contains "${mutation}" '"affectedRows":1' "synthetic update did not affect one parent document"

after="$(execute_sql "SELECT project_id, member_id, role FROM synthetic.PROJECT_MEMBER WHERE project_id = 'project-1' AND member_id = 'user-2'")"
assert_contains "${after}" '"containsRows":true' "updated synthetic member is missing"
assert_contains "${after}" '"member_id":"user-2"' "updated member id is incorrect"
assert_contains "${after}" '"role":"maintainer"' "synthetic update was not persisted in the parent document"

printf 'Synthetic entities smoke test passed.\n'
