package orbit.stage5_fuzz_smoke

import orbit
import orbit.multipart
import orbit.testing
from net.http import Client
import net.tcp

export main

def assert(condition, message):
  raise ArgumentError(message) unless condition

schema = orbit.params:
  field(:name, required: true)

def echo(request):
  orbit.render(json: request.params.json.expect(schema))

def ok(request):
  orbit.render(text: "ok")

routes = orbit.routes:
  get "/ok", to: &ok
  get "/items/:id", to: &ok
  post "/json", to: &echo

def parser_corpus():
  app = orbit.App(routes: routes)
  percent_cases = [
    "/items/%", "/items/%0", "/items/%GG", "/items/%2f", "/items/%00",
    "/items/%25", "/items/a%20b", "/items/%F0%9F%92%A5", "/items/%C0%AF"
  ]
  percent_cases.each |path|:
    try:
      routes.lookup(path, "GET")
    rescue Exception:
      null

  query_cases = [
    "", "a=1", "a=1&a=2", "a=%", "a=%GG", "a=%00", "=x", "&&", "a=+",
    "a=%F0%9F%92%A5", "a=" + "x" * 1024
  ]
  query_cases.each |query|:
    try:
      orbit.Request(path: "/ok", target: "/ok?" + query, raw_query: query).query_params()
    rescue Exception:
      null

  json_cases = [
    "", "null", "[]", "{}", "{", "{\"name\":1}", "{\"name\":null}",
    "{\"name\":\"ok\"}", "{\"name\":\"\\u0000\"}", "[1,2,3]"
  ]
  json_cases.each |body|:
    response = app.call(testing.post("/json", headers: {
      "content-type": "application/json"
    }, body: body))
    assert([200, 400].contains?(response.status), "JSON fuzz result is bounded")

  multipart_cases = [
    "", "--x--\r\n", "--x\n", "--x\r\n\r\n--x--\r\n",
    "--x\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\n1\r\n--x--\r\n",
    "--x\r\nContent-Disposition: form-data; name=\"a\"; filename=\"../x\"\r\n\r\n1\r\n--x--\r\n"
  ]
  multipart_cases.each |body|:
    request = testing.post("/upload", headers: {
      "content-type": "multipart/form-data; boundary=x"
    }, body: body)
    try:
      multipart.parse(request)
    rescue multipart.MultipartError:
      null
  true

def raw_exchange(port, payload):
  socket = net.tcp.connect("127.0.0.1", port)
  socket.write_all!(payload)
  socket.read_all!().to_str

def framing_corpus():
  server = orbit.App(routes: routes).start(
    port: 0,
    read_timeout: 0.05,
    write_timeout: 0.2,
    idle_timeout: 0.05,
    max_header_bytes: 2048,
    max_body_bytes: 1024,
    max_requests_per_connection: 4)
  payloads = [
    "GET /ok HTTP/1.1\r\nhost: localhost\r\nconnection: close\r\n\r\n",
    "GET /ok HTTP/1.1\nhost: localhost\n\n",
    "GET  /ok HTTP/1.1\r\nhost: localhost\r\n\r\n",
    "GET /ok HTTP/1.1\r\nhost: a\r\nhost: b\r\n\r\n",
    "POST /json HTTP/1.1\r\nhost: localhost\r\ncontent-length: -1\r\n\r\n",
    "POST /json HTTP/1.1\r\nhost: localhost\r\ncontent-length: 1\r\ncontent-length: 2\r\n\r\n",
    "POST /json HTTP/1.1\r\nhost: localhost\r\ncontent-length: 0\r\ntransfer-encoding: chunked\r\n\r\n",
    "POST /json HTTP/1.1\r\nhost: localhost\r\ntransfer-encoding: gzip\r\n\r\n",
    "GET /ok HTTP/1.1\r\nhost: localhost\r\n folded: yes\r\n\r\n",
    "G?T /ok HTTP/1.1\r\nhost: localhost\r\n\r\n"
  ]
  payloads.each |payload|:
    try:
      raw_exchange(server.port(), payload)
    rescue Exception:
      null
    probe = Client().get("http://127.0.0.1:#{server.port()}/ok")
    assert(probe.status == 200 and probe.body_text() == "ok", "framing corpus must not crash server")
  assert(server.shutdown(timeout: 1.0), "fuzz smoke server drains")
  server.wait()
  true

def main():
  parser_corpus()
  framing_corpus()
  print("stage5 fuzz smoke passed")
