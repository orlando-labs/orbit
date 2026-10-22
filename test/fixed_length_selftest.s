package orbit.fixed_length_selftest

import orbit
import orbit.testing
from orbit.telemetry import Telemetry, MemorySink
from orbit import Controller
from net.http import Client

export main

completion_sink = MemorySink()

def observed(request):
  sink = completion_sink
  observer = |success, bytes|:
    sink.emit("terminal", {success: success, bytes: bytes})
  orbit.stream(length: 3, on_complete: observer) |body|:
    body.write("yes")

def observed_short(request):
  sink = completion_sink
  observer = |success, bytes|:
    sink.emit("terminal", {success: success, bytes: bytes})
  orbit.stream(length: 4, on_complete: observer) |body|:
    body.write("ab")

def assert(condition, message):
  raise ArgumentError(message) unless condition

def fixed(request):
  orbit.stream(length: 6) |body|:
    body.write("one")
    body.write("")
    body.write("two")

def explicit_close(request):
  orbit.stream(length: 3) |body|:
    body.write("yes")
    body.close
    body.close
    body.finish
    body.finish

def empty(request):
  orbit.stream(length: 0) |body|:
    null

def head_only(request):
  orbit.stream(length: 2147483648) |body|:
    raise ArgumentError("HEAD must not start producer")

def short(request):
  orbit.stream(length: 4) |body|:
    body.write("ab")

def overflow(request):
  orbit.stream(length: 4) |body|:
    body.write("ab")
    try:
      body.write("cde")
    rescue BodyLengthError:
      null

def short_close(request):
  orbit.stream(length: 4) |body|:
    body.write("ab")
    try:
      body.close
    rescue BodyLengthError:
      null

def chunked(request):
  orbit.stream(trailers: ["x-done"]) |body|:
    body.write("yes", extensions: [["part", "one"]])
    body.close
    body.trailer("x-done", "ok")
    body.finish

def no_extensions(request):
  orbit.stream(length: 1) |body|:
    body.write("x", extensions: [["part", "one"]])

def no_trailers(request):
  orbit.stream(length: 1) |body|:
    body.write("x")
    body.close
    body.trailer("x-test", "no")

class FixedController < Controller:
  def show():
    stream(length: 3) |body|:
      body.write("yes")

def response_headers(request, next):
  response = next(request)
  if orbit.StreamingResponse === response:
    response = response.with_header("x-first", "yes")
    response = response.merge_headers({"x-second": "yes"})
    response = orbit.with_response_header(response, "x-third", "yes")
  response

routes = orbit.routes:
  get "/observed", to: &observed
  get "/observed-short", to: &observed_short
  get "/fixed", to: &fixed
  get "/explicit", to: &explicit_close
  get "/empty", to: &empty
  get "/head", to: &head_only
  get "/short", to: &short
  get "/overflow", to: &overflow
  get "/short-close", to: &short_close
  get "/chunked", to: &chunked
  get "/no-extensions", to: &no_extensions
  get "/no-trailers", to: &no_trailers
  get "/controller", to: &FixedController#show

def invalid_options():
  [-1, "3", true, 1.5].each |length|:
    rejected = try:
      orbit.stream(length: length) |body|: null
      false
    rescue ArgumentError:
      true
    assert(rejected, "invalid fixed length rejected")
  rejected_trailers = try:
    orbit.stream(length: 0, trailers: ["x-test"]) |body|: null
    false
  rescue InvalidHeaderError:
    true
  assert(rejected_trailers, "fixed length rejects declared trailers")
  ["content-length", "transfer-encoding", "trailer"].each |header|:
    headers = {}
    headers.store!(header, "3")
    rejected = try:
      orbit.stream(length: 3, headers: headers) |body|: null
      false
    rescue InvalidHeaderError:
      true
    assert(rejected, "framing headers remain transport-owned")
  true

