# Synthetic Entities Sample

This sample shows how Kubling exposes an array inside a document as a relational table and maps a SQL mutation back into the parent document.

The JavaScript data source owns one deterministic `PROJECT` document:

```json
{
  "project_id": "project-1",
  "name": "Kubling samples",
  "members": [
    {"member_id": "user-1", "display_name": "Ada", "role": "owner"},
    {"member_id": "user-2", "display_name": "Linus", "role": "developer"}
  ]
}
```

`PROJECT_MEMBER` has no independent upstream representation. Its `synthetic_parent` and `synthetic_path` directives instruct Kubling to ungroup `members` for queries and rebuild the `PROJECT` document for mutations.

Both tables declare a generated identifier and a business `UNIQUE` key. Those keys let Kubling locate the physical parent and the exact member inside its nested array during a mutation.

## Source map

- `module/schema.sql` defines the physical parent and synthetic child tables.
- `module/data/projects.js` provides deterministic nested documents.
- `module/handler/PROJECT.js` reads and persists complete parent documents.
- `module/bundle-script-info.yaml` enables table-handler discovery and module-owned DDL.

The handler knows only about `PROJECT`. Kubling performs the synthetic projection and mutation mapping before invoking it.

## Prerequisites

- Git
- Docker Engine
- Docker Compose v2

## Start

```bash
cd synthetic-entities
docker compose up --wait
```

Compose generates the descriptor and JavaScript module bundles with the official Kubling CLI image. Generated ZIP files live only in a named volume and are not committed.

When the stack is ready:

- Kubling Studio: <http://localhost:8282/console>
- Health endpoint: <http://localhost:8282/observe/health>
- VDB: `SyntheticEntitiesVDB`
- schema/data source: `synthetic`
- physical table: `PROJECT`
- synthetic table: `PROJECT_MEMBER`

## Query the nested array

Open Kubling Studio and run:

```sql
SELECT project_id, member_id, display_name, role
FROM synthetic.PROJECT_MEMBER
ORDER BY member_id;
```

Expected rows:

| project_id | member_id | display_name | role |
|:--|:--|:--|:--|
| `project-1` | `user-1` | `Ada` | `owner` |
| `project-1` | `user-2` | `Linus` | `developer` |

## Mutate a synthetic row

```sql
UPDATE synthetic.PROJECT_MEMBER
SET role = 'maintainer'
WHERE project_id = 'project-1' AND member_id = 'user-2';
```

Expected affected rows: `1`.

Query `PROJECT_MEMBER` again. `user-2` now has role `maintainer`. Kubling applied the change to the nested `members` array and passed the complete updated `PROJECT` document to its handler.

## Automated verification

Run the same query and mutation assertions used by CI:

```bash
docker compose --profile test run --rm --no-deps smoke-test
```

Static checks are available from the repository root:

```bash
bash scripts/check-synthetic-entities.sh
```

## Cleanup

```bash
docker compose down --volumes --remove-orphans
```
