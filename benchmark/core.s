package orbit.benchmark.core

import orbit
import orbit.testing
from net.http import Client

export main

class NullStreamBody:
  def init():
    @bytes = 0

  def write(data, extensions: null):
    @bytes += if Bytes === data then data.count else data.to_str.bytesize
    self

  def close():
    self

  def trailer(name, value):
    self

  def finish():
    self

  def closed?():
    false

def small_json(request):
  orbit.render(json: {"ok": true, "value": 42})

def buffered_html(request):
  orbit.render(html: orbit.Html.raw(
    "<!doctype html><html><body><main>orbit benchmark</main></body></html>"))

def duplex(request):
  orbit.stream() |body|:
    request.body_stream.each_chunk(max_bytes: 1024) |chunk|:
      body.write(chunk.bytes())

def static_response(request):
  orbit.render(text: "ok")

routes = orbit.routes:
  get "/json", to: &small_json
  get "/html", to: &buffered_html
  post "/duplex", to: &duplex
  get "/keepalive", to: &static_response

def percentile(sorted, percent):
  sorted[((sorted.count - 1) * percent) // 100]

def measure(iterations, warmup: 20, &block):
  warmup.times:
    block()
  samples = []
  total_started = Time.monotonic
  iterations.times:
    started = Time.monotonic
    block()
    samples.push!((Time.monotonic - started).total_nanoseconds)
  total_ns = (Time.monotonic - total_started).total_nanoseconds
  ordered = samples.sorted
  {
    "iterations": iterations,
    "p50_us": percentile(ordered, 50).to_float / 1000.0,
    "p95_us": percentile(ordered, 95).to_float / 1000.0,
    "p99_us": percentile(ordered, 99).to_float / 1000.0,
    "throughput_per_second": iterations.to_float * 1000000000.0 / total_ns.to_float
  }

def route_table(count):
  target = routes.routes[0].target
  entries = []
  count.times |index|:
    entries.push!(orbit.Route("GET", "/route/#{index}", target))
  orbit.Routes(entries)

def run_duplex(app, payload):
  response = app.call(testing.post("/duplex", body: payload))
  response._producer_block()(NullStreamBody())

def core_workloads():
  app = orbit.App(routes: routes)
  one_k = route_table(1000)
  four_k = route_table(4096)
  payload = "x" * 4096
  results = {}
  results.store!("small_json", measure(100, warmup: 5):
    app.call(testing.get("/json")))
  results.store!("buffered_html", measure(100, warmup: 5):
    app.call(testing.get("/html")))
  results.store!("router_1k", measure(20, warmup: 1):
    one_k.lookup("/route/999", "GET"))
  results.store!("router_4k", measure(20, warmup: 1):
    four_k.lookup("/route/4095", "GET"))
  results.store!("full_duplex_streaming", measure(100, warmup: 5):
    run_duplex(app, payload))
  results

def keepalive_workload():
  app = orbit.App(routes: routes)
  server = app.start(
    port: 0,
    workers: 1,
    max_concurrent_per_worker: 4,
    idle_timeout: 1.0,
    max_requests_per_connection: 1000)
  client = Client()
  result = measure(50, warmup: 5):
    client.get("http://127.0.0.1:#{server.port()}/keepalive").body_text()
  stats = server.stats()
  client.close!()
  server.shutdown(timeout: 1.0)
  server.wait()
  result.store!("keepalive_requests", stats[:keepalive_requests])
  result

def main():
  workloads = core_workloads()
  workloads.store!("keep_alive", keepalive_workload())
  io.stdout.write_line(Json.generate({
    "schema": "orbit.benchmark.result.v1",
    "suite": "core",
    "workloads": workloads
  }))
  null
