# Endpoints Sample

This sample demonstrates Kubling query endpoints and actions against the official In-memory gRPC provider. It is intentionally small: one endpoint reads a task, and one action creates one.

## Requirements

- Git;
- Docker Engine; and
- Docker Compose v2.

You do not need Go, Java, Kubernetes, a database server, source credentials, or a host-installed SQL client.

## Start

From this directory, run:

```bash
docker compose up --wait
```

The stack publishes Kubling on <http://localhost:8283>. Its aggregate health endpoint is <http://localhost:8283/observe/health>, and Kubling Studio is available at <http://localhost:8283/console>.

## Architecture

Kubling loads `EndpointsVDB`, registers the `provider` schema as `PROVIDER_GRPC`, and imports its physical schema through `GetSchema`. The VDB does not duplicate provider DDL.

The descriptor also registers:

- `get_task`, a parameterized SQL query endpoint; and
- `create_task`, an action with an insert operation.

Both endpoints execute through Kubling. The provider remains responsible for source-side reads and mutations.

## Query endpoint

The provider starts `task-2` with `completed = false`. Retrieve it through the named endpoint:

```bash
curl --fail --silent --show-error \
  --header 'Content-Type: application/json' \
  --data '{"task_id":"task-2"}' \
  http://localhost:8283/api/v1/query/perform/get_task
```

The response contains:

```json
{
  "containsError": false,
  "object": [
    {
      "id": "task-2",
      "title": "Build in-memory provider",
      "completed": false
    }
  ]
}
```

`task_id` is declared as a required template field. This local sample uses a trusted deterministic value; production endpoints must validate any untrusted value before interpolating it into SQL.

## Action endpoint

Create a deterministic task through the named action:

```bash
curl --fail --silent --show-error \
  --header 'Content-Type: application/json' \
  --data '{"task_id":"task-endpoint-sample"}' \
  http://localhost:8283/api/v1/actions/run/create_task
```

Expected response:

```json
{
  "containsError": false
}
```

Calling `get_task` with `task-endpoint-sample` then returns:

```json
{
  "containsError": false,
  "object": [
    {
      "id": "task-endpoint-sample",
      "title": "Created through an action",
      "completed": false
    }
  ]
}
```

The insert is executed through the provider. Reusing the same ID without deleting the task first is expected to fail because provider task IDs are unique.

## Automated validation

With the stack running, execute:

```bash
docker compose --profile test run --rm smoke-test
```

The smoke test removes any prior sample task, exercises the query endpoint, runs the action, verifies the resulting provider state, and removes the task again. It prints `Endpoints smoke test passed.` on success.

## Runtime contract

| Item | Value |
|:--|:--|
| Kubling image | `docker.io/kubling/kubling:latest` |
| Provider image | `docker.io/kubling/inmemory-provider:latest` |
| Descriptor builder | `docker.io/kubling/kubling-cli:latest` |
| VDB | `EndpointsVDB` |
| Data source and schema | `provider` |
| Provider table | `TASK` |
| Published host port | `8283` on all host interfaces |
| Provider gRPC | `provider:50051`, internal to Compose |
| Health | `http://localhost:8283/observe/health` |

## Cleanup

Remove containers, the network, and the generated descriptor volume:

```bash
docker compose down --volumes
```
