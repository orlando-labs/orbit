package orbit.middleware

import orbit
import orbit.telemetry

export request_id, access_log, RequestIdMiddleware, AccessLogMiddleware
export macro before

def request_id(request, next):
  RequestIdMiddleware()(request, next)

class RequestIdMiddleware:
  def init(@accept_incoming: true, @max_length: 128):
    unless Bool === @accept_incoming:
      raise ArgumentError("request-id accept_incoming must be Bool")
    unless Int === @max_length and @max_length >= 16 and @max_length <= 256:
      raise ArgumentError("request-id max_length must be between 16 and 256")

  def call(request, next):
    RequestIdContinuation(request, next, @accept_incoming, @max_length).call

class RequestIdContinuation:
  def init(@request, @next, @accept_incoming, @max_length)

  def _valid?(value):
    return false unless Str === value
    return false if value.empty? or value.length > @max_length
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
    value.chars.all? |char|: allowed.contains?(char)

  def call():
    supplied = @request.header("x-request-id")
    @request_id = if @accept_incoming and _valid?(supplied) then supplied else SecureRandom.base64url(18)
    response = orbit.normalize_response(@next(@request))
    orbit.with_response_header(response, "x-request-id", @request_id)

def access_log(request, next):
  AccessLogMiddleware()(request, next)

class AccessLogMiddleware:
  def init(to: io.stderr, redaction: null):
    sink = telemetry.JsonLogSink(to: to, redaction: redaction)
    @telemetry = telemetry.Telemetry(sink: sink, tracer: false)

  def call(request, next):
    AccessLogContinuation(request, next, @telemetry).call

class AccessLogContinuation:
  def init(@request, @next, @telemetry)

  def call():
    observation = @telemetry.start_request(@request)
    @telemetry.authorized_request(observation, @request)
    try:
      response = orbit.normalize_response(@next(@request))
      route_pattern = orbit.request_route_pattern(@request)
      @telemetry.finish_response(observation, response, @request, route_pattern)
    rescue Exception |error|:
      route_pattern = orbit.request_route_pattern(@request)
      @telemetry.finish_exception(observation, error, @request, route_pattern)
      raise error

macro def before(middleware as Ast, declaration as Ast) -> Ast:
  unless declaration.kind == "AstDefStmt":
    raise ArgumentError("ORBIT_BEFORE_DECLARATION: before supports module functions")
  params = declaration.signature.params
  if params.empty? or params[0].param_kind != "positional":
    raise ArgumentError("ORBIT_BEFORE_REQUEST: annotated function must accept request first")

  request_name = params[0].local_name
  request = Ast.node("AstName", {name: request_name})
  original = Ast.node("AstBlock", {
    params: [Ast.node("AstPatternParam", {pattern: request_name})],
    body: declaration.body
  })
  wrapped = quote:
    return orbit.__before(#{middleware}, __orbit_before_request__) |__orbit_before_next__|:
      __orbit_before_body__(__orbit_before_next__)
  wrapped = wrapped.replace_name("__orbit_before_request__", request)
  wrapped = wrapped.replace_name("__orbit_before_body__", original)
  return Ast.node("AstDefStmt", {
    name: declaration.name,
    signature: declaration.signature,
    body: [wrapped]
  })