def incomplete_transfer(port, path, prefix):
  client = Client(timeout: 2.0)
  received = ""
  try:
    response = client.get("http://127.0.0.1:#{port}#{path}", headers: {"connection": "close"})
    index = 0
    while index < prefix.bytesize:
      received = received + response.body.read(max_bytes: 1).to_str()
      index += 1
    incomplete = try:
      response.body.read(max_bytes: 1)
      false
    rescue UnexpectedEofError:
      true
    assert(incomplete, "invalid transfer is incomplete: " + path)
    assert(received == prefix, "excess bytes are not sent: " + path)
  ensure:
    client.close!

def main():
  invalid_options()
  observer = Telemetry(sink: MemorySink(), tracer: false)
  app = orbit.App(routes: routes, middleware: [&response_headers], telemetry: observer, expose_exceptions: true)
  response = app.call(testing.get("/fixed"))
  assert(orbit.StreamingResponse === response and response.length == 6,
    "header/security/telemetry wrappers preserve length")
  head = app.call(testing.head("/head"))
  assert(head.header("content-length") == "2147483648" and head.body_text == "",
    "in-memory HEAD advertises known length without producer")
  server = app.start(port: 0, idle_timeout: 0.2, write_timeout: 1.0)
  client = Client(timeout: 2.0)
  try:
    ["/fixed", "/explicit", "/empty", "/controller"].each |path|:
      res = client.get("http://127.0.0.1:#{server.port()}#{path}")
      text = res.body_text()
      expected = if path == "/fixed":
        "onetwo"
      elif path == "/empty":
        ""
      else:
        "yes"
      assert(res.status == 200 and text == expected,
        "fixed stream data: " + path + ": " + res.status.to_str + ": " + text)
      assert(res.headers.first("content-length") == expected.bytesize.to_str,
        "fixed stream exact length: " + path)
      assert(res.headers.first("transfer-encoding") == null, "fixed stream without TE")
      assert(res.headers.first("x-third") == "yes", "middleware headers preserved")
    head = client.head("http://127.0.0.1:#{server.port()}/head")
    assert(head.body_text() == "" and head.headers.first("content-length") == "2147483648",
      "wire HEAD preserves 2 GiB length")
    streamed = client.get("http://127.0.0.1:#{server.port()}/chunked")
    assert(streamed.body_text() == "yes" and streamed.headers.first("transfer-encoding") == "chunked",
      "default stream retains chunked mode")
    assert(streamed.body.trailers.first("x-done") == "ok", "chunked trailer retained")
    ["/short", "/overflow", "/short-close"].each |path|:
      incomplete_transfer(server.port(), path, "ab")
    incomplete_transfer(server.port(), "/no-extensions", "")
    response = client.get("http://127.0.0.1:#{server.port()}/no-trailers", headers: {"connection": "close"})
    assert(response.body_text() == "x", "invalid trailers do not become body data")
    assert(server.stats()["keepalive_requests"] > 0,
      "successful fixed responses preserve connection reuse")
    head = client.head("http://127.0.0.1:#{server.port()}/observed")
    assert(head.body_text == "" and completion_sink.snapshot().empty?,
      "HEAD does not invoke stream completion observer")
    full = client.get("http://127.0.0.1:#{server.port()}/observed")
    assert(full.body_text == "yes", "observed full transfer")
    incomplete_transfer(server.port(), "/observed-short", "ab")
    attempt = 0
    while completion_sink.snapshot().count < 2 and attempt < 100:
      task.sleep(0.01)
      attempt += 1
    terminal = completion_sink.snapshot()
    assert(terminal.count == 2, "exactly one terminal callback per streamed response")
    assert(terminal[0]["success"] == true and terminal[0]["bytes"] == 3,
      "successful callback reports actual payload after transport finish")
    assert(terminal[1]["success"] == false and terminal[1]["bytes"] == 2,
      "short transfer callback reports failure and actual prefix")
  ensure:
    client.close!
    server.shutdown(timeout: 1.0)
    server.wait
  true
