#!/bin/sh

set -eu

kubling_host="${KUBLING_HOST:-kubling}"
kubling_port="${KUBLING_PORT:-35432}"
kubling_vdb="${KUBLING_VDB:-RbacVDB}"
export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-8}"

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

run_sql() {
  user="$1"
  password="$2"
  sql="$3"

  PGPASSWORD="${password}" psql \
    --host "${kubling_host}" \
    --port "${kubling_port}" \
    --dbname "${kubling_vdb}" \
    --username "${user}" \
    --no-password \
    --tuples-only \
    --no-align \
    --command "${sql}"
}

read_task() {
  run_sql \
    "reader" \
    "reader-pass" \
    "SELECT id, title, completed FROM provider.TASK WHERE id = 'task-2'"
}

cleanup() {
  run_sql \
    "editor" \
    "editor-pass" \
    "UPDATE provider.TASK SET completed = false WHERE id = 'task-2'" \
    >/dev/null 2>&1 || true
}

trap cleanup 0
cleanup

if run_sql "reader" "wrong-password" "SELECT 1" >/tmp/invalid-credentials 2>&1; then
  fail "invalid credentials were accepted"
fi

before="$(read_task)"
assert_contains "${before}" "task-2|Build in-memory provider|f" "reader could not read task-2"

if run_sql \
  "reader" \
  "reader-pass" \
  "UPDATE provider.TASK SET completed = true WHERE id = 'task-2'" \
  >/tmp/reader-update 2>&1; then
  fail "reader update was not denied"
fi

after_denial="$(read_task)"
assert_contains "${after_denial}" "task-2|Build in-memory provider|f" "reader update changed provider state"

run_sql \
  "editor" \
  "editor-pass" \
  "UPDATE provider.TASK SET completed = true WHERE id = 'task-2'" \
  >/dev/null

after_editor="$(read_task)"
assert_contains "${after_editor}" "task-2|Build in-memory provider|t" "editor update did not persist through the provider"

cleanup
restored="$(read_task)"
assert_contains "${restored}" "task-2|Build in-memory provider|f" "task-2 was not restored"

trap - 0
printf 'RBAC smoke test passed.\n'
