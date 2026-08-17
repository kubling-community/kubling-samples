# Kubling Samples

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg?style=flat-square)](LICENSE)

Runnable examples for learning Kubling through working code.

Kubling combines several capabilities that solve different problems: provider integration, endpoints, authentication and authorization, JavaScript extensibility, functions, module lifecycle hooks, and synthetic entities. Putting all of them into one large application makes each mechanism harder to identify and understand, so this repository isolates them into small, independent samples.

Start with the Quickstart to see the complete minimal stack, then choose a focused sample for the feature you want to explore. These examples complement the [official Kubling documentation](https://docs.kubling.com), which remains the reference for concepts and configuration.

## Start with the Quickstart

The Quickstart runs Kubling, Kubling Studio, and the official In-memory gRPC provider with Docker Compose.

```bash
cd quickstart
docker compose up --wait
```

Open <http://localhost:8282/console>, or follow the complete [Quickstart guide](quickstart/README.md) to run a deterministic query and mutation.

All samples require only Git, Docker Engine, and Docker Compose v2. They generate their required bundles automatically and do not require a host-language toolchain.

## Explore Kubling features

Each directory answers a specific question:

| Sample | What to explore |
|:--|:--|
| [Quickstart](quickstart/README.md) | How Kubling registers a gRPC provider, imports its schema, queries deterministic data, and executes a mutation |
| [Endpoints](endpoints/README.md) | How query endpoints and actions expose reusable operations over provider data |
| [RBAC](rbac/README.md) | How authentication sources, external-role mappings, and VDB data roles control access |
| [JavaScript data source](javascript/README.md) | How a JavaScript module defines schema, data, and table handlers |
| [Functions](functions/README.md) | How SQL functions and custom template functions are packaged and invoked |
| [Initialization and scheduling](initializer/README.md) | How modules run initialization during bootstrap, report success or failure, and schedule recurring work |
| [Synthetic entities](synthetic-entities/README.md) | How nested document arrays become relational tables and how mutations propagate to their parent document |

## Run a focused sample

Samples are independent and publish Kubling on port `8282`, so run one at a time:

```bash
cd <sample-directory>
docker compose up --wait
```

The sample README explains what to inspect, which query or operation to run, the expected result, and its automated smoke test.

When finished, remove the complete sample stack and its generated bundles:

```bash
docker compose down --volumes --remove-orphans
```

## License

Licensed under the [Apache License 2.0](LICENSE).
