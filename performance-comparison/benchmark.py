#!/usr/bin/env python3
"""Execute and compare deterministic Kubling performance workloads."""

from __future__ import annotations

import argparse
import datetime as dt
import http.client
import json
import math
import statistics
import sys
import time
import urllib.parse
from pathlib import Path
from typing import Any


FORMAT = "kubling-performance-workloads"
SAMPLE_FORMAT = "kubling-performance-sample"
SUMMARY_FORMAT = "kubling-performance-summary"
MAIN_VDB = "PerformanceComparisonVDB"
TRACER_VDB = "PerfTracerVDB"


def fail(message: str) -> None:
    raise RuntimeError(message)


def positive_int(value: Any, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        fail(f"{field} must be a positive integer")
    return value


def load_workloads(path: Path, group: str, scale: float) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("format") != FORMAT or data.get("formatVersion") != 1:
        fail(f"Unsupported workload catalog: {path}")
    if not math.isfinite(scale) or scale <= 0:
        fail("--scale must be greater than zero")

    groups = data.get("groups")
    if not isinstance(groups, list) or not groups:
        fail("Workload catalog must define a non-empty groups array")
    group_ids = [item.get("id") for item in groups]
    if len(group_ids) != len(set(group_ids)):
        fail("Workload group IDs must be unique")
    if group != "all" and group not in group_ids:
        fail(f"Unknown workload group: {group}")

    selected: list[dict[str, Any]] = []
    query_ids: set[str] = set()
    for group_definition in groups:
        group_id = group_definition.get("id")
        if not isinstance(group_id, str) or not group_id:
            fail("Each workload group requires a non-empty id")
        if group != "all" and group_id != group:
            continue
        queries = group_definition.get("queries")
        if not isinstance(queries, list) or not queries:
            fail(f"Workload group {group_id} requires queries")
        for query in queries:
            query_id = query.get("id")
            sql = query.get("sql")
            if not isinstance(query_id, str) or not query_id:
                fail(f"Workload group {group_id} contains a query without an id")
            if query_id in query_ids:
                fail(f"Duplicate workload query id: {query_id}")
            query_ids.add(query_id)
            if not isinstance(sql, str) or not sql.strip():
                fail(f"Workload query {query_id} requires SQL")
            warmups = positive_int(query.get("warmups"), f"{query_id}.warmups")
            iterations = positive_int(query.get("iterations"), f"{query_id}.iterations")
            min_rows = positive_int(query.get("minRows", 1), f"{query_id}.minRows")
            selected.append(
                {
                    "id": query_id,
                    "group": group_id,
                    "sql": sql.strip(),
                    "warmups": max(1, round(warmups * scale)),
                    "iterations": max(1, round(iterations * scale)),
                    "minRows": min_rows,
                    "requiresSeed": bool(group_definition.get("requiresSeed", False)),
                }
            )
    if not selected:
        fail("No workload queries were selected")
    return data, selected


class KublingControlClient:
    def __init__(self, base_url: str) -> None:
        parsed = urllib.parse.urlparse(base_url)
        if parsed.scheme != "http" or not parsed.hostname or not parsed.port:
            fail(f"Expected an http URL with an explicit port: {base_url}")
        self.host = parsed.hostname
        self.port = parsed.port
        self.headers = {"Connection": "keep-alive"}
        self.connection = self._new_connection()

    def _new_connection(self) -> http.client.HTTPConnection:
        return http.client.HTTPConnection(self.host, self.port, timeout=60)

    def close(self) -> None:
        self.connection.close()

    def _request_json(self, path: str) -> dict[str, Any]:
        for attempt in range(2):
            try:
                self.connection.request("GET", path, headers=self.headers)
                response = self.connection.getresponse()
                body = response.read().decode("utf-8", errors="replace")
                if response.status >= 400:
                    fail(f"HTTP {response.status} for {path}: {body}")
                value = json.loads(body)
                if not isinstance(value, dict):
                    fail(f"Expected a JSON object from {path}")
                return value
            except (http.client.RemoteDisconnected, ConnectionResetError, BrokenPipeError):
                self.connection.close()
                self.connection = self._new_connection()
                if attempt == 1:
                    raise
        fail(f"Request failed: {path}")

    def wait_for_tracer_idle(self, timeout_seconds: float = 45) -> dict[str, Any]:
        deadline = time.monotonic() + timeout_seconds
        last: dict[str, Any] = {}
        while time.monotonic() < deadline:
            last = self._request_json("/api/v1/admin/perftracer/status")
            if (
                last.get("enabled") is True
                and last.get("idle") is True
                and last.get("pendingEvents") == 0
                and last.get("inFlightEvents") == 0
            ):
                return last
            time.sleep(0.1)
        fail(f"Performance tracer did not become idle: {last}")


class KublingGrpcClient:
    def __init__(self, grpc_target: str, control_url: str) -> None:
        try:
            from kubling_sqlalchemy import dbapi
        except ImportError as error:
            raise RuntimeError(
                "The Kubling gRPC client is not installed. Run: "
                "python3 -m pip install --target "
                "performance-comparison/target/client-libs "
                "-r performance-comparison/requirements.txt"
            ) from error

        self.control = KublingControlClient(control_url)
        self.connections: dict[str, Any] = {}
        try:
            for vdb in (MAIN_VDB, TRACER_VDB):
                self.connections[vdb] = dbapi.connect(
                    endpoint=grpc_target,
                    vdb_name=vdb,
                    username="performance-comparison",
                    password="performance-comparison",
                    tls=None,
                    connect_timeout_seconds=30,
                    rpc_timeout_seconds=60,
                    application_name="kubling-performance-comparison",
                    autocommit=True,
                )
        except Exception:
            self.close()
            raise

    def close(self) -> None:
        for connection in reversed(tuple(self.connections.values())):
            try:
                connection.close()
            except Exception:
                pass
        self.connections.clear()
        self.control.close()

    def query(self, vdb: str, sql: str) -> dict[str, Any]:
        connection = self.connections.get(vdb)
        if connection is None:
            fail(f"No gRPC session is open for VDB {vdb}")

        cursor = connection.cursor()
        try:
            cursor.execute(sql)
            if cursor.description is None:
                return {"containsRows": False, "rows": []}
            columns = [column.name.lower() for column in cursor.description]
            rows = [dict(zip(columns, row, strict=True)) for row in cursor.fetchall()]
            return {"containsRows": True, "rows": rows}
        finally:
            cursor.close()

    def wait_for_tracer_idle(self, timeout_seconds: float = 45) -> dict[str, Any]:
        return self.control.wait_for_tracer_idle(timeout_seconds)


def sql_string(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def seed_portable_data(client: KublingGrpcClient, catalog: dict[str, Any]) -> None:
    seed = catalog.get("seed", {})
    customer_count = positive_int(seed.get("customers", 32), "seed.customers")
    orders_per_customer = positive_int(seed.get("ordersPerCustomer", 8), "seed.ordersPerCustomer")
    regions = ["EU", "US", "APAC", "LATAM"]
    statuses = ["PAID", "PENDING", "CANCELLED"]

    client.query(MAIN_VDB, "DELETE FROM local.ORDERS")
    client.query(MAIN_VDB, "DELETE FROM local.CUSTOMERS")
    for customer_id in range(1, customer_count + 1):
        region = regions[(customer_id - 1) % len(regions)]
        client.query(
            MAIN_VDB,
            "INSERT INTO local.CUSTOMERS (id, name, region) "
            f"VALUES ({customer_id}, 'customer-{customer_id:03d}', '{region}')",
        )

    order_id = 1
    for customer_id in range(1, customer_count + 1):
        for order_offset in range(orders_per_customer):
            amount_cents = 500 + ((order_id * 137) % 20_000)
            amount = f"{amount_cents // 100}.{amount_cents % 100:02d}"
            status = statuses[(customer_id + order_offset) % len(statuses)]
            client.query(
                MAIN_VDB,
                "INSERT INTO local.ORDERS (id, customer_id, amount, status) "
                f"VALUES ({order_id}, {customer_id}, {amount}, '{status}')",
            )
            order_id += 1


def validate_query_result(result: dict[str, Any], query: dict[str, Any]) -> None:
    rows = result.get("rows")
    if result.get("containsRows") is not True or not isinstance(rows, list):
        fail(f"Workload query {query['id']} did not return rows")
    if len(rows) < query["minRows"]:
        fail(
            f"Workload query {query['id']} returned {len(rows)} rows; "
            f"expected at least {query['minRows']}"
        )


def percentile(values: list[int], quantile: float) -> float:
    ordered = sorted(values)
    index = max(0, math.ceil(quantile * len(ordered)) - 1)
    return float(ordered[index])


def duration_stats(values: list[int]) -> dict[str, Any]:
    if not values:
        fail("Cannot calculate statistics for an empty duration list")
    total = sum(values)
    return {
        "count": len(values),
        "minMillis": min(values) / 1_000_000,
        "meanMillis": statistics.fmean(values) / 1_000_000,
        "p50Millis": statistics.median(values) / 1_000_000,
        "p95Millis": percentile(values, 0.95) / 1_000_000,
        "p99Millis": percentile(values, 0.99) / 1_000_000,
        "maxMillis": max(values) / 1_000_000,
        "sequentialQueriesPerSecond": len(values) / (total / 1_000_000_000),
    }


def tracer_watermark(client: KublingGrpcClient, run_id: str) -> int:
    result = client.query(
        TRACER_VDB,
        "SELECT MAX(TS_NANOS) AS LAST_TS_NANOS "
        "FROM PerfTracer.QUERY_START "
        f"WHERE RUN_ID = {sql_string(run_id)}",
    )
    rows = result.get("rows", [])
    if len(rows) != 1:
        fail(f"Could not read the PerfTracer watermark for run {run_id}")
    value = rows[0].get("last_ts_nanos")
    return int(value) if value is not None else -1


def tracer_durations(client: KublingGrpcClient, run_id: str, after_nanos: int) -> list[int]:
    trace_query = f"""
        SELECT
            QS.TS_NANOS AS STARTED_NANOS,
            (QE.TS_NANOS - QS.TS_NANOS) AS DURATION_NANOS,
            QE.SUCCESS AS SUCCESS
        FROM PerfTracer.QUERY_START AS QS
        JOIN PerfTracer.QUERY_END AS QE
          ON QS.QUERY_ID = QE.QUERY_ID
         AND QS.RUN_ID = QE.RUN_ID
        WHERE QS.RUN_ID = {sql_string(run_id)}
          AND QS.TS_NANOS > {after_nanos}
        ORDER BY QS.TS_NANOS
    """.strip()
    result = client.query(TRACER_VDB, trace_query)
    rows = result.get("rows", [])
    durations: list[tuple[int, int]] = []
    for row in rows:
        if str(row.get("success")).lower() != "true":
            fail(f"Performance tracer recorded a failed execution after {after_nanos}")
        durations.append((int(row["started_nanos"]), int(row["duration_nanos"])))
    durations.sort(key=lambda item: item[0])
    return [duration for _, duration in durations]


def execute(args: argparse.Namespace) -> None:
    catalog, queries = load_workloads(Path(args.workloads), args.group, args.scale)
    client = KublingGrpcClient(args.grpc_target, args.control_url)
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    try:
        if any(query["requiresSeed"] for query in queries):
            seed_portable_data(client, catalog)
            client.wait_for_tracer_idle()

        for query in queries:
            for _ in range(query["warmups"]):
                validate_query_result(client.query(MAIN_VDB, query["sql"]), query)
        client.wait_for_tracer_idle()

        query_results: list[dict[str, Any]] = []
        all_external: list[int] = []
        all_internal: list[int] = []
        tracer_status: dict[str, Any] = {}
        for query in queries:
            watermark = tracer_watermark(client, args.run_id)
            external: list[int] = []
            for _ in range(query["iterations"]):
                started = time.perf_counter_ns()
                result = client.query(MAIN_VDB, query["sql"])
                completed = time.perf_counter_ns()
                validate_query_result(result, query)
                external.append(completed - started)

            tracer_status = client.wait_for_tracer_idle()
            internal = tracer_durations(client, args.run_id, watermark)
            if len(internal) != query["iterations"]:
                fail(
                    f"PerfTracer returned {len(internal)} measured executions for {query['id']}; "
                    f"expected {query['iterations']}"
                )
            all_external.extend(external)
            all_internal.extend(internal)
            query_results.append(
                {
                    "id": query["id"],
                    "group": query["group"],
                    "sql": query["sql"],
                    "warmups": query["warmups"],
                    "iterations": query["iterations"],
                    "client": duration_stats(external),
                    "kubling": duration_stats(internal),
                    "rawClientNanos": external,
                    "rawKublingNanos": internal,
                }
            )

        sample = {
            "format": SAMPLE_FORMAT,
            "formatVersion": 1,
            "startedAt": started_at,
            "completedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
            "label": args.label,
            "round": args.round,
            "runId": args.run_id,
            "group": args.group,
            "scale": args.scale,
            "imageReference": args.image_reference,
            "imageId": args.image_id,
            "startupMillis": args.startup_ms,
            "tracerStatus": tracer_status,
            "overall": {
                "client": duration_stats(all_external),
                "kubling": duration_stats(all_internal),
            },
            "queries": query_results,
        }
        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(sample, indent=2) + "\n", encoding="utf-8")
    finally:
        client.close()


def improvement_percent(baseline: float, candidate: float, higher_is_better: bool = False) -> float:
    if baseline == 0:
        return 0.0
    if higher_is_better:
        return (candidate / baseline - 1.0) * 100.0
    return (1.0 - candidate / baseline) * 100.0


def aggregate_samples(samples: list[dict[str, Any]], label: str) -> dict[str, Any]:
    selected = [sample for sample in samples if sample["label"] == label]
    if not selected:
        fail(f"No samples found for {label}")
    image_ids = {sample["imageId"] for sample in selected}
    if len(image_ids) != 1:
        fail(f"{label} samples used multiple image IDs: {sorted(image_ids)}")

    startup_nanos = [int(float(sample["startupMillis"]) * 1_000_000) for sample in selected]
    query_ids = [query["id"] for query in selected[0]["queries"]]
    query_aggregates: list[dict[str, Any]] = []
    all_external: list[int] = []
    all_internal: list[int] = []
    for query_id in query_ids:
        external: list[int] = []
        internal: list[int] = []
        group = ""
        for sample in selected:
            matches = [query for query in sample["queries"] if query["id"] == query_id]
            if len(matches) != 1:
                fail(f"Sample {sample['runId']} does not contain query {query_id} exactly once")
            query = matches[0]
            group = query["group"]
            external.extend(int(value) for value in query["rawClientNanos"])
            internal.extend(int(value) for value in query["rawKublingNanos"])
        all_external.extend(external)
        all_internal.extend(internal)
        query_aggregates.append(
            {
                "id": query_id,
                "group": group,
                "client": duration_stats(external),
                "kubling": duration_stats(internal),
            }
        )

    return {
        "label": label,
        "imageReference": selected[0]["imageReference"],
        "imageId": selected[0]["imageId"],
        "rounds": len(selected),
        "startup": duration_stats(startup_nanos),
        "overall": {
            "client": duration_stats(all_external),
            "kubling": duration_stats(all_internal),
        },
        "queries": query_aggregates,
    }


def comparison_row(baseline: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    return {
        "baseline": baseline,
        "candidate": candidate,
        "candidateImprovementPercent": improvement_percent(
            float(baseline["p50Millis"]), float(candidate["p50Millis"])
        ),
        "candidateP95ImprovementPercent": improvement_percent(
            float(baseline["p95Millis"]), float(candidate["p95Millis"])
        ),
        "candidateP99ImprovementPercent": improvement_percent(
            float(baseline["p99Millis"]), float(candidate["p99Millis"])
        ),
        "candidateThroughputImprovementPercent": improvement_percent(
            float(baseline["sequentialQueriesPerSecond"]),
            float(candidate["sequentialQueriesPerSecond"]),
            higher_is_better=True,
        ),
    }


def markdown(summary: dict[str, Any]) -> str:
    baseline = summary["baseline"]
    candidate = summary["candidate"]
    manifest = summary["manifest"]
    host = manifest["host"]
    docker = manifest["docker"]
    limits = manifest["limits"]
    host_name = host.get("label") or "unlabeled host"
    cpu_model = host.get("cpuModel") or "not reported"
    lines = [
        "# Kubling image performance comparison",
        "",
        f"- Baseline: `{baseline['imageReference']}` (`{baseline['imageId']}`)",
        f"- Candidate: `{candidate['imageReference']}` (`{candidate['imageId']}`)",
        f"- Host: {host_name}; {host['architecture']}; {cpu_model}",
        f"- Docker: {docker['serverVersion']} on {docker['operatingSystem']}",
        f"- Container limits: {limits['cpus']} CPUs, {limits['memory']} memory",
        f"- Workload: {manifest['group']} at scale {manifest['scale']}",
        f"- Rounds per image: {baseline['rounds']}",
        "- Positive percentages mean the candidate was faster.",
        "",
        "| Metric | Baseline p50 (ms) | Candidate p50 (ms) | p50 faster | p95 faster | p99 faster |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    startup = summary["comparison"]["startup"]
    client = summary["comparison"]["overallClient"]
    kubling = summary["comparison"]["overallKubling"]
    lines.extend(
        [
            f"| Startup to health | {startup['baseline']['p50Millis']:.3f} | "
            f"{startup['candidate']['p50Millis']:.3f} | "
            f"{startup['candidateImprovementPercent']:+.2f}% | "
            f"{startup['candidateP95ImprovementPercent']:+.2f}% | "
            f"{startup['candidateP99ImprovementPercent']:+.2f}% |",
            f"| Client-observed query latency | {client['baseline']['p50Millis']:.3f} | "
            f"{client['candidate']['p50Millis']:.3f} | "
            f"{client['candidateImprovementPercent']:+.2f}% | "
            f"{client['candidateP95ImprovementPercent']:+.2f}% | "
            f"{client['candidateP99ImprovementPercent']:+.2f}% |",
            f"| Kubling-recorded query duration | {kubling['baseline']['p50Millis']:.3f} | "
            f"{kubling['candidate']['p50Millis']:.3f} | "
            f"{kubling['candidateImprovementPercent']:+.2f}% | "
            f"{kubling['candidateP95ImprovementPercent']:+.2f}% | "
            f"{kubling['candidateP99ImprovementPercent']:+.2f}% |",
            "",
            "## Sequential query rate",
            "",
            "| Baseline (queries/s) | Candidate (queries/s) | Candidate higher |",
            "| ---: | ---: | ---: |",
            f"| {client['baseline']['sequentialQueriesPerSecond']:.2f} | "
            f"{client['candidate']['sequentialQueriesPerSecond']:.2f} | "
            f"{client['candidateThroughputImprovementPercent']:+.2f}% |",
            "",
            "## Per-query comparison",
            "",
            "| Group | Query | Client p50 baseline/candidate (ms) | Client p50/p95/p99 faster | "
            "Kubling p50 baseline/candidate (ms) | Kubling p50/p95/p99 faster |",
            "| --- | --- | ---: | ---: | ---: | ---: |",
        ]
    )
    for item in summary["comparison"]["queries"]:
        client_row = item["client"]
        kubling_row = item["kubling"]
        lines.append(
            f"| {item['group']} | {item['id']} | "
            f"{client_row['baseline']['p50Millis']:.3f} / {client_row['candidate']['p50Millis']:.3f} | "
            f"{client_row['candidateImprovementPercent']:+.2f}% / "
            f"{client_row['candidateP95ImprovementPercent']:+.2f}% / "
            f"{client_row['candidateP99ImprovementPercent']:+.2f}% | "
            f"{kubling_row['baseline']['p50Millis']:.3f} / {kubling_row['candidate']['p50Millis']:.3f} | "
            f"{kubling_row['candidateImprovementPercent']:+.2f}% / "
            f"{kubling_row['candidateP95ImprovementPercent']:+.2f}% / "
            f"{kubling_row['candidateP99ImprovementPercent']:+.2f}% |"
        )
    lines.extend(
        [
            "",
            "This compares complete container images on one host. It is not an absolute capacity result. "
            "To attribute a difference to one runtime or toolchain change, build both images from the "
            "same Kubling source revision and configuration.",
            "",
        ]
    )
    return "\n".join(lines)


def terminal_winner(improvement: float) -> str:
    displayed = round(improvement, 2)
    if displayed > 0:
        return f"candidate faster by {displayed:.2f}%"
    if displayed < 0:
        return f"baseline faster by {abs(displayed):.2f}%"
    return "tie"


def terminal_duration_unit(comparison: dict[str, Any]) -> tuple[float, str]:
    values = [
        float(comparison[side][percentile])
        for side in ("baseline", "candidate")
        for percentile in ("p50Millis", "p95Millis", "p99Millis")
    ]
    largest = max(values)
    if largest < 0.001:
        return 1_000_000.0, "ns"
    if largest < 1:
        return 1_000.0, "us"
    return 1.0, "ms"


def terminal_metric(label: str, comparison: dict[str, Any], indent: str = "  ") -> list[str]:
    baseline = comparison["baseline"]
    candidate = comparison["candidate"]
    scale, unit = terminal_duration_unit(comparison)
    return [
        f"{indent}{label}",
        f"{indent}  baseline -> candidate ({unit}; lower is better)",
        f"{indent}  p50  {baseline['p50Millis'] * scale:>10.3f} -> "
        f"{candidate['p50Millis'] * scale:>10.3f} {unit}  | "
        f"{terminal_winner(comparison['candidateImprovementPercent'])}",
        f"{indent}  p95  {baseline['p95Millis'] * scale:>10.3f} -> "
        f"{candidate['p95Millis'] * scale:>10.3f} {unit}  | "
        f"{terminal_winner(comparison['candidateP95ImprovementPercent'])}",
        f"{indent}  p99  {baseline['p99Millis'] * scale:>10.3f} -> "
        f"{candidate['p99Millis'] * scale:>10.3f} {unit}  | "
        f"{terminal_winner(comparison['candidateP99ImprovementPercent'])}",
    ]


def terminal(summary: dict[str, Any]) -> str:
    baseline = summary["baseline"]
    candidate = summary["candidate"]
    manifest = summary["manifest"]
    host = manifest["host"]
    docker = manifest["docker"]
    limits = manifest["limits"]
    host_name = host.get("label") or "unlabeled host"
    cpu_model = host.get("cpuModel") or "not reported"

    lines = [
        "Kubling image performance comparison",
        "====================================",
        "",
        "Images",
        f"  baseline   {baseline['imageReference']}",
        f"             {baseline['imageId'][:19]}",
        f"  candidate  {candidate['imageReference']}",
        f"             {candidate['imageId'][:19]}",
        "",
        "Environment",
        f"  host       {host_name}",
        f"  system     {host['architecture']}; {cpu_model}",
        f"  Docker     {docker['serverVersion']} on {docker['operatingSystem']}",
        f"  limits     {limits['cpus']} CPUs, {limits['memory']} memory",
        f"  workload   {manifest['group']}; scale {manifest['scale']}; "
        f"{baseline['rounds']} rounds per image",
        "",
        "Overall",
    ]
    lines.extend(terminal_metric("Startup to health", summary["comparison"]["startup"]))
    lines.extend(
        terminal_metric(
            "Client-observed query latency", summary["comparison"]["overallClient"]
        )
    )
    lines.extend(
        terminal_metric(
            "Kubling-recorded query duration", summary["comparison"]["overallKubling"]
        )
    )
    client = summary["comparison"]["overallClient"]
    lines.extend(
        [
            "  Sequential query rate",
            "    baseline -> candidate (queries/s; higher is better)",
            f"    {client['baseline']['sequentialQueriesPerSecond']:>10.2f} -> "
            f"{client['candidate']['sequentialQueriesPerSecond']:>10.2f} queries/s  | "
            f"{terminal_winner(client['candidateThroughputImprovementPercent'])}",
            "",
            "Per query",
        ]
    )
    for item in summary["comparison"]["queries"]:
        lines.append(f"  {item['group']} / {item['id']}")
        lines.extend(terminal_metric("client", item["client"], indent="    "))
        lines.extend(terminal_metric("Kubling", item["kubling"], indent="    "))

    lines.extend(
        [
            "",
            "This compares complete images on one host; it is not an absolute capacity result.",
        ]
    )
    return "\n".join(lines)


def compare(args: argparse.Namespace) -> None:
    samples = [json.loads(Path(path).read_text(encoding="utf-8")) for path in args.samples]
    if any(sample.get("format") != SAMPLE_FORMAT for sample in samples):
        fail("One or more input files are not Kubling performance samples")
    baseline = aggregate_samples(samples, "baseline")
    candidate = aggregate_samples(samples, "candidate")
    if baseline["rounds"] != candidate["rounds"]:
        fail("Baseline and candidate must have the same number of rounds")

    candidate_queries = {item["id"]: item for item in candidate["queries"]}
    query_comparisons: list[dict[str, Any]] = []
    for baseline_query in baseline["queries"]:
        candidate_query = candidate_queries.get(baseline_query["id"])
        if candidate_query is None:
            fail(f"Candidate is missing query {baseline_query['id']}")
        query_comparisons.append(
            {
                "id": baseline_query["id"],
                "group": baseline_query["group"],
                "client": comparison_row(baseline_query["client"], candidate_query["client"]),
                "kubling": comparison_row(baseline_query["kubling"], candidate_query["kubling"]),
            }
        )

    manifest_path = Path(args.manifest)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    completed_at = dt.datetime.now(dt.timezone.utc).isoformat()
    manifest.update({"completedAt": completed_at, "result": "passed"})
    summary = {
        "format": SUMMARY_FORMAT,
        "formatVersion": 1,
        "generatedAt": completed_at,
        "manifest": manifest,
        "baseline": baseline,
        "candidate": candidate,
        "comparison": {
            "startup": comparison_row(baseline["startup"], candidate["startup"]),
            "overallClient": comparison_row(
                baseline["overall"]["client"], candidate["overall"]["client"]
            ),
            "overallKubling": comparison_row(
                baseline["overall"]["kubling"], candidate["overall"]["kubling"]
            ),
            "queries": query_comparisons,
        },
    }
    Path(args.output_json).write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    Path(args.output_markdown).write_text(markdown(summary), encoding="utf-8")
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(terminal(summary))


def validate(args: argparse.Namespace) -> None:
    load_workloads(Path(args.workloads), args.group, args.scale)


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    commands = root.add_subparsers(dest="command", required=True)

    validate_parser = commands.add_parser("validate")
    validate_parser.add_argument("--workloads", required=True)
    validate_parser.add_argument("--group", default="all")
    validate_parser.add_argument("--scale", type=float, default=1.0)
    validate_parser.set_defaults(handler=validate)

    execute_parser = commands.add_parser("execute")
    execute_parser.add_argument("--grpc-target", required=True)
    execute_parser.add_argument("--control-url", required=True)
    execute_parser.add_argument("--run-id", required=True)
    execute_parser.add_argument("--label", choices=("baseline", "candidate"), required=True)
    execute_parser.add_argument("--round", type=int, required=True)
    execute_parser.add_argument("--group", default="all")
    execute_parser.add_argument("--scale", type=float, default=1.0)
    execute_parser.add_argument("--startup-ms", type=float, required=True)
    execute_parser.add_argument("--image-reference", required=True)
    execute_parser.add_argument("--image-id", required=True)
    execute_parser.add_argument("--workloads", required=True)
    execute_parser.add_argument("--output", required=True)
    execute_parser.set_defaults(handler=execute)

    compare_parser = commands.add_parser("compare")
    compare_parser.add_argument("--manifest", required=True)
    compare_parser.add_argument("--output-json", required=True)
    compare_parser.add_argument("--output-markdown", required=True)
    compare_parser.add_argument("samples", nargs="+")
    compare_parser.set_defaults(handler=compare)
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        args.handler(args)
        return 0
    except Exception as error:
        print(f"Performance comparison failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
