package orbit.stage4_selftest

import orbit
import orbit.testing
import orbit.telemetry
from net.http import Client

export main

def assert(condition, message):
  raise ArgumentError(message) unless condition

def user(request, id):
  orbit.render(json: {"ok": true})

def failure(request):
  raise ValueError("secret failure detail")

def streamed(request):
  orbit.stream() |body|:
    body.write("abc")
    body.write("def")

def metrics(request):
  request.service(:telemetry).metrics.response(request)

class NullStreamBody:
  attr bytes

  def init():
    @bytes = 0
    @closed = false

  def write(data, extensions: null):
    @bytes += if Bytes === data then data.count else data.to_str.bytesize
    self

  def close():
    @closed = true
    self

  def trailer(name, value):
    self

  def finish():
    @closed = true
    self

  def closed?():
    @closed

class BrokenSink:
  def emit(kind, fields):
    raise ValueError("telemetry unavailable")

class FailedAttachIntegration < orbit.Integration:
  def attach_server(server):
    raise ValueError("attach failed")

routes = orbit.routes:
  get "/users/:id", to: &user, params: {id: Str}
  get "/failure", to: &failure
  get "/stream", to: &streamed
  get "/metrics", to: &metrics

def event(events, kind, name):
  events.find |entry|:
    entry["event.kind"] == kind and entry["event.name"] == name

def structured_telemetry():
  sink = telemetry.MemorySink()
  metrics = telemetry.MetricsRegistry(max_series: 16)
  observed = telemetry.Telemetry(sink: sink, metrics: metrics)
  app = orbit.App(routes: routes, telemetry: observed)

  request = testing.get(
    "/users/customer-secret?token=do-not-log",
    headers: {
      "x-request-id": "stage-four-request",
      "authorization": "Bearer do-not-log",
      "cookie": "session=do-not-log",
      "traceparent": "00-invalid"
    })
  response = app.call(request)
  assert(response.status == 200, "instrumented buffered response")
  assert(response.header("x-request-id") == "stage-four-request",
    "telemetry correlates response request id")

  events = sink.snapshot()
  access = event(events, "access", "http.server.request")
  span = event(events, "span", "otel.span")
  assert(access != null and span != null, "access and span events emitted")
  assert(access["http.route"] == "/users/:id", "access uses route template")
  assert(access["http.response.status_code"] == 200, "access status")
  assert(access["http.response.body.size"] > 0, "access response bytes")
  assert(access["duration_ns"] >= 0 and access["outcome"] == "success",
    "access duration and outcome")
  assert(access["request.id"] == "stage-four-request", "access request id")
  assert(span["name"] == "GET /users/:id" and span["kind"] == "SERVER",
    "OpenTelemetry server span name and kind")
  attributes = span["attributes"]
  assert(attributes["http.request.method"] == "GET", "OTel method attribute")
  assert(attributes["http.route"] == "/users/:id", "OTel route attribute")
  assert(attributes["url.scheme"] == "http", "OTel scheme attribute")
  assert(attributes["url.path"] == "[REDACTED]", "trace path is private by default")
  serialized = Json.generate(events)
  assert(not serialized.contains?("customer-secret"), "raw path is absent")
  assert(not serialized.contains?("do-not-log"), "query/header secrets are absent")

  failed = app.call(testing.get("/failure", headers: {"x-request-id": "failed-request"}))
  assert(failed.status == 500, "instrumented error response")
  error_event = sink.snapshot().reversed.find |entry|:
    entry["event.kind"] == "error"
  failed_access = sink.snapshot().reversed.find |entry|:
    entry["event.kind"] == "access" and entry["http.route"] == "/failure"
  assert(error_event != null and error_event["error.type"] == "Exception",
    "structured redacted error event")
  assert(failed_access["outcome"] == "error" and failed_access["http.response.status_code"] == 500,
    "500 access outcome")
  assert(not Json.generate(sink.snapshot()).contains?("secret failure detail"),
    "exception message is not logged")

  streaming_response = app.call(testing.get("/stream"))
  before_stream = metrics.snapshot()
  assert(before_stream["http.server.active_requests"] == 1,
    "stream remains in-flight before producer completes")
  body = NullStreamBody()
  streaming_response._producer_block()(body)
  after_stream = metrics.snapshot()
  assert(body.bytes == 6, "observed stream preserves payload")
  assert(after_stream["http.server.active_requests"] == 0,
    "stream leaves in-flight accounting on completion")
  assert(after_stream["orbit.streams.completed"] == 1,
    "stream completion metric")
  assert(after_stream["http.server.requests"] == 3,
    "request counter covers buffered, error, and stream")
  assert(after_stream["http.server.errors"] == 1, "error counter")
  assert(after_stream["http.server.request.duration"]["count"] == 3,
    "duration histogram count")

  metrics.set_integration_pool("database", active: 2, capacity: 8, waiting: 1)
  pool = metrics.snapshot()["orbit.integration.pools"]["database"]
  assert(pool["active"] == 2 and pool["capacity"] == 8 and pool["waiting"] == 1,
    "bounded integration-pool metrics")
  true

