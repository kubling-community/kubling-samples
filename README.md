# Kubling Samples

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg?style=flat-square)](LICENSE)

Runnable examples for Kubling. This repository provides the canonical first-run experience and focused examples for features that are easier to understand from working code than from reference documentation alone.

## Quickstart

The supported 26.4 Quickstart runs Kubling, Kubling Studio, and the official In-memory provider with Docker Compose.

```bash
cd quickstart
docker compose up --wait
```

Open <http://localhost:8282/console>, or follow the complete [Quickstart guide](quickstart/README.md) for its deterministic query, mutation, automated smoke test, and cleanup.

The Quickstart requires only Git, Docker Engine, and Docker Compose v2. It does not require Go, Java, Kubernetes, an external database, or source credentials.

## Feature examples

The repository also provides focused feature examples. Entries marked as legacy predate 26.4 and are retained as source material rather than supported runbooks:

| Directory | What it teaches | Current state |
|:--|:--|:--|
| `endpoints/` | Query endpoints, actions, mutations, and templates | Supported on 26.4 |
| `rbac/` | Authentication, authorization, and data policies | Supported on 26.4 |
| `javascript/` | JavaScript data sources, module bundles, and table handlers | Supported on 26.4 |
| `functions/` | SQL functions and custom template functions | Supported on 26.4 |
| `initializer/` | Initialization and scheduled JavaScript behavior | Supported on 26.4 |
| `synthetic-entities/` | Relational projections and mutations over nested document arrays | Supported on 26.4 |

Each legacy directory carries its own warning. Until that warning is removed, use the code to understand the feature—not as a validated 26.4 deployment recipe. Provider-backed examples must use `PROVIDER_GRPC`; a sample may intentionally use a JavaScript adapter when JavaScript itself is the lesson.

## Sample quality contract

Every supported sample must:

- teach one clear Kubling capability;
- run independently with exact dependency versions;
- state prerequisites, startup, readiness, verification, expected results, and cleanup;
- avoid external credentials and paid infrastructure unless that dependency is the lesson;
- keep generated bundles and runtime state out of Git; and
- include automation appropriate to its scope.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the complete contribution contract.

## Generated artifacts

Descriptor and module bundles are build output. ZIP files, compiled classes, JARs, database files, and runtime state must not be committed.

Supported samples run an exact Kubling CLI image to generate descriptor and module bundles inside named Compose volumes. Contributors therefore do not need to install the CLI or a host-language toolchain.

## Versioning

Samples target an explicit Kubling release line. The first modernized baseline is `26.4`.

- Published image references use exact versions; `latest` and untagged images are not accepted.
- The canonical Quickstart will also pin image digests once the public release digests are confirmed.
- Repository release tags should identify the compatible Kubling line, for example `26.4.0` or `26.4.0-1` for a samples-only correction.

The repository is published as `kubling-community/kubling-samples`, a name that covers both the Quickstart and the advanced feature examples.

## License

Licensed under the [Apache License 2.0](LICENSE).
