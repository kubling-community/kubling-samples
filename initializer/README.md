# Initialization and Scheduling Sample

This sample shows how a Kubling JavaScript data source can initialize shared state before accepting queries and update that state with a scheduled script.

The module exposes one row through `SCHEDULER_STATE`:

- the initialization script creates generation `0` and token `token-0`;
- the scheduled script advances the generation every two seconds; and
- the table handler reads the current state from Kubling's shared thread-safe key/value store.

The generation and token are stored together as one JSON value, so readers never observe a token from a different generation.

## Source map

- `module/init/initialize_state.js` establishes the state and reports successful initialization.
- `module/scheduled/advance_state.js` advances it on a six-field cron schedule.
- `module/handler/SCHEDULER_STATE.js` exposes the current value as a table row.
- `module/bundle-script-info.yaml` connects the lifecycle scripts, handler directory, DDL, and translator configuration.

## Prerequisites

- Git
- Docker Engine
- Docker Compose v2

No Node.js, Java, database, credentials, or Kubernetes cluster is required on the host.

## Start

```bash
cd initializer
docker compose up --wait
```

Compose generates the descriptor and JavaScript module bundles with an exact Kubling CLI image. Generated ZIP files live only in a named volume and are not committed.

When the stack is ready:

- Kubling Studio: <http://localhost:8282/console>
- Health endpoint: <http://localhost:8282/observe/health>
- VDB: `InitializerVDB`
- schema/data source: `initializer`
- table: `SCHEDULER_STATE`

## Observe the lifecycle

Open Kubling Studio and run:

```sql
SELECT id, generation, token
FROM initializer.SCHEDULER_STATE;
```

The result always contains one coherent row:

| id | generation | token |
|:--|--:|:--|
| `scheduler` | `n` | `token-n` |

Run the query again after two seconds. The generation will be greater and the token suffix will match it. The exact generation depends on how long the stack has been running.

## Automated verification

Run the same lifecycle assertions used by CI:

```bash
docker compose --profile test run --rm --no-deps smoke-test
```

Static checks are available from the repository root:

```bash
bash scripts/check-initializer.sh
```

## Cleanup

```bash
docker compose down --volumes --remove-orphans
```
