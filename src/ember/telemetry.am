package ember.telemetry

import ember
from sync import Mutex

export RedactionPolicy, JsonLogSink, MemorySink
export AccessEvent, ErrorLogEvent, TraceContext, ServerSpan, Tracer
export MetricsRegistry, HealthProbe, Telemetry

def _valid_request_id?(value):
  return false unless Str === value
  return false if value.empty? or value.length > 128
  allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
  value.chars.all? |char|: allowed.contains?(char)

def _hex?(value, length):
  return false unless Str === value and value.length == length
  allowed = "0123456789abcdef"
  value.chars.all? |char|: allowed.contains?(char)

def _all_zero?(value):
  value.chars.all? |char|: char == "0"

def _error_type(error):
  return "cancelled" if CancelledError === error or FlowCancelledError === error
  return "connection_reset" if ConnectionResetError === error
  return "broken_pipe" if BrokenPipeError === error
  return "unexpected_eof" if UnexpectedEofError === error
  return "route_parameter" if ember.RouteParamError === error
  return "request_parameters" if ember.RequestParamsError === error
  return "request_security" if ember.RequestSecurityError === error
  return "invalid_response" if ember.InvalidResponseError === error
  "Exception"

def _outcome(status, failed, cancelled: false):
  return "cancelled" if cancelled
  return "error" if failed or (status != null and status >= 500)
  return "client_error" if status != null and status >= 400
  "success"

def _payload_bytes(data):
  return data.count if Bytes === data
  data.to_str.bytesize

def _runtime_control_error?(error):
  return true if CancelledError === error or FlowCancelledError === error
  return true if IsolationError === error or LifetimeError === error
  return true if CapabilityError === error or EffectViolationError === error
  return true if DeterminismError === error or UnsupportedProfileError === error
  return true if WorldFrozenError === error
  return true if ConnectionResetError === error or BrokenPipeError === error
  return true if UnexpectedEofError === error
  false

def _safe_emit(sink, kind, fields):
  try:
    sink.emit(kind, fields)
  rescue Exception |error|:
    raise error if _runtime_control_error?(error)
    null

class RedactionPolicy:
  attr fields

  def init(fields: []):
    unless Array === fields:
      raise ArgumentError("redaction fields must be an Array")
    @fields = fields.map: _1.to_str.downcase .freeze
    if @fields.count > 128:
      raise ArgumentError("redaction field count exceeds 128")

  def apply(values as (Map | StrictMap)):
    result = {}
    values.each |name, value|:
      key = name.to_str
      selected = if @fields.include?(key.downcase) then "[REDACTED]" else value
      result.store!(key, selected)
    result.freeze

class JsonLogSink:
  def init(@to: io.stderr, redaction: null):
    @redaction = redaction or RedactionPolicy()
    unless RedactionPolicy === @redaction:
      raise ArgumentError("log redaction must be a RedactionPolicy")
    @mutex = Mutex.new()

  def emit(kind, fields as (Map | StrictMap)):
    payload = {}
    payload.store!("event.kind", kind.to_str)
    @redaction.apply(fields).each |name, value|:
      payload.store!(name, value)
    @mutex.synchronize:
      @to.write_line(Json.generate(payload))
      @to.flush
    payload.freeze

class MemorySink:
  attr events

  def init(redaction: null):
    @redaction = redaction or RedactionPolicy()
    unless RedactionPolicy === @redaction:
      raise ArgumentError("memory-sink redaction must be a RedactionPolicy")
    @events = []
    @mutex = Mutex.new()

  def emit(kind, fields as (Map | StrictMap)):
    payload = {}
    payload.store!("event.kind", kind.to_str)
    @redaction.apply(fields).each |name, value|:
      payload.store!(name, value)
    payload = payload.freeze
    @mutex.synchronize:
      @events.push!(payload)
    payload

  def snapshot():
    @mutex.synchronize: @events.copy.freeze

