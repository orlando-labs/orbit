# Representative CRUD and 72-hour soak test

`examples/soak` is the release-candidate reference workload. It consists of a
controller-based Orbit service backed by the locked ORM/SQLite integration and
an Sputnik `net.http` client. Python is used only to build processes, sample
operating-system resources, and produce evidence; every application request is
generated and checked by the Sputnik client.

## Application contract

`CatalogItem` has 22 persisted attributes: identity, SKU, descriptive,
classification, price, inventory, physical, manufacturer, barcode, variant,
rating, tags, metadata, optimistic-lock version, and timestamps. The service
provides:

- `GET /v1/items` and `POST /v1/items`;
- `GET`, `PUT`, `PATCH`, and `DELETE /v1/items/:id`;
- liveness, readiness, bounded metrics, and authenticated graceful shutdown;
- strict JSON/query schemas, domain validation, body limits, Host
  authorization, optimistic `If-Match`, unique SKU handling, and structured
  4xx problems;
- a bounded SQLite connection pool with WAL and production-shaped server
  limits.

The handlers are ordinary `orbit.Controller` methods. Bare `params`, `request`,
`render`, and `service` are lexical-first dynamic nullary sends to the
controller receiver; the example intentionally exercises that Sputnik language
contract instead of spelling Python-like `self.*` throughout.

Strong-parameter schemas own transport shape and type checks. Catalog domain
constraints are declared on the ORM model and flow through structured
`orm.ValidationError` issues into the 422 response details.

Each mixed client iteration performs create, show, filtered list, full replace,
partial update, delete, and post-delete verification. At its configured
interval it also executes the complete negative contract:

- media type, malformed JSON, wrong root, missing required fields, wrong types,
  and unknown top-level/nested fields;
- every declared item-domain validation, including SKU, text bounds,
  enumerations, numeric ranges, country/currency/barcode formats, tags, and
  metadata;
- request-size, unique-SKU, optimistic-lock, empty/unknown patch, typed path,
  query allowlist, unsupported method, Host authorization, missing resources,
  and delete precondition failures.

The client asserts the exact expected status for every request and exits
nonzero on the first mismatch. All deliberately invalid cases expect a 4xx
status; unexpected 5xx responses therefore fail the run immediately.

## Fast gate

From a clean checkout:

```sh
./script/soak smoke
```

This resolves the exact revisions in `release/dependencies.lock.json`, builds
both Sputnik programs without cache, starts the service, runs one full CRUD/4xx
cycle, verifies idle metrics, and performs graceful shutdown. CI runs this gate
on the ORM/SQLite integration row.

Both programs are built with `--target native --require-full-native`. The gate
fails unless `native_graph_full_coverage` is true and both VM-bridge and
fallback code-object counts are zero for the complete service and client
graphs.

For an already resolved local dependency tree:

```sh
ORBIT_LOCAL_SOURCE_ROOT=/path/to/dependency-source ./script/soak smoke
```

## 72-hour qualification

Run on a production-equivalent host with a persistent artifact directory:

```sh
./script/soak run \
  --duration 72h \
  --clients 4 \
  --server-workers 4 \
  --pool-size 8 \
  --artifacts /var/lib/orbit-evidence/soak-1.0.0-rc.1
```

The default duration is already `72h`. During the run the orchestrator records
RSS, physical footprint on Darwin, descriptor and thread counts for both the
service and every load client, readiness, the full Orbit metrics snapshot,
source and dependency revisions, a canonical configuration digest, and binary
digests. After traffic stops, it checks that connections, requests, streams,
pool leases, and pool waiters quiesce, then uses the service's authenticated
graceful-shutdown endpoint.

The output directory contains:

- `run.json`: immutable inputs and provenance;
- `samples.jsonl`: timestamped resource and application metrics;
- `report.json`: aggregate traffic, thresholds, slopes, checks, and verdict;
- separate stdout/stderr logs for the service and every Sputnik client;
- the exact service/client binaries and SQLite database used by the run.

`report.json` sets `qualifies_as_72h_evidence` only when the run passed and the
shortest-lived Sputnik worker itself reached at least 259,200 seconds. The source
tree must also have no tracked or staged changes. Untracked local files and soak
artifacts are recorded in `run.json` but do not disqualify evidence because they
cannot change the committed source revision. A dirty tracked-tree run remains
useful diagnostics but cannot qualify as release evidence. A shorter
`--duration 10m` run is useful operational rehearsal but cannot be mistaken for
release evidence.

Default post-warmup per-process limits are 1 GiB peak RSS and physical
footprint, 4 MiB/hour memory slope, 512 file descriptors, 512 threads, and
0.25/hour descriptor and thread slopes. Client aggregates scale the maxima by
the configured client count while still enforcing each per-process maximum.
On Darwin, physical footprint is the memory qualification metric; `ps` RSS is
retained as diagnostic evidence because it includes resident pages that
libmalloc has already made reclaimable. On other platforms RSS is the memory
qualification metric.
They are intentionally explicit CLI options rather than hidden heuristics. A
release manager may tighten them for the named runner, but relaxing them
requires a reviewed evidence note.

This test supplies the application and reproducible 72-hour evidence format.
It does not by itself close the separate reverse-proxy canary, 24-hour
coverage-guided fuzzing, failure matrix, cryptographic review, or rollback
rehearsal gates.
