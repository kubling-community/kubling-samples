# Functions Sample

This sample shows how Kubling loads JavaScript functions from independently generated modules. It combines two related extension points:

- `task_label`, a deterministic SQL user-defined function invoked from a query; and
- `validate_task_id`, a custom template function that validates a task identifier for a query endpoint.

Both functions operate on the deterministic data exposed by the official Kubling In-memory provider. JavaScript is used only to implement the functions; the physical data source follows the provider gRPC architecture.

## Source map

- `sql-functions/bundle-sql-function-info.yaml` declares the SQL function signature and runtime limits.
- `sql-functions/fn/task_label.js` implements the SQL function.
- `template-functions/bundle-function-info.yaml` declares the template function and its ordered parameters.
- `template-functions/fn/validate_task_id.js` validates the endpoint parameter before the template uses it.
- `descriptor/endpoint/queries/get_task_label.yaml` uses the template function while building an endpoint query and the SQL function while executing it.

Function files cannot import modules or call other user-defined functions. Kubling loads and evaluates the declared function itself rather than executing the file as a general script.

## Prerequisites

- Git
- Docker Engine
- Docker Compose v2

No Node.js, Java, database, credentials, or Kubernetes cluster is required on the host.

## Start

```bash
cd functions
docker compose up --wait
```

Compose generates the descriptor, SQL-function, and template-function bundles with an exact Kubling CLI image. The ZIP files live only in a named volume and are not committed.

When the stack is ready:

- Kubling Studio: <http://localhost:8282/console>
- Health endpoint: <http://localhost:8282/observe/health>
- VDB: `FunctionsVDB`
- schema/data source: `provider`
- table: `TASK`
- query endpoint: `get_task_label`

## SQL function

Open Kubling Studio and run:

```sql
SELECT id, task_label(id, title) AS label
FROM provider.TASK
WHERE id = 'task-2';
```

Expected row:

| id | label |
|:--|:--|
| `task-2` | `task-2: Build in-memory provider` |

The parameter names and order in `bundle-sql-function-info.yaml` determine how SQL values are exposed to the JavaScript `args` object.

## Template function

Call the query endpoint from any HTTP client:

```http
POST http://localhost:8282/api/v1/query/perform/get_task_label
Content-Type: application/json

{"task_id":"task-2"}
```

The template calls `templates__validate_task_id(_context.task_id)` before producing the SQL query. The validated value is then quoted by the endpoint template. The resulting query also calls `task_label`, so the expected response contains:

```json
{
  "id": "task-2",
  "label": "task-2: Build in-memory provider"
}
```

## Automated verification

Run the same SQL and endpoint assertions used by CI:

```bash
docker compose --profile test run --rm --no-deps smoke-test
```

Static checks are available from the repository root:

```bash
bash scripts/check-functions.sh
```

## Cleanup

```bash
docker compose down --volumes --remove-orphans
```