class TraceContext:
  attr trace_id
  attr parent_id
  attr flags

  def init(@trace_id, @parent_id, @flags)

  class_method def parse(value):
    return null unless Str === value and value.length == 55
    parts = value.split("-")
    return null unless parts.count == 4
    version = parts[0]
    parsed_trace_id = parts[1]
    parsed_parent_id = parts[2]
    parsed_flags = parts[3]
    return null unless version == "00"
    return null unless _hex?(parsed_trace_id, 32) and not _all_zero?(parsed_trace_id)
    return null unless _hex?(parsed_parent_id, 16) and not _all_zero?(parsed_parent_id)
    return null unless _hex?(parsed_flags, 2)
    TraceContext(parsed_trace_id, parsed_parent_id, parsed_flags)

class AccessEvent:
  attr request_id
  attr method
  attr route_pattern
  attr status
  attr duration_nanoseconds
  attr bytes
  attr outcome
  attr trace_id
  attr span_id

  def init(
    @request_id,
    @method,
    @route_pattern,
    @status,
    @duration_nanoseconds,
    @bytes,
    @outcome,
    @trace_id: null,
    @span_id: null
  )

  def fields():
    {
      "event.name": "http.server.request",
      "request.id": @request_id,
      "http.request.method": @method,
      "http.route": @route_pattern,
      "http.response.status_code": @status,
      "duration_ns": @duration_nanoseconds,
      "http.response.body.size": @bytes,
      "outcome": @outcome,
      "trace_id": @trace_id,
      "span_id": @span_id
    }

class ErrorLogEvent:
  attr request_id
  attr method
  attr route_pattern
  attr error_type
  attr trace_id
  attr span_id

  def init(@request_id, @method, @route_pattern, @error_type, @trace_id: null, @span_id: null)

  def fields():
    {
      "event.name": "ember.error",
      "request.id": @request_id,
      "http.request.method": @method,
      "http.route": @route_pattern,
      "error.type": @error_type,
      "outcome": "error",
      "trace_id": @trace_id,
      "span_id": @span_id
    }

class ServerSpan:
  attr trace_id
  attr span_id
  attr parent_span_id
  attr started_at
  attr finished_at
  attr attributes
  attr name
  attr status

  def init(request, request_id, parent: null, capture_path: false):
    @trace_id = if parent then parent.trace_id else SecureRandom.hex(16)
    @parent_span_id = if parent then parent.parent_id else null
    @flags = if parent then parent.flags else "01"
    @span_id = SecureRandom.hex(8)
    @started_at = Time.monotonic
    @finished_at = null
    @name = request.method
    @status = "UNSET"
    path_value = if capture_path then request.path else "[REDACTED]"
    @attributes = {
      "http.request.method": request.method,
      "url.path": path_value,
      "url.scheme": request.effective_scheme or "http",
      "network.protocol.name": "http",
      "request.id": request_id
    }
    if request.effective_authority:
      @attributes.store!("server.address", request.effective_authority)
    if request.client_ip:
      @attributes.store!("client.address", request.client_ip)

  def traceparent():
    "00-" + @trace_id + "-" + @span_id + "-" + @flags

  def finish!(route_pattern, status, bytes, outcome, error_type: null):
    return self if @finished_at
    @finished_at = Time.monotonic
    if route_pattern:
      @name = @attributes["http.request.method"] + " " + route_pattern
      @attributes.store!("http.route", route_pattern)
    @attributes.store!("http.response.status_code", status) if status != null
    @attributes.store!("http.response.body.size", bytes)
    @attributes.store!("error.type", error_type) if error_type
    @status = if outcome == "error" then "ERROR" else "UNSET"
    @attributes = @attributes.freeze
    self

  def duration_nanoseconds():
    finish = @finished_at or Time.monotonic
    (finish - @started_at).total_nanoseconds

  def fields():
    {
      "event.name": "otel.span",
      "name": @name,
      "kind": "SERVER",
      "trace_id": @trace_id,
      "span_id": @span_id,
      "parent_span_id": @parent_span_id,
      "status": @status,
      "duration_ns": duration_nanoseconds(),
      "attributes": @attributes
    }

