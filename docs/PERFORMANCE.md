# Orbit performance contract

Status: normative stage-4 performance contract, 2026-07-22.

The reproducible suite lives in `benchmark/` and covers small JSON, buffered
HTML, 1K and 4096-route worst-position lookup, application-level request and
response streaming with 4 KiB payloads, HTTP/1.1 keep-alive, and exhausted
single-connection ORM pool checkout.

## Metrics and budgets

Each workload publishes per-operation p50/p95/p99 latency in microseconds and
throughput per second. The environment manifest also fixes the CPU, memory,
OS, compiler, runtime and source revisions. Process peak RSS and CPU budgets
are release-level limits in `benchmark/performance_budgets.json`; the RC runner
records them with the platform resource monitor.

The absolute preview budgets are intentionally wider than the approved
baseline so noisy developer machines produce an actionable report rather than
false precision. A release candidate fails when any required workload:

- exceeds an absolute p50, p95, or p99 budget;
- falls below its absolute throughput budget; or
- regresses by more than 10% from the approved baseline on the named runner.

An accepted exception must identify the cause, before/after profiles, user
impact, owner, and expiry. Silently replacing the baseline is not an accepted
exception.

## Reproduction

```sh
mkdir -p benchmark/results
.build/dependencies/sputnik-lang/build/sputnik build benchmark/core.build.yaml \
  --target native --out-dir out-bench-core --cache-dir cache-bench-core --no-cache \
  --grant net.listen --grant net.connect
./out-bench-core/orbit.benchmark.core > benchmark/results/core.json

.build/dependencies/sputnik-lang/build/sputnik build benchmark/orm_pool.build.yaml \
  --target native --out-dir out-bench-orm --cache-dir cache-bench-orm --no-cache
./out-bench-orm/orbit.benchmark.orm_pool > benchmark/results/orm.json

python3 benchmark/performance_gate.py \
  --current benchmark/results/core.json \
  --current benchmark/results/orm.json \
  --baseline benchmark/baseline.json \
  --budgets benchmark/performance_budgets.json
```

The keep-alive executable needs loopback listen/connect capabilities. Run on an
otherwise idle named host, performance mode enabled, with the same native
compiler. Run at least three suites for a release and use the median result;
retain every raw JSON result. The committed baseline records the initial
stage-4 evidence and must only be updated through review.

`benchmark/results/` contains generated local evidence and is ignored by Git.
Static CI checks the approved baseline against the budgets; the performance gate
above compares a fresh run with that baseline.
