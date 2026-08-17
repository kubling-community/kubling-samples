# Kubling Quickstart

Run Kubling, Kubling Studio, and the official In-memory provider as one disposable Docker Compose project.

## Requirements

- Git
- Docker Engine
- Docker Compose v2

## Start

From this directory, run:

```bash
docker compose up --wait
```

Compose generates the descriptor bundle into a named volume, verifies the provider's gRPC `Health` RPC, starts Kubling only after the provider is ready, and waits for Kubling's aggregate health endpoint.

Open Kubling Studio at <http://localhost:8282/console>.

The Studio login form requires non-empty values even when the VDB has no authentication delegate. For this local stack you can enter `quickstart` for both fields; they are not external credentials and are not persisted by this repository.

## Runtime contract

| Item | Value |
|:--|:--|
| Kubling image | `docker.io/kubling/kubling:latest` |
| Provider image | `docker.io/kubling/inmemory-provider:latest` |
| Descriptor builder | `docker.io/kubling/kubling-cli:latest` |
| Provider health probe | `docker.io/fullstorydev/grpcurl:latest` |
| HTTP readiness and smoke test | `docker.io/curlimages/curl:latest` |
| Studio | `http://localhost:8282/console` |
| Health | `http://localhost:8282/observe/health` |
| Published host port | `8282` on all host interfaces |
| Provider gRPC | `provider:50051`, internal to Compose |
| VDB | `ProviderQuickstartVDB` |
| Data source and schema | `provider` |
| Tables | `PROJECT`, `TASK`, `AUDIT_EVENT`, `TYPE_SAMPLE` |

Kubling registers `provider` as `PROVIDER_GRPC`. The VDB contains no provider table DDL: Kubling imports the physical schema returned by the provider's `GetSchema` RPC.

When the stack is ready, the health URL returns HTTP `200` with aggregate status `UP`. Because `provider` contributes to aggregate health, that status also verifies the provider connection.

## Query deterministic data

In Studio's SQL Workspace, select `ProviderQuickstartVDB` and run:

```sql
SELECT id, name, status, active
FROM provider.PROJECT
ORDER BY id;
```

Expected result:

| id | name | status | active |
|:--|:--|:--|:--|
| `project-1` | `Provider SDK` | `A` | `true` |
| `project-2` | `Engine Integration` | `P` | `true` |

## Run a mutation

The provider starts `task-2` with `completed = false`. Run:

```sql
UPDATE provider.TASK
SET completed = true
WHERE id = 'task-2';
```

Expected update count: `1`.

Verify the provider-owned change:

```sql
SELECT id, title, completed
FROM provider.TASK
WHERE id = 'task-2';
```

Expected result:

| id | title | completed |
|:--|:--|:--|
| `task-2` | `Build in-memory provider` | `true` |

The data resets to its canonical state whenever the provider container is recreated.

## Automated validation

With the stack running, execute:

```bash
docker compose --profile test run --rm smoke-test
```

The check validates Kubling Studio, both projects, resets `task-2`, performs the mutation, and verifies the resulting provider state. It prints `Quickstart smoke test passed.` on success.

## Inspect or stop

Show service state or logs:

```bash
docker compose ps
docker compose logs kubling provider
```

Remove containers, the network, and the generated descriptor volume:

```bash
docker compose down --volumes --remove-orphans
```
