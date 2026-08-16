# RBAC Sample

This sample demonstrates Kubling authentication and data-role authorization against the official In-memory gRPC provider. A JavaScript authentication delegate maps two deterministic local users to external roles, and `RbacVDB` grants each role a different set of permissions on `provider.TASK`.

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
| Published host port | `8284`, health only, on all host interfaces |
| Kubling SQL transport | `kubling:35432`, internal to Compose |
| Provider gRPC | `provider:50051`, internal to Compose |
| Health | `http://localhost:8284/observe/health` |

## Walkthrough

Start the stack from this directory:

```bash
docker compose up --wait
```

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

## Requirements

- Git;
- Docker Engine; and
- Docker Compose v2.

You do not need Go, Java, Kubernetes, source credentials, a database server, or a host-installed SQL client.

## Cleanup

Remove containers, the network, and the generated descriptor volume with:

```bash
docker compose down --volumes --remove-orphans
```
