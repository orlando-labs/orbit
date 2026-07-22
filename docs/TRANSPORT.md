# Ember production transport

Status: implemented roadmap stage 2, 2026-07-21.

Ember serves plaintext HTTP/1.1 on the trusted inner hop described in
[DEPLOYMENT.md](DEPLOYMENT.md). TLS, HTTP/2/3, public-edge normalization, and
proxy identity remain out of process. The in-process contract is bounded
keep-alive, predictable overload, and an explicit lifecycle that can drain or
cancel every admitted request.

## Starting and stopping

`App#server` validates configuration, starts integrations in declaration
order, and then binds the listener. It returns an unstarted `ServerHandle`.
`App#start` performs those steps and starts the accept loop asynchronously.
`App#run` is the blocking convenience API.

```amber
server = app.start(
  host: "127.0.0.1",
  port: 3000,
  workers: 2,
  max_concurrent_per_worker: 64,
  idle_timeout: 15.0,
  max_requests_per_connection: 100,
  shutdown_timeout: 30.0,
  overload: :reject)

# On the process shutdown signal:
server.stop_accepting()
clean = server.shutdown()
stats = server.wait()
```

The handle API is:

| Operation | Contract |
|---|---|
| `start(max_requests: null)` | Start the accept loop once and return the handle. |
| `serve(max_requests: null)` | Run the accept loop in the current task and return final stats. |
| `wait()` | Join an asynchronously started server and return final stats. |
| `ready?()` | True only while accepting and every started integration reports ready. |
| `accepting?()` | Report listener admission state without dependency readiness. |
| `stop_accepting()` | Mark unready and close the listener; admitted connections continue. Idempotent. |
| `shutdown(timeout: null)` | Stop admission, drain until the deadline, then cancel remaining request tasks and close their streams. Returns `true` for a clean drain and `false` if the deadline forced cancellation. Idempotent. |
| `in_flight()` | Current admitted requests executing application code. |
| `stats()` | Current connection, request, rejection, capacity, and shutdown counters. |
| `port()`, `local_endpoint()` | Bound listener address, including an ephemeral `port: 0` result. |

Concurrent shutdown calls are serialized. A later caller waits for the first
shutdown and receives its same clean/forced result. Integration stop hooks run
once, after request drain or cancellation has completed.

`max_requests` is a bounded-run/test option. Production shutdown uses the
handle lifecycle instead of a request counter.

## Configuration

| Keyword | Default | Meaning |
|---|---:|---|
| `host` | `"127.0.0.1"` | Listener address. The 1.0 profile keeps this on a trusted inner hop. |
| `port` | `3000` | `0..65535`; zero requests an ephemeral port. |
| `workers` | `1` | Capacity multiplier. |
| `max_concurrent_per_worker` | `32` | Hard admitted-connection capacity per worker. |
| `backlog` | `128` | OS listen backlog. |
| `reuse_addr` | `true` | Listener address reuse. |
| `max_header_bytes` | `65536` | Maximum request-head bytes. |
| `max_body_bytes` | `1048576` | Maximum request content bytes. |
| `read_timeout` | `30.0` | Request read timeout. |
| `write_timeout` | `30.0` | Response write timeout. |
| `idle_timeout` | `15.0` | Time allowed for the next request on a keep-alive connection. |
| `max_requests_per_connection` | `100` | Bounded sequential requests per connection. |
| `shutdown_timeout` | `30.0` | Default graceful-drain deadline. |
| `overload` | `:reject` | Hard-cap behavior; currently only immediate rejection is supported. |

Timeouts accept non-negative `Float` seconds or `Int` milliseconds, following
Amber `net.http` duration conventions. Production values must be finite and
reviewed against edge timeouts. Configuration is rejected before listener bind
when a value has the wrong type/range or an unsupported overload policy.

## Keep-alive and overload

HTTP/1.1 connections are persistent unless either peer requests
`Connection: close`, request framing prevents safe reuse, the per-connection
request limit is reached, the server stops accepting, or an error makes reuse
unsafe. HTTP/1.0 closes by default and is persistent only after an explicit
`Connection: keep-alive` agreement.

Requests on one connection are processed sequentially. Already-buffered
pipelined request bytes are retained for the next parse; pipelining does not
bypass the per-connection count or global capacity.

The hard capacity is `workers * max_concurrent_per_worker` active connections.
When it is full, an accepted excess connection receives a short
`503 Service Unavailable` response and is closed. Ember does not create an
unbounded request task or application queue for rejected work. The edge should
still apply its own earlier connection/rate limits.

## Integration lifecycle

A lifecycle-aware integration subclasses `ember.Integration` in addition to
implementing `around_controller(request, next)`. It may override:

- `start()` — run before listener bind and readiness;
- `attach_server(server)` — bind lifecycle telemetry after the native handle exists;
- `ready?()` — participate in `ServerHandle#ready?`;
- `stop()` — run once in reverse successful-start order after drain/cancel.

The base implementations are safe no-ops (`ready?()` returns `true`). A
duck-typed integration that implements only `around_controller` is not entered
into the lifecycle list.

If startup fails, already-started integrations are stopped in reverse order
and the listener is not exposed. The ORM pool integration rejects a closed
pool during startup and closes its pool during stop. Deadline cancellation
cooperatively unwinds controller `ensure` scopes before stop hooks, so a
request-scoped ORM lease is returned before the pool closes.

## Wire correctness

The application and transport boundaries reject a final informational `1xx`
response. `HEAD` never writes content; buffered responses retain or compute a
hypothetical representation length, and streaming producers are not invoked.
`204` omits content framing, `205` uses zero length, and `304` sends no content
or transfer coding. Application-supplied buffered `Content-Length` must match
content, except that a HEAD value describes the selected representation.

`Transfer-Encoding` and `Trailer` are transport-owned. The parser rejects
missing/duplicate HTTP/1.1 `Host`, ambiguous `Content-Length`/
`Transfer-Encoding`, conflicting lengths, obsolete folded headers, malformed
heads, and bounded-size violations before routing. Chunked full-duplex streams,
trailers, and `Expect: 100-continue` retain their existing contract.

Regression evidence lives in `test/stage2_selftest.am` and the Amber runtime
suite `tests/vm_net_http_tests.cpp`. They cover clean and forced drain,
cancel/unwind, integration ordering, no lost lease, keep-alive/pipelining,
overload, malformed raw requests, and contentless/HEAD framing.
