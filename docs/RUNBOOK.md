# Ember operations runbook

This runbook covers Ember 1.0 behind the trusted edge in
[DEPLOYMENT.md](DEPLOYMENT.md). Replace example service names and paths, but do
not remove the trust, limit, readiness, or drain invariants.

## Pre-deployment

1. Verify the image/source revision, `VERSION`, dependency-lock digest, and
   artifact checksum against the release evidence.
2. Review the non-secret configuration diff using
   [CONFIGURATION.md](CONFIGURATION.md). Confirm exact hosts, proxy CIDRs/hops,
   capacity, pools, timeouts, body limits, and shutdown grace.
3. Confirm secrets are present in the secret manager and that current/previous
   keys match the planned rotation window.
4. Run database migrations/backups using the application's own transaction and
   compatibility plan before shifting traffic.
5. Start one canary, wait for readiness, exercise buffered and streaming
   probes through the real edge, and check logs/metrics/traces for redaction.

## Normal rollout and shutdown

The process adapter handles the platform termination signal in this order:

1. mark the instance unready and wait for readiness propagation;
2. call `ServerHandle#stop_accepting`;
3. call `shutdown` with the configured deadline and then `wait`;
4. exit zero only when `shutdown` reports a clean drain.

The platform grace period must exceed propagation plus Ember drain plus stop
hooks. A forced deadline increments `forced_shutdowns`, emits lifecycle
telemetry, and exits non-zero; it is an incident signal, not a normal rollout.

## Triage

| Symptom | First evidence | Immediate safe action |
|---|---|---|
| Readiness 503 | integration readiness, pool gauges, startup event | Stop promotion; keep failed instance out of service; inspect dependency health. |
| Elevated 5xx | `ember.error` type, route template, trace ID | Roll back if correlated with release; never enable exception exposure in production. |
| Overload 503 | rejection/capacity/active metrics, edge queue | Shed/rate-limit at edge; scale within tested bounds; do not add an unbounded queue. |
| Latency regression | route-template histogram and pool waiting | Compare release baseline, dependency time, and saturation; disable the canary. |
| Streaming stalls | active streams, write timeouts, edge buffering | Stop new streaming traffic; verify proxy buffering/timeouts and disconnect propagation. |
| Memory/descriptor growth | RSS, heap/live bytes, connections/tasks/series | Drain the suspect instance; preserve diagnostics; rollback rather than repeatedly hard-killing. |
| Suspected secret/log leak | sink/exporter sample and access control | Restrict access, stop affected exporter, rotate credentials, follow the security-report process. |

Never log raw requests to diagnose an incident. Use request ID, route template,
bounded error type, trace ID, and platform connection metadata.

## Rollback

1. Stop promotion and mark new instances unready.
2. Re-deploy the last artifact whose checksum, lock, config schema, database
   compatibility, and session-envelope version are in the evidence index.
3. Drain new instances normally; hard kill only after the platform deadline.
4. Verify readiness, error/rejection rate, session decode, and representative
   reads/writes through the edge.
5. Record recovery time and preserve the failed artifact/config digest.

Rollback is unsafe after a destructive data migration or removal of all old
session keys. Applications use expand/migrate/contract database changes and
retain read-side session keys through the rollback window.

## Backup and restore

Ember core is stateless and owns no backup format. Back up application data,
configuration metadata, release evidence, and secret versions using the
storage engine's supported online-backup procedure. For SQLite, do not copy
only the main file while WAL writes are active; use SQLite's backup API or a
coordinated checkpoint/snapshot. Upload/object storage has its own versioning,
integrity, and malware-response plan.

Restore rehearsals verify schema version, checksums, foreign keys, application
read/write behavior, and rollback compatibility on an isolated environment.
Never test restore by overwriting the only production copy.

## Incident closeout

- Link request/trace IDs and immutable release evidence without sensitive
  payloads.
- Convert every parser, lifecycle, cancellation, or security regression into a
  permanent corpus test.
- Update the threat model, runbook, budgets, or compatibility matrix when an
  assumption changed.
- Treat unexplained forced shutdown, memory growth, conformance failure, or a
  critical/high finding as a release blocker.
