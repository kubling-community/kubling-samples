# Kubling Samples

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg?style=flat-square)](LICENSE)

Runnable examples for Kubling. This repository provides the canonical first-run experience and focused examples for features that are easier to understand from working code than from reference documentation alone.

## Quickstart

The supported Quickstart runs Kubling, Kubling Studio, and the official In-memory provider with Docker Compose.

```bash
cd quickstart
docker compose up --wait
```

Open <http://localhost:8282/console>, or follow the complete [Quickstart guide](quickstart/README.md) for its deterministic query, mutation, automated smoke test, and cleanup.

The Quickstart requires only Git, Docker Engine, and Docker Compose v2. It does not require Go, Java, Kubernetes, an external database, or source credentials.

## Feature examples

The repository also provides focused, independently runnable feature examples:

| Directory | What it teaches | Status |
|:--|:--|:--|
| `endpoints/` | Query endpoints, actions, mutations, and templates | Supported |
| `rbac/` | Authentication, authorization, and data policies | Supported |
| `javascript/` | JavaScript data sources, module bundles, and table handlers | Supported |
| `functions/` | SQL functions and custom template functions | Supported |
| `initializer/` | Initialization and scheduled JavaScript behavior | Supported |
| `synthetic-entities/` | Relational projections and mutations over nested document arrays | Supported |

Provider-backed examples use `PROVIDER_GRPC`. A sample may intentionally use a JavaScript adapter when JavaScript itself is the lesson.

## Sample quality contract

Every supported sample must:

- teach one clear Kubling capability;
- run independently against the current public container images;
- state prerequisites, startup, readiness, verification, expected results, and cleanup;
- avoid external credentials and paid infrastructure unless that dependency is the lesson;
- keep generated bundles and runtime state out of Git; and
- include automation appropriate to its scope.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the complete contribution contract.

## Generated artifacts

Descriptor and module bundles are build output. ZIP files, compiled classes, JARs, database files, and runtime state must not be committed.

Supported samples run the official Kubling CLI image to generate descriptor and module bundles inside named Compose volumes. Contributors therefore do not need to install the CLI or a host-language toolchain.

## Compatibility

The default branch tracks the current public Kubling release instead of a fixed release line.

- Compose files use the public `latest` images so the samples continue to follow new Kubling releases.
- CI continuously validates those rolling images against every supported sample.
- Git history and repository release tags preserve older states when a historical sample is needed.

The repository is published as `kubling-community/kubling-samples`, a name that covers both the Quickstart and the advanced feature examples.

## License

Licensed under the [Apache License 2.0](LICENSE).
