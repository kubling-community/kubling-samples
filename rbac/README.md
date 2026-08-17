# RBAC Sample

This sample demonstrates transport-scoped Kubling authentication and data-role authorization against the official In-memory gRPC provider. A JavaScript authentication delegate accepts two deterministic local users only through `SOCKET_TRANSPORT`, maps them to external roles, and `RbacVDB` grants each role a different set of permissions on `provider.TASK`.

## Contract

The sample has no external database. Compose runs PostgreSQL only as a disposable `psql` client; the data source remains the official In-memory provider over gRPC.

The sample credentials are teaching fixtures:

| User | Password | External role | Access to `provider.TASK` |
|:--|:--|:--|:--|
| `reader` | `reader-pass` | `ROLE_TASK_READER` | Read only |
| `editor` | `editor-pass` | `ROLE_TASK_EDITOR` | Read and update |

The provider schema is imported through `GetSchema`; the VDB does not duplicate its DDL.

| Item | Value |
|:--|:--|
| Kubling image | `docker.io/kubling/kubling:latest` |
| Provider image | `docker.io/kubling/inmemory-provider:latest` |
| Descriptor builder | `docker.io/kubling/kubling-cli:latest` |
| Disposable SQL client | `docker.io/library/postgres:latest` |
| VDB/database | `RbacVDB` |
| Data source and schema | `provider` |
| Protected table | `TASK` |
| Accepted authentication source | `SOCKET_TRANSPORT` |
| Intentionally rejected source | `HTTP`, used by Kubling Studio |
| Published host port | `8282`, Studio and health, on all host interfaces |
| Kubling SQL transport | `kubling:35432`, internal to Compose |
| Provider gRPC | `provider:50051`, internal to Compose |
| Health | `http://localhost:8282/observe/health` |

## Walkthrough

Start the stack from this directory:

```bash
docker compose up --wait
```

## Verify the authentication boundary

The credentials in this sample are valid only for the socket transport. Kubling Studio authenticates through `HTTP`, so entering `reader` / `reader-pass` or `editor` / `editor-pass` in Studio must not create a session.

You can verify the same behavior without a browser:

```bash
docker compose exec -T stack-readiness curl --include \
  --user reader:reader-pass \
  --request POST \
  http://kubling:8282/api/v1/studio/session
```

Expected status: `HTTP 401 Unauthorized`.

This is an authentication-source rejection, not an RBAC denial: no authenticated HTTP identity exists yet, so the VDB roles are never evaluated.

To enable Studio authentication, modify `descriptor/auth/authenticator.js` to accept `HTTP` explicitly and decide which principals and roles that source should receive. Do not remove the source check indiscriminately: the delegate also receives the source for other transports.

## Verify socket authentication and RBAC

First, the reader can see the deterministic task:

```bash
docker compose run --rm sql-client \
  --username reader \
  --command "SELECT id, title, completed FROM provider.TASK WHERE id = 'task-2'"
```

Expected row:

```text
task-2|Build in-memory provider|f
```

`psql` renders PostgreSQL boolean values as `f` and `t` in unaligned output.

The same user must be denied this mutation, and the row must remain unchanged:

```bash
docker compose run --rm sql-client \
  --username reader \
  --command "UPDATE provider.TASK SET completed = true WHERE id = 'task-2'"
```

The editor must be allowed to apply it:

```bash
RBAC_PASSWORD=editor-pass docker compose run --rm sql-client \
  --username editor \
  --command "UPDATE provider.TASK SET completed = true WHERE id = 'task-2'"
```

A subsequent reader query must return:

```text
task-2|Build in-memory provider|t
```

Restore the deterministic state with the editor before finishing:

```bash
RBAC_PASSWORD=editor-pass docker compose run --rm sql-client \
  --username editor \
  --command "UPDATE provider.TASK SET completed = false WHERE id = 'task-2'"
```

## Automated validation

With the stack running, execute:

```bash
docker compose --profile test run --rm smoke-test
```

Every client connection has an eight-second timeout, so a broken transport fails instead of hanging indefinitely. The smoke test must verify all of these behaviors:

- invalid credentials are rejected;
- `reader` can read deterministic `task-2`;
- `reader` cannot update it;
- the failed reader update does not change provider state;
- `editor` can update it; and
- the test restores `task-2` to its original state.

Only this final output constitutes a pass:

```text
RBAC smoke test passed.
```

The GitHub workflow runs both the static contract and Docker E2E on pull requests and pushes that affect this sample.
The static contract also verifies that the authentication delegate remains intentionally scoped to `SOCKET_TRANSPORT`.

## Requirements

- Git
- Docker Engine
- Docker Compose v2

## Cleanup

Remove containers, the network, and the generated descriptor volume with:

```bash
docker compose down --volumes --remove-orphans
```
