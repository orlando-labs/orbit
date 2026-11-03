package orbit.assets_selftest

import orbit
import orbit.testing
from orbit.assets import StaticFiles
from net.http import Client

export main

def check(value, message):
  raise ValueError("static assets: " + message) unless value

def fallback(request): orbit.render(text: "application")
def label(request, value): orbit.render(text: value)

routes = orbit.routes:
  get "/app", to: &fallback
  get "/labels/:value", to: &label

class Chunks:
  attr sizes
  attr parts
  def init():
    @sizes = []
    @parts = []
  def write(chunk):
    @sizes.push!(chunk.count)
    @parts.push!(chunk.to_str)

class Interrupted:
  def write(chunk): raise ValueError("client disconnected")

def main():
  parser = ArgParser()
  parser.arg("--fixtures", required: true)
  root = parser.parse_or_raise[:fixtures]
  files = StaticFiles(root: root + "/public", chunk_size: 4096)
  app = orbit.App(routes: routes, middleware: [files], expose_exceptions: true)
  large = app.call(testing.get("/large.bin"))
  raise ValueError(large.body_text) unless orbit.StreamingResponse === large
  check(orbit.StreamingResponse === large and large.length == 150000, "file stays a fixed-length streaming response")
  producer = large._producer_block
  chunks = Chunks()
  producer(chunks)
  check(chunks.sizes.count > 1 and chunks.sizes.all?: _1 <= 4096, "bounded reads reach the writer incrementally")
  check(chunks.parts.join("") == fs.read_text(root + "/public/large.bin"), "chunk stream preserves every byte")
  interrupted = false
  try:
    producer(Interrupted())
  rescue ValueError:
    interrupted = true
  check(interrupted, "writer interruption propagates through scoped File.open")
  retry = Chunks()
  producer(retry)
  check(retry.parts.join("") == chunks.parts.join(""), "producer opens its own file rather than capturing an open descriptor")
  head = app.call(testing.head("/large.bin"))
  check(orbit.Response === head and head.body_text == "" and head.header("content-length") == "150000", "HEAD omits file producer and retains length")
  check(app.call(testing.get("/app")).body_text == "application", "unmatched asset falls through to application")
  check(app.call(testing.get("/labels/%25")).body_text == "%", "static path restrictions do not reject valid application routes")
  ["/missing", "/nested", "/.env", "/nested/.secret", "/../private.txt", "/%2e%2e/private.txt",
    "/nested%2f..%2fprivate.txt", "/%252e%252e/private.txt", "/..%5cprivate.txt", "/C%3a/private.txt",
    "/%00bad", "/linked.txt", "/linked-dir/private.txt"].each |path|:
    check(app.call(testing.get(path)).status == 404, "private/invalid/missing path rejected: " + path)
  check(app.call(testing.get("/%XX")).status == 400, "malformed URL retains normal application error handling")
  check(app.call(testing.post("/favicon.svg")).status == 404, "static middleware only handles GET/HEAD")
  mounted = orbit.App(routes: routes, middleware: [StaticFiles(root: root + "/public", at: "/static")])
  check(orbit.StreamingResponse === mounted.call(testing.get("/static/favicon.svg")), "explicit URL prefix")
  check(mounted.call(testing.get("/favicon.svg")).status == 404 and mounted.call(testing.get("/static-other/favicon.svg")).status == 404, "mount prefix matches whole path segments")
  invalid_root = false
  try:
    StaticFiles(root: root + "/rootlink")
  rescue ArgumentError:
    invalid_root = true
  check(invalid_root, "configured root cannot be a symlink")

  server = app.start(port: 0)
  client = Client(timeout: 5.0)
  origin = "http://127.0.0.1:" + server.port.to_str
  try:
    icon = client.get(origin + "/favicon.svg")
    check(icon.status == 200 and icon.body_text == fs.read_text(root + "/public/favicon.svg"), "wire SVG response")
    check(icon.headers.first("content-type") == "image/svg+xml", "SVG MIME")
    check(icon.headers.first("content-length") == fs.metadata(root + "/public/favicon.svg").size.to_str, "wire Content-Length")
    check(icon.headers.first("transfer-encoding") == null, "fixed stream does not use chunked framing")
    check(icon.headers.first("cache-control") == "public, max-age=3600", "unhashed asset cache policy")
    check(icon.headers.first("x-content-type-options") == "nosniff", "security policy protects asset responses")
    empty = client.get(origin + "/empty.txt")
    check(empty.body_text == "" and empty.headers.first("content-length") == "0", "empty file")
    css = client.get(origin + "/nested/style.css")
    check(css.body_text == "body { color: green }" and css.headers.first("content-type").starts_with?("text/css"), "nested asset and MIME")
    big = client.get(origin + "/large.bin")
    check(big.body_text.bytesize == 150000 and big.headers.first("content-type") == "application/octet-stream", "multi-chunk binary transfer")
    head = client.head(origin + "/large.bin")
    check(head.body_text == "" and head.headers.first("content-length") == "150000", "wire HEAD")
  ensure:
    client.close!
    server.shutdown(timeout: 1.0)
    server.wait
  print "PASS streaming static files"
