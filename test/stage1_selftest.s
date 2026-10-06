package ember.stage1_selftest

import ember
import ember.testing
from ember.middleware import AccessLogMiddleware, RequestIdMiddleware

export main

error_events = []

def assert(condition, message):
  raise ArgumentError(message) unless condition

def buffered(request):
  ember.Response(
    headers: ember.Headers([
      ["set-cookie", "theme=dark"],
      ["set-cookie", "session=abc"]]),
    body: "buffered")

def streamed(request):
  ember.stream(
    headers: ember.Headers([
      ["set-cookie", "theme=dark"],
      ["set-cookie", "session=abc"]])) |body|:
        body.write("streamed")

def failure(request):
  raise ValueError("private failure detail")

def cancellation(request):
  raise CancelledError("shutdown cancellation")

def isolation_failure(request):
  raise IsolationError("isolation policy")

def lifetime_failure(request):
  raise LifetimeError("fatal runtime state")

def record_error(event):
  error_events.push!(event)

def broken_error_hook(event):
  raise ValueError("reporter failed")

def cancelling_error_hook(event):
  raise CancelledError("reporter cancelled")

routes = ember.routes:
  get "/buffered", to: &buffered, as: :buffered
  get "/streamed", to: &streamed
  get "/failure", to: &failure
  get "/cancel", to: &cancellation
  get "/isolation", to: &isolation_failure
  get "/lifetime", to: &lifetime_failure
  get "/items/:id", to: &buffered, params: {id: Int}, as: :item

def rejects(&block):
  try:
    block()
    false
  rescue InvalidHeaderError:
    true

def propagated(app, path, error_type):
  try:
    app.call(testing.get(path))
    false
  rescue Exception |error|:
    error_type === error

