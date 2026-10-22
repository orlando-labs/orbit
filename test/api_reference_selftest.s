package orbit.api_reference_selftest

import orbit
import orbit.middleware
import orbit.multipart
import orbit.security
import orbit.telemetry
import orbit.testing
from orbit.html import raw, url

export main

def show(request, id):
  orbit.render(json: {id: id, origin: request.origin()})

routes = orbit.routes:
  get "/items/:id", to: &show, params: {id: Int}, as: :item

def main():
  policy = orbit.SecurityPolicy(allowed_hosts: ["example.test"])
  sink = telemetry.MemorySink()
  observer = telemetry.Telemetry(sink: sink)
  app = orbit.App(routes: routes, security: policy, telemetry: observer)

  request = testing.get("/items/42", headers: {host: "example.test"})
  response = app.call(request)
  testing.assert_status(response, :ok)
  testing.assert_header(response, "content-type", "application/json; charset=utf-8")

  destination = routes.path(:item, id: 42)
  destination_url = url(destination)
  page = raw("<a href=\"" + destination_url.to_str + "\">item</a>")
  testing.assert_body(orbit.Response(body: page),
    "<a href=\"/items/42\">item</a>")

  cookies = security.CookieJar.parse("theme=dark")
  raise "cookie API example failed" unless cookies.get("theme") == "dark"
  raise "metrics API example failed" unless observer.metrics.snapshot()["http.server.requests"] == 1
  print("api reference selftest passed")