class Tracer:
  def init(@sink, accept_remote: true, trusted_edge_only: true, capture_url_path: false):
    @accept_remote = accept_remote
    @trusted_edge_only = trusted_edge_only
    @capture_url_path = capture_url_path
    unless Bool === @accept_remote and Bool === @trusted_edge_only and Bool === @capture_url_path:
      raise ArgumentError("tracer policy flags must be Bool")

  def start_server_span(request as ember.Request, request_id):
    parent = null
    trusted = not @trusted_edge_only or request.trusted_proxy
    if @accept_remote and trusted:
      parent = TraceContext.parse(request.header("traceparent"))
    ServerSpan(request, request_id, parent: parent, capture_path: @capture_url_path)

  def finish_server_span(span as ServerSpan, route_pattern, status, bytes, outcome, error_type: null):
    span.finish!(route_pattern, status, bytes, outcome, error_type: error_type)
    _safe_emit(@sink, :span, span.fields())
    span

class MetricsRegistry:
  attr max_series

  def init(max_series: 8192):
    unless Int === max_series and max_series > 0 and max_series <= 65536:
      raise ArgumentError("metrics max_series must be between 1 and 65536")
    @max_series = max_series
    @mutex = Mutex.new()
    @requests = 0
    @in_flight = 0
    @errors = 0
    @response_bytes = 0
    @duration_nanoseconds = 0
    @duration_count = 0
    @duration_boundaries_ns = [
      5000000, 10000000, 25000000, 50000000, 75000000,
      100000000, 250000000, 500000000, 750000000, 1000000000,
      2500000000, 5000000000, 7500000000, 10000000000
    ]
    @duration_bucket_counts = @duration_boundaries_ns.map: 0
    @streams_active = 0
    @streams_completed = 0
    @streams_failed = 0
    # Request handlers run in isolated VMs whose dynamic Str ids are local to
    # that VM. Keep retained labels as VM-neutral Bytes and index them by an
    # Int hash; snapshot recreates Str keys in the caller's VM.
    @series = {}
    @series_count = 1
    @series_overflow = 0
    @integration_pools = {}
    @shutdowns = 0
    @forced_shutdowns = 0
    @shutdown_duration_nanoseconds = 0
    @server = null

  def attach_server(server):
    @mutex.synchronize:
      @server = server
    self

  def request_started():
    @mutex.synchronize:
      @in_flight += 1
    self

  def stream_started():
    @mutex.synchronize:
      @streams_active += 1
    self

  def request_finished(method, route_pattern, status, duration_nanoseconds, bytes, outcome, streaming: false):
    route = route_pattern or "<unmatched>"
    status_class = if status == null then "none" else (status // 100).to_str + "xx"
    key = method + " " + route + " " + status_class + " " + outcome
    encoded_key = Bytes.new(key)
    key_hash = encoded_key.stable_hash()
    @mutex.synchronize:
      @requests += 1
      @in_flight -= 1 if @in_flight > 0
      @errors += 1 if outcome == "error"
      @response_bytes += bytes
      @duration_nanoseconds += duration_nanoseconds
      @duration_count += 1
      duration_bucket = 0
      while duration_bucket < @duration_boundaries_ns.count and duration_nanoseconds > @duration_boundaries_ns[duration_bucket]:
        duration_bucket += 1
      if duration_bucket < @duration_bucket_counts.count:
        @duration_bucket_counts[duration_bucket] = @duration_bucket_counts[duration_bucket] + 1
      bucket = if @series.has_key?(key_hash) then @series[key_hash] else null
      entry = if bucket:
        bucket.find |candidate|: candidate[0].to_str == key
      else:
        null
      if entry:
        entry[1] = entry[1] + 1
      elsif @series_count >= @max_series:
        @series_overflow += 1
      else:
        entry = [encoded_key, 1]
        if bucket:
          bucket.push!(entry)
        else:
          @series.store!(key_hash, [entry])
        @series_count += 1
      if streaming:
        @streams_active -= 1 if @streams_active > 0
        @streams_completed += 1
        @streams_failed += 1 if outcome == "error"
    self

  def record_shutdown(clean, duration_nanoseconds):
    @mutex.synchronize:
      @shutdowns += 1
      @forced_shutdowns += 1 unless clean
      @shutdown_duration_nanoseconds += duration_nanoseconds
    self

  def set_integration_pool(name, active:, capacity:, waiting: 0):
    key = name.to_str
    unless key.length > 0 and key.length <= 64:
      raise ArgumentError("integration pool metric name must contain 1..64 characters")
    [active, capacity, waiting].each |value|:
      unless Int === value and value >= 0:
        raise ArgumentError("integration pool metrics must be non-negative Int values")
    @mutex.synchronize:
      if not @integration_pools.has_key?(key) and @integration_pools.count >= 64:
        raise ArgumentError("integration pool metric count exceeds 64")
      @integration_pools.store!(key, {
        "active": active,
        "capacity": capacity,
        "waiting": waiting
      }.freeze)
    self

  def snapshot():
    local = @mutex.synchronize:
      series = {"__overflow__": @series_overflow}
      @series.each |_key_hash, bucket|:
        bucket.each |entry|:
          series.store!(entry[0].to_str, entry[1])
      cumulative_duration_buckets = []
      cumulative_duration_count = 0
      @duration_bucket_counts.each |count|:
        cumulative_duration_count += count
        cumulative_duration_buckets.push!(cumulative_duration_count)
      {
        "http.server.requests": @requests,
        "http.server.active_requests": @in_flight,
        "http.server.request.duration": {
          "unit": "s",
          "count": @duration_count,
          "sum": @duration_nanoseconds.to_float / 1000000000.0,
          "explicit_bucket_boundaries": @duration_boundaries_ns.map:
            _1.to_float / 1000000000.0,
          "bucket_counts": cumulative_duration_buckets.freeze
        }.freeze,
        "http.server.response.body.size": {
          "unit": "By",
          "sum": @response_bytes
        }.freeze,
        "http.server.errors": @errors,
        "ember.streams.active": @streams_active,
        "ember.streams.completed": @streams_completed,
        "ember.streams.failed": @streams_failed,
        "ember.shutdowns": @shutdowns,
        "ember.shutdowns.forced": @forced_shutdowns,
        "ember.shutdown.duration_ns": @shutdown_duration_nanoseconds,
        "ember.request.series": series.freeze,
        "ember.integration.pools": @integration_pools.copy.freeze,
        "ember.server": if @server then @server.stats() else null
      }.freeze
    local

  def response(request = null):
    ember.render(json: snapshot())

class HealthProbe:
  def init():
    @mutex = Mutex.new()
    @server = null

  def attach_server(server):
    @mutex.synchronize:
      @server = server
    self

  def live?():
    true

  def ready?():
    server = @mutex.synchronize: @server
    server != null and server.ready?()

  def liveness(request = null):
    ember.render(json: {"status": "ok"})

  def readiness(request = null):
    ready = ready?()
    ember.render(
      json: {"status": if ready then "ready" else "not_ready"},
      status: if ready then :ok else :service_unavailable)

class RequestObservation:
  attr request
  attr request_id
  attr started_at
  attr span
  attr failed
  attr completed
  attr bytes

  def init(@request, @request_id):
    @started_at = Time.monotonic
    @span = null
    @failed = false
    @completed = false
    @bytes = 0

  def authorize!(request, span):
    @request = request
    @span = span
    self

  def fail!():
    @failed = true
    self

  def add_bytes!(count):
    @bytes += count
    self

  def complete!():
    return false if @completed
    @completed = true
    true

  def duration_nanoseconds():
    (Time.monotonic - @started_at).total_nanoseconds

class ObservedStreamBody:
  def init(@body, @observation)

  def write(data, extensions: null):
    if extensions == null:
      @body.write(data)
    else:
      @body.write(data, extensions: extensions)
    @observation.add_bytes!(_payload_bytes(data))
    self

  def close():
    @body.close()
    self

  def trailer(name, value):
    @body.trailer(name, value)
    self

  def finish():
    @body.finish()
    self

  def closed?():
    @body.closed?()

class Telemetry:
  attr sink
  attr metrics
  attr tracer
  attr health

  def init(sink: null, metrics: null, tracer: null, health: null, redaction: null):
    @sink = sink or JsonLogSink(redaction: redaction)
    @metrics = metrics or MetricsRegistry()
    @tracer = if tracer == false then null else (tracer or Tracer(@sink))
    @health = health or HealthProbe()

  def start_request(request as ember.Request):
    supplied = request.header("x-request-id")
    request_id = if _valid_request_id?(supplied) then supplied else SecureRandom.base64url(18)
    observation = RequestObservation(request, request_id)
    @metrics.request_started()
    observation

  def authorized_request(observation as RequestObservation, request as ember.Request):
    span = if @tracer then @tracer.start_server_span(request, observation.request_id) else null
    observation.authorize!(request, span)

  def record_error(observation as RequestObservation, error, request as ember.Request, route_pattern):
    observation.fail!()
    span = observation.span
    event = ErrorLogEvent(
      observation.request_id,
      request.method,
      route_pattern or "<unmatched>",
      _error_type(error),
      trace_id: if span then span.trace_id else null,
      span_id: if span then span.span_id else null)
    _safe_emit(@sink, :error, event.fields())
    event

  def finish_exception(observation as RequestObservation, error, request as ember.Request, route_pattern):
    cancelled = CancelledError === error or FlowCancelledError === error
    record_error(observation, error, request, route_pattern) unless cancelled
    _complete(
      observation,
      request,
      route_pattern,
      null,
      observation.bytes,
      _outcome(null, not cancelled, cancelled: cancelled),
      error_type: if cancelled then null else _error_type(error))
    null

  def finish_response(
    observation as RequestObservation,
    response as (ember.Response | ember.StreamingResponse),
    request as ember.Request,
    route_pattern
  ):
    selected = response
    unless response.header("x-request-id"):
      selected = ember.with_response_header(response, "x-request-id", observation.request_id)
    if ember.StreamingResponse === selected:
      @metrics.stream_started()
      producer = selected._producer_block()
      telemetry = self
      return ember.StreamingResponse(
        status: selected.status,
        headers: selected.headers,
        trailers: selected.trailers) |body|:
          try:
            producer(ObservedStreamBody(body, observation))
            telemetry._complete(
              observation,
              request,
              route_pattern,
              selected.status,
              observation.bytes,
              _outcome(selected.status, observation.failed),
              streaming: true)
          rescue Exception |error|:
            cancelled = CancelledError === error or FlowCancelledError === error
            telemetry.record_error(observation, error, request, route_pattern) unless cancelled
            telemetry._complete(
              observation,
              request,
              route_pattern,
              selected.status,
              observation.bytes,
              _outcome(selected.status, not cancelled, cancelled: cancelled),
              error_type: if cancelled then null else _error_type(error),
              streaming: true)
            raise error
    bytes = selected.body_bytes().count
    _complete(
      observation,
      request,
      route_pattern,
      selected.status,
      bytes,
      _outcome(selected.status, observation.failed))
    selected

  def _complete(
    observation as RequestObservation,
    request as ember.Request,
    route_pattern,
    status,
    bytes,
    outcome,
    error_type: null,
    streaming: false
  ):
    return null unless observation.complete!()
    duration = observation.duration_nanoseconds()
    route = route_pattern or "<unmatched>"
    span = observation.span
    if span and @tracer:
      @tracer.finish_server_span(
        span,
        route_pattern,
        status,
        bytes,
        outcome,
        error_type: error_type)
    event = AccessEvent(
      observation.request_id,
      request.method,
      route,
      status,
      duration,
      bytes,
      outcome,
      trace_id: if span then span.trace_id else null,
      span_id: if span then span.span_id else null)
    @metrics.request_finished(
      request.method,
      route_pattern,
      status,
      duration,
      bytes,
      outcome,
      streaming: streaming)
    _safe_emit(@sink, :access, event.fields())
    event

  def attach_server(server):
    @metrics.attach_server(server)
    @health.attach_server(server)
    self

  def record_shutdown(clean, duration_nanoseconds, stats):
    @metrics.record_shutdown(clean, duration_nanoseconds)
    _safe_emit(@sink, :lifecycle, {
      "event.name": "ember.server.shutdown",
      "outcome": if clean then "success" else "forced",
      "duration_ns": duration_nanoseconds,
      "active_requests": stats[:active_requests],
      "forced_shutdowns": stats[:forced_shutdowns]
    })
    self