def main():
  headers = ember.Headers([
    ["Set-Cookie", "a=1"],
    ["set-cookie", "b=2"],
    ["Vary", "accept"],
    ["vary", "origin"]])
  assert(headers.first("SET-cookie") == "a=1", "case-insensitive first header")
  assert(headers.all("set-cookie") == ["a=1", "b=2"], "ordered repeated Set-Cookie")
  assert(headers.to_pairs[2][0] == "vary", "canonical header names")
  token_header = ember.Headers({"X-!#$%&'*+.^_`|~": "value"})
  assert(token_header.first("x-!#$%&'*+.^_`|~") == "value", "HTTP token header name")
  base_headers = ember.Headers({"x-base": "one", "x-remove": "old"})
  added_headers = base_headers.add("x-added", "two")
  set_headers = base_headers.set("x-base", "updated")
  deleted_headers = base_headers.delete("x-remove")
  merged_headers = base_headers.merge({"x-base": "merged", "x-new": "three"})
  assert(
    base_headers.first("x-base") == "one" and
    base_headers.first("x-added") == null and
    base_headers.first("x-remove") == "old",
    "header derivation does not mutate source")
  assert(added_headers.first("x-added") == "two", "header add derives pairs")
  assert(set_headers.first("x-base") == "updated", "header set derives pairs")
  assert(deleted_headers.first("x-remove") == null, "header delete derives pairs")
  assert(
    merged_headers.first("x-base") == "merged" and
    merged_headers.first("x-new") == "three",
    "header merge derives pairs")
  base_response = ember.Response(headers: {"x-base": "one"}, body: "payload")
  derived_response = base_response.with_header("x-added", "two")
  assert(base_response.header("x-added") == null,
    "response header derivation does not mutate source")
  assert(
    derived_response.header("x-added") == "two" and
    derived_response.status == base_response.status and
    derived_response.body == base_response.body,
    "response header derivation preserves response state")

  invalid_name = rejects():
    ember.Headers({"bad name": "value"})
  injected_value = rejects():
    ember.Headers({"x-test": "one\r\ntwo"})
  conflicting_length = rejects():
    ember.Headers([
      ["content-length", "1"],
      ["content-length", "2"]])
  ambiguous_framing = rejects():
    ember.Headers([
      ["content-length", "1"],
      ["transfer-encoding", "chunked"]])
  duplicate_host = rejects():
    ember.Headers([["host", "a"], ["Host", "b"]])
  transformed_ambiguous_framing = rejects():
    ember.Headers({"content-length": "1"}).add("transfer-encoding", "chunked")
  transformed_duplicate_host = rejects():
    ember.Headers({"host": "a"}).add("Host", "b")
  transformed_injected_value = rejects():
    ember.Headers().add("x-test", "one\r\ntwo")
  buffered_framing = rejects():
    ember.Response(headers: {"transfer-encoding": "chunked"})
  transformed_buffered_framing = rejects():
    ember.Response(headers: ember.Headers().set("transfer-encoding", "chunked"))
  streaming_framing = rejects():
    ember.stream(headers: {"content-length": "1"}) |body|:
      null
  assert(invalid_name, "invalid header name")
  assert(injected_value, "header injection")
  assert(conflicting_length, "conflicting Content-Length")
  assert(ambiguous_framing, "CL/TE ambiguity")
  assert(duplicate_host, "duplicate Host")
  assert(transformed_ambiguous_framing, "transformed CL/TE ambiguity")
  assert(transformed_duplicate_host, "transformed duplicate Host")
  assert(transformed_injected_value, "transformed header injection")
  assert(buffered_framing, "buffered response owns framing")
  assert(transformed_buffered_framing, "buffered response uses cached framing")
  assert(streaming_framing, "streaming response owns framing")

  log = io.Buffer.new()
  app = ember.App(routes: routes, middleware: [RequestIdMiddleware()], expose_exceptions: true)
  logging_app = ember.App(routes: routes, middleware: [AccessLogMiddleware(to: log)])
  probe = testing.get("/streamed", headers: {"x-request-id": "stage-one"})
  assert(probe.header("x-request-id") == "stage-one", "request id input snapshot")
  streaming_response = app.call(testing.get(
    "/streamed",
    headers: {"x-request-id": "stage-one", "x-input": "before"}))
  buffered_response = app.call(testing.get(
    "/buffered",
    headers: {"x-request-id": "stage-one", "x-input": "before"}))
  if ember.Response === streaming_response:
    raise ArgumentError("unexpected stream response: " + streaming_response.body_text)
  assert(ember.Response === buffered_response, "request-id preserves buffered response")
  assert(ember.StreamingResponse === streaming_response, "request-id preserves streaming response")
  assert(buffered_response.header("x-request-id") != null, "buffered request id")
  assert(streaming_response.header("x-request-id") != null, "streaming request id")
  assert(buffered_response.headers.all("set-cookie") == ["theme=dark", "session=abc"],
    "middleware preserves repeated buffered headers")
  assert(streaming_response.headers.all("set-cookie") == ["theme=dark", "session=abc"],
    "middleware preserves repeated streaming headers")
  logged_buffered = logging_app.call(testing.get("/buffered"))
  logged_stream = logging_app.call(testing.get("/streamed"))
  assert(ember.Response === logged_buffered, "access log preserves buffered response")
  assert(ember.StreamingResponse === logged_stream, "access log preserves streaming response")
  assert(log.to_str.contains?("\"event.kind\":\"access\""), "structured access log")
  assert(log.to_str.contains?("\"http.route\":\"/buffered\""),
    "access log uses route template")

  input = {"x-before": "yes"}
  request = ember.Request(
    target: "/buffered?tag=a&tag=b",
    path: "/buffered",
    raw_query: "tag=a&tag=b",
    headers: input)
  input.store!("x-before", "changed")
  assert(request.header("x-before") == "yes", "request headers snapshot input")
  pair_source = [["x-snapshot", "before"]]
  pair_headers = ember.Headers(pair_source)
  pair_source[0][1] = "after"
  pair_source.push!(["x-extra", "after"])
  assert(pair_headers.to_pairs == [["x-snapshot", "before"]],
    "header pairs are a deep snapshot")
  assert(request.query_params["tag"] == ["a", "b"], "query values snapshot")

  before_source = []
  param_source = {id: Int}
  snapshot_route = ember.Route(
    "GET", "/snap/:id", routes.routes[0].target,
    params: param_source,
    before: before_source)
  middleware_source_value = &record_error
  before_source.push!(middleware_source_value)
  param_source.store!(:other, Int)
  assert(snapshot_route.middleware.empty?, "route middleware snapshot")
  assert(not snapshot_route.param_types.has_key?(:other), "route params snapshot")
  route_source = [snapshot_route]
  snapshot_routes = ember.Routes(route_source)
  route_source.push!(routes.routes[0])
  assert(snapshot_routes.routes.count == 1, "route table snapshot")

  match_params_source = {id: 42}
  captures_source = [42]
  snapshot_match = ember.RouteMatch(snapshot_route, match_params_source, captures_source)
  match_params_source.store!(:id, 7)
  captures_source[0] = 7
  assert(snapshot_match.path_params[:id] == 42, "match path params snapshot")
  assert(snapshot_match.captures == [42], "match captures snapshot")
  allowed_source = ["GET"]
  snapshot_lookup = ember.RouteLookup(:method_not_allowed, allowed_methods: allowed_source)
  allowed_source.push!("TRACE")
  assert(snapshot_lookup.allowed_methods == ["GET"], "allowed methods snapshot")
  [1, 2, 7, 42, 999].each |id|:
    path = routes.path(:item, id: id)
    round_trip = routes.match(path, method: "GET")
    assert(round_trip.match.path_params["id"] == id, "route/path property round-trip")

  observed = ember.App(routes: routes, on_error: &record_error)
  error_response = observed.call(testing.get("/failure"))
  assert(error_response.status == 500 and error_response.body_text == "internal server error",
    "safe application error response")
  event = error_events[-1]
  assert(event.method == "GET" and event.route_pattern == "/failure", "redacted error metadata")
  assert(ValueError === event.error, "error hook observes original exception")
  assert(event.method != null and event.route_pattern != null,
    "error event exposes only documented redacted request metadata")

  broken_hook_app = ember.App(routes: routes, on_error: &broken_error_hook)
  assert(broken_hook_app.call(testing.get("/failure")).status == 500,
    "ordinary reporter failure cannot replace response")
  cancelling_hook_app = ember.App(routes: routes, on_error: &cancelling_error_hook)
  assert(propagated(cancelling_hook_app, "/failure", CancelledError),
    "error hook cancellation propagates")

  assert(propagated(app, "/cancel", CancelledError), "cancellation is not converted to 500")
  assert(propagated(app, "/isolation", IsolationError), "isolation error is not converted to 500")
  assert(propagated(app, "/lifetime", LifetimeError), "fatal runtime error is not converted to 500")

  invalid_server = false
  try:
    app.run(read_timeout: null, max_requests: 0)
  rescue ArgumentError:
    invalid_server = true
  assert(invalid_server, "server timeouts must be finite")
  true
