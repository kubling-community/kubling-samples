# Hibernate Sample

> [!WARNING]
> Legacy reference: this sample targets Kubling 24.2.6 and is not validated with Kubling 26.4 or external gRPC providers. Do not use its dependency versions or deployment instructions as a current compatibility contract. Start with the [supported Quickstart](../quickstart/README.md).

Goal
: In this sample project, you will get an idea of how to interact with `Kubling DBVirt` 
from a `SpringBoot` application using `JDBC` Driver
and Hibernate.

Difficulty
: Medium - Requires some basic JPA/Hibernate knowledge.

## How to Test It

Before running tests, navigate to the [vdb](springboot/vdb) directory and execute:
```bash
sh gen-bundles.sh
```

The tests utilize [Testcontainers](https://testcontainers.com), specifically a [Kubling container module](https://central.sonatype.com/artifact/com.kubling/kubling-test-container).
Each test suite configures a Kubling instance with:

- An [`app-config.yaml`](springboot/vdb/app-config.yaml) file.
- A [descriptor.zip](springboot/vdb/descriptor.zip).

We recommend adopting this testing methodology in your own projects, as it has been proven to scale effectively.

In this particular case, the setup combines a `k3s` instance with Kubling. However, your tests can integrate other data sources, such as:
- Postgres
- TimescaleDB
- Azure API
- Your own APIs
- And more...
