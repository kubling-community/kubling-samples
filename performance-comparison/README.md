# Compare Kubling image performance

Use this sample to compare two existing Kubling container images on the same
machine. It answers one practical question:

> With the same SQL workload and resource limits, how does a candidate image
> behave compared with a baseline image?

The runner starts one image at a time, executes the same deterministic queries,
alternates the baseline/candidate order between rounds, and produces a report
with startup, client-side, and engine-side measurements.

## What is this useful for?

Before migrating to a newer Kubling version, if your topology is especially sensible to nano-to-millisecods delays, you shoud consider this experiment
as a part of the migration evaluation process.

## What is measured

| Measurement | What it shows |
|:--|:--|
| Startup to health | Time from `docker run` until `/observe/health` reports `UP` |
| Client-observed query latency | Complete gRPC round trip seen by the official Python client |
| Kubling query duration | Query execution time recorded inside Kubling by Performance Tracer |
| Sequential query rate | Queries per second derived from the client-side measurements |

Client latency includes transport, serialization, and result delivery.
Performance Tracer measures the query lifecycle inside the engine. Reading both
figures together helps distinguish an engine execution change from time spent
outside that execution window.

## How Performance Tracer is used

The sample enables Kubling's Performance Tracer for both images.
Kubling records query start and query end events in a dedicated tracing VDB,
which can be queried.

For each workload query, the runner:

1. Executes the configured warmup iterations
2. Records a trace watermark so warmup and previous events are excluded
3. Measures every execution from the persistent gRPC client
4. Waits until Performance Tracer has no pending or in-flight events
5. Joins the corresponding query start and end events to calculate Kubling's
   internal duration

The raw client and tracer durations remain separate in the generated evidence.
Performance Tracer is enabled identically for both images, so its observation
cost is part of both sides of the comparison.

See [Performance Tracer in the Kubling documentation](https://docs.kubling.com/perf/intro)
for its configuration, event model, and other ways to inspect execution data.

## Requirements

- Bash 3.2 or newer
- Docker Engine or Docker Desktop
- Python 3.10 or newer with `pip`
- `curl`, Git, `jq`, and `sed`
- two existing Kubling images built for the Docker server's architecture

Install the pinned Kubling client from the repository root:

```bash
python3 -m pip install \
  --target performance-comparison/target/client-libs \
  -r performance-comparison/requirements.txt
```

The runner finds that directory automatically. Set
`PERFORMANCE_COMPARE_CLIENT_LIB_DIR` if the packages are installed elsewhere.
Every result records the Python implementation and the resolved versions of
`kubling-sqlalchemy`, `kubling-grpc`, `grpcio`, protobuf, and SQLAlchemy.

The descriptor bundle is generated with the public
`docker.io/kubling/kubling-cli:latest` image. Set `KUBLING_CLI_IMAGE` to use a
different public CLI image.

## Run the comparison

From the repository root:

```bash
./performance-comparison/run-comparison.sh \
  --baseline docker.io/kubling/kubling:TAG_A \
  --candidate docker.io/kubling/kubling:TAG_B \
  --host-label my-test-host
```

Replace the placeholder tags with real image references. The runner pulls both
images and resolves them to immutable image IDs before measuring. Add
`--no-pull` when both images are already loaded locally.

A successful run prints a comparison table and the result directory. Positive
percentages mean that the candidate was faster - negative percentages mean that
it was slower.

For a quick functional check with fewer executions:

```bash
./performance-comparison/run-comparison.sh \
  --baseline IMAGE_A \
  --candidate IMAGE_B \
  --rounds 1 \
  --scale 0.05 \
  --no-pull
```

## Choose the workload

Use `--group` to select one of these groups:

| Group | Queries |
|:--|:--|
| `sql` | Scalar SQL execution and structured JSON expansion with `JSONTABLE` |
| `portable` | Point lookup, grouping, joining, aggregation, and a partitioned window over deterministic portable-local data |
| `all` | Both groups; this is the default |

`--scale` multiplies warmup and measured iteration counts. Every selected query
still executes at least once.

Each container receives two CPUs and 2 GB of memory by default. Change both
limits with `--cpus` and `--memory`. The same limits always apply to the baseline
and candidate.

`--host-label` is optional. It adds a reader-supplied machine label to the report
without collecting the machine's network name.

## Read the result

Results are stored under:

```text
performance-comparison/target/<UTC timestamp>-<pid>/
```

| Artifact | Contents |
|:--|:--|
| `comparison.md` | Human-readable p50, p95, p99, startup, and sequential query-rate comparison |
| `summary.json` | Aggregated measurements and percentage differences |
| `manifest.json` | Immutable image identities, host and Docker context, resource limits, client versions, and runner settings |
| `samples/*/sample.json` | Per-round statistics and raw client/tracer nanosecond values |

The harness does not impose a universal pass/fail threshold. Interpret small
changes across repeated runs and inspect both client and tracer measurements
before drawing a conclusion.

For a useful comparison:

- Run on an otherwise idle host
- Keep image configuration and Docker limits identical
- Use at least four alternating rounds
- Repeat the complete comparison
- Retain the full result directory as evidence

To attribute a difference to a runtime or toolchain change, compare images built
from the same Kubling source revision and configuration. Results collected on
different hosts can show whether a trend repeats, but they are not directly
comparable capacity measurements.

## Networking and cleanup

The runner publishes temporary HTTP and gRPC ports only on the loopback
interface and lets Docker select unused host ports. It waits for
`/observe/health` before beginning a workload.

Containers and temporary Docker volumes are removed after every round and when
the runner exits after an error or interruption. Reports and failure evidence
remain under the ignored `target/` directory until you remove them.

## Validate or extend the sample

Validate the sample definition without starting containers:

```bash
bash scripts/check-performance-comparison.sh
```

To add coverage, edit `workloads.json` and provide a stable query ID, group,
warmup count, measured iteration count, expected minimum rows, and whether the
query requires the portable-local seed data.