def trace_context_contract():
  valid = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
  parsed = telemetry.TraceContext.parse(valid)
  assert(parsed != null and parsed.trace_id == "4bf92f3577b34da6a3ce929d0e0e4736",
    "W3C traceparent parses")
  assert(telemetry.TraceContext.parse(
    "00-00000000000000000000000000000000-00f067aa0ba902b7-01") == null,
    "all-zero trace id is rejected")
  assert(telemetry.TraceContext.parse("00-invalid") == null,
    "malformed traceparent is rejected")

  sink = telemetry.MemorySink()
  tracer = telemetry.Tracer(sink)
  trusted = orbit.Request(
    method: "GET",
    path: "/private/value",
    headers: {"traceparent": valid},
    trusted_proxy: true,
    effective_scheme: "https",
    effective_authority: "example.test")
  trusted_span = tracer.start_server_span(trusted, "trace-test")
  assert(trusted_span.trace_id == parsed.trace_id,
    "validated context propagates from trusted edge")
  assert(trusted_span.parent_span_id == parsed.parent_id,
    "trusted parent span is linked")
  untrusted = orbit.Request(
    method: "GET",
    path: "/private/value",
    headers: {"traceparent": valid},
    trusted_proxy: false)
  untrusted_span = tracer.start_server_span(untrusted, "trace-test")
  assert(untrusted_span.trace_id != parsed.trace_id,
    "untrusted trace context starts a new trace")
  true

def redaction_and_cardinality():
  sink = telemetry.MemorySink(
    redaction: telemetry.RedactionPolicy(fields: ["request.id"]))
  sink.emit(:access, {"request.id": "secret-id", "safe": "yes"})
  assert(sink.snapshot()[0]["request.id"] == "[REDACTED]",
    "configured field redaction")

  bounded = telemetry.MetricsRegistry(max_series: 1)
  bounded.request_started()
  bounded.request_finished("GET", "/one", 200, 1, 1, "success")
  bounded.request_started()
  bounded.request_finished("POST", "/two", 500, 1, 1, "error")
  series = bounded.snapshot()["orbit.request.series"]
  assert(series.count == 1 and series["__overflow__"] == 2,
    "metric labels overflow into one bounded series")

  histogram = telemetry.MetricsRegistry()
  histogram.request_started()
  histogram.request_finished("GET", "/histogram", 200, 6000000, 1, "success")
  bucket_counts = histogram.snapshot()["http.server.request.duration"]["bucket_counts"]
  assert(bucket_counts[0] == 0 and bucket_counts[1] == 1 and bucket_counts[-1] == 1,
    "duration histogram snapshot exposes cumulative buckets")
  true

def lifecycle_probes():
  sink = telemetry.MemorySink()
  observed = telemetry.Telemetry(sink: sink)
  app = orbit.App(
    routes: routes,
    services: {telemetry: observed},
    telemetry: observed)
  assert(observed.health.liveness().status == 200, "liveness is process-local")
  assert(observed.health.readiness().status == 503, "unattached app is not ready")
  server = app.start(port: 0, idle_timeout: 0.1, shutdown_timeout: 1.0)
  assert(observed.health.readiness().status == 200, "accepting server is ready")
  metrics_response = observed.metrics.response()
  metrics_body = Json.parse(metrics_response.body_text)
  assert(
    metrics_response.status == 200 and
    metrics_body["orbit.server"]["active_requests"] == 0,
    "attached server metrics produce a JSON response")
  loopback_user = Client().get(
    "http://127.0.0.1:#{server.port()}/users/42",
    headers: {"connection": "close"})
  assert(loopback_user.status == 200, "live request populates metrics series")
  loopback_metrics = Client().get(
    "http://127.0.0.1:#{server.port()}/metrics",
    headers: {"connection": "close"})
  loopback_metrics_body = loopback_metrics.body_text
  loopback_metrics_json = Json.parse(loopback_metrics_body)
  assert(
    loopback_metrics.status == 200 and
    loopback_metrics_json["orbit.server"]["active_requests"] == 1 and
    loopback_metrics_json["orbit.request.series"][
      "GET /users/:id 2xx success"] == 1,
    "metrics preserve a series recorded by a different request VM: " +
      loopback_metrics.status.to_str + ":" + loopback_metrics_body)
  server.stop_accepting()
  assert(observed.health.readiness().status == 503, "draining server is not ready")
  assert(server.shutdown(), "probe server drains")
  server.wait()
  metrics = observed.metrics.snapshot()
  assert(metrics["orbit.shutdowns"] == 1, "shutdown metric")
  assert(metrics["orbit.server"][:active_requests] == 0, "server state metrics")
  lifecycle = sink.snapshot().find |entry|:
    entry["event.name"] == "orbit.server.shutdown"
  assert(lifecycle != null and lifecycle["outcome"] == "success",
    "structured lifecycle event")
  true

def telemetry_failure_is_safe():
  broken = telemetry.Telemetry(sink: BrokenSink())
  app = orbit.App(routes: routes, telemetry: broken)
  response = app.call(testing.get("/users/42"))
  assert(response.status == 200, "telemetry sink failure cannot replace response")
  true

def request_derivation_is_isolated():
  request = testing.get("/users/42")
  app = orbit.App(routes: routes, services: {marker: "derived"})
  response = app.call(request)
  assert(response.status == 200, "derived request reaches route target")
  assert(request.effective_scheme == null and request.effective_authority == null,
    "authorization derivation does not mutate source provenance")
  assert(request.routes == null and request.selected_route == null,
    "routing derivation does not mutate source route state")
  assert(request.path_params().empty? and request.services.empty?,
    "routing derivation does not mutate source data")
  true

def attach_failure_unwinds():
  failed = false
  try:
    orbit.App(
      routes: routes,
      integrations: [FailedAttachIntegration()]
    ).server(port: 0)
  rescue ValueError:
    failed = true
  assert(failed, "integration attach failure aborts startup")
  true

def main():
  structured_telemetry()
  trace_context_contract()
  redaction_and_cardinality()
  lifecycle_probes()
  telemetry_failure_is_safe()
  request_derivation_is_isolated()
  attach_failure_unwinds()
  true
