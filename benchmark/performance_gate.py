#!/usr/bin/env python3
"""Compare Orbit benchmark results to absolute budgets and an approved baseline."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def load(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def workloads(documents: list[dict]) -> dict:
    merged: dict = {}
    for document in documents:
        merged.update(document.get("workloads", {}))
    return merged


def resources(documents: list[dict]) -> dict:
    return {
        "max_rss_mb": max(document.get("resources", {}).get("max_rss_mb", 0) for document in documents),
        "cpu_utilization_percent": max(
            document.get("resources", {}).get("cpu_utilization_percent", 0)
            for document in documents
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--current", type=Path, action="append", required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--budgets", type=Path, required=True)
    args = parser.parse_args()

    current_documents = [load(path) for path in args.current]
    baseline_document = load(args.baseline)
    current = workloads(current_documents)
    baseline = workloads([baseline_document])
    current_resources = resources(current_documents)
    baseline_resources = resources([baseline_document])
    budgets = load(args.budgets)
    threshold = budgets["regression_threshold_percent"] / 100.0
    checks: list[dict] = []

    for name, budget in budgets["workloads"].items():
        if name not in current or name not in baseline:
            checks.append({"workload": name, "status": "fail", "reason": "missing result"})
            continue
        observed = current[name]
        approved = baseline[name]
        failures: list[str] = []
        for percentile in ("p50_us", "p95_us", "p99_us"):
            if observed[percentile] > budget[percentile]:
                failures.append(f"{percentile} exceeds absolute budget")
            if observed[percentile] > approved[percentile] * (1.0 + threshold):
                failures.append(f"{percentile} regressed by more than 10%")
        minimum = budget["min_throughput_per_second"]
        if observed["throughput_per_second"] < minimum:
            failures.append("throughput is below absolute budget")
        if observed["throughput_per_second"] < approved["throughput_per_second"] / (1.0 + threshold):
            failures.append("throughput regressed by more than 10%")
        if name == "orm_pool_exhaustion" and observed.get("rejected") != observed["iterations"]:
            failures.append("ORM exhaustion workload did not reject every contended checkout")
        checks.append({
            "workload": name,
            "status": "fail" if failures else "pass",
            "failures": failures,
        })

    resource_failures: list[str] = []
    resource_budgets = budgets["resources"]
    if current_resources["max_rss_mb"] > resource_budgets["max_rss_mb"]:
        resource_failures.append("peak RSS exceeds absolute budget")
    if current_resources["max_rss_mb"] > baseline_resources["max_rss_mb"] * (1.0 + threshold):
        resource_failures.append("peak RSS regressed by more than 10%")
    if current_resources["cpu_utilization_percent"] > resource_budgets["max_cpu_utilization_percent"]:
        resource_failures.append("CPU utilization exceeds absolute budget")
    checks.append({
        "workload": "process_resources",
        "status": "fail" if resource_failures else "pass",
        "failures": resource_failures,
    })

    result = {
        "schema": "orbit.performance-gate.v1",
        "status": "fail" if any(item["status"] == "fail" for item in checks) else "pass",
        "regression_threshold_percent": budgets["regression_threshold_percent"],
        "checks": checks,
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 1 if result["status"] == "fail" else 0


if __name__ == "__main__":
    sys.exit(main())
