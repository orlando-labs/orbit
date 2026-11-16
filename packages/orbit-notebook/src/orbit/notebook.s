package orbit.notebook

import orbit
import task
from sync import Atomic

export serve

class TokenAccess:
  def init(@token)

  def call(request, next):
    unless request.header("authorization") == @token:
      return orbit.render(text: "Unauthorized", status: 401)
    next(request)

class NotebookReading:
  def init(@input, @control):
    @sequence = 0
    @busy = Atomic.new(false)

  def wait_for_reply(reply):
    remaining = 200
    while remaining > 0:
      if fs.exists?(reply):
        return Int(fs.read_text(reply, limit: 16))
      task.sleep(0.01)
      remaining -= 1
    503

  def call(request):
    return orbit.render(text: "Input unavailable", status: 404) if @input == ""
    if request.body_text.bytes.count > 8192:
      return orbit.render(text: "Reading too large", status: 413)
    parsed = false
    value = null
    try:
      value = Json.parse(request.body_text)
      parsed = true
    rescue Exception:
      null
    return orbit.render(text: "Expected a JSON value", status: 400) unless parsed
    unless @busy.compare_and_set(false, true):
      return orbit.render(text: "Notebook is busy", status: 503)
    try:
      @sequence += 1
      id = @sequence
      reply = @control + "/reply-" + id.to_str
      fs.atomic_write_text(@control + "/input.json", Json.generate({event: "input", id: id, input: @input, value: Json.generate(value)}))
      status = wait_for_reply(reply)
      orbit.render(text: if status == 200 then "Accepted" else "Input not accepted", status: status)
    ensure:
      @busy.set(false)

def health(request):
  orbit.render(text: "OK")

def accept_reading(request):
  request.service(:notebook_reading).call(request)

def default_routes():
  orbit.routes:
    get "/health", to: &health
    post "/reading", to: &accept_reading

def serve(config_path, control, supplied_routes: null):
  config = Json.parse(fs.read_text(config_path, limit: 65536))
  properties = config["properties"]
  port = Int(properties["port"])
  reading = NotebookReading(properties["reading"], control)
  routes = supplied_routes or default_routes()
  unless orbit.Routes === routes:
    raise ArgumentError("The selected export must be an orbit.Routes value")
  app = orbit.App(routes: routes, middleware: [TokenAccess("Bearer " + config["token"])],
    services: {notebook_reading: reading})
  handle = app.start(host: "127.0.0.1", port: port, max_body_bytes: 65536,
    read_timeout: 4.0, write_timeout: 4.0, idle_timeout: 3.0)
  try:
    fs.atomic_write_text(control + "/ready.json", Json.generate({event: "ready", port: handle.port()}))
    last = -1
    until fs.exists?(control + "/stop"):
      count = handle.stats()[:requests]
      if count != last:
        fs.atomic_write_text(control + "/stats.json", Json.generate({event: "stats", requests: count}))
        last = count
      task.sleep(0.05)
  ensure:
    handle.stop_accepting()
    handle.shutdown(timeout: 3.0)
    handle.wait()
