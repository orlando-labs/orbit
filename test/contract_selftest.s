package orbit.contract_selftest

import orbit
import orbit.testing

export main

def fallback(request):
  orbit.render(text: "fallback", headers: {"x-handler": "get"})

def explicit_get(request):
  orbit.render(text: "get", headers: {"x-handler": "get"})

def explicit_head(request):
  orbit.render(text: "head", status: :accepted,
    headers: {"x-handler": "head"})

def strict_path(request):
  "strict"

def no_value(request):
  null

def empty_value(request):
  ""

routes = orbit.routes:
  get "/fallback", to: &fallback
  get "/explicit", to: &explicit_get
  head "/explicit", to: &explicit_head
  get "/strict", to: &strict_path
  get "/no-value", to: &no_value
  get "/empty-value", to: &empty_value

def assert(condition, message):
  raise ArgumentError(message) unless condition

def main():
  app = orbit.App(routes: routes, expose_exceptions: true)

  fallback_head = app.call(testing.head("/fallback"))
  assert(fallback_head.status == 200, "HEAD falls back to GET by default")
  assert(fallback_head.body_text == "", "HEAD never exposes response content")
  assert(fallback_head.header("x-handler") == "get", "HEAD keeps GET metadata")

  explicit_head_response = app.call(testing.head("/explicit"))
  assert(explicit_head_response.status == 202, "explicit HEAD route takes precedence")
  assert(explicit_head_response.body_text == "", "explicit HEAD content is suppressed")
  assert(explicit_head_response.header("x-handler") == "head", "explicit HEAD handler selected")

  exact_only = orbit.App(routes: routes, head_fallback: false)
  rejected_head = exact_only.call(testing.head("/fallback"))
  assert(rejected_head.status == 405, "HEAD fallback can be disabled")
  assert(rejected_head.header("allow") == "GET, OPTIONS", "exact-only Allow methods")

  method_rejected = app.call(testing.post("/fallback"))
  assert(method_rejected.status == 405, "known path with wrong method is 405")
  assert(method_rejected.header("allow") == "GET, HEAD, OPTIONS", "automatic methods in Allow")

  assert(app.call(testing.get("/strict")).status == 200, "exact slash path matches")
  assert(app.call(testing.get("/strict/")).status == 404, "trailing slash is significant")

  automatic_options = app.call(testing.options("/fallback"))
  assert(automatic_options.status == 204, "automatic OPTIONS is empty success")
  assert(automatic_options.body_text == "", "automatic OPTIONS has no content")
  assert(automatic_options.header("allow") == "GET, HEAD, OPTIONS", "automatic OPTIONS Allow")

  no_value_response = app.call(testing.get("/no-value"))
  assert(no_value_response.status == 204 and no_value_response.body_text == "", "null means 204")
  empty_value_response = app.call(testing.get("/empty-value"))
  assert(empty_value_response.status == 200 and empty_value_response.body_text == "", "empty text remains 200")

  assert(orbit.status_code(599) == 599, "highest valid HTTP status")
  invalid_status_rejected = false
  try:
    orbit.status_code(600)
  rescue orbit.UnknownStatusError |error|:
    invalid_status_rejected = true
  assert(invalid_status_rejected, "status outside 100..599 is rejected")
  true
