package orbit.security_policy_selftest

import orbit
import orbit.testing

export main

def assert(condition, message):
  raise ArgumentError(message) unless condition

def invalid_config(&block):
  rejected = false
  try:
    block()
  rescue ArgumentError:
    rejected = true
  assert(rejected, "invalid security configuration must fail at startup")

def ok(request): orbit.render(text: "ok")

routes = orbit.routes:
  get "/ok", to: &ok

def origin_checks():
  origin = orbit.Origin("HTTPS://APP.EXAMPLE.TEST:00443/")
  assert(origin.to_str == "https://app.example.test" and origin.host == "app.example.test" and origin.port == 443,
    "origin normalizes host case, trailing slash and default port")
  assert(origin.secure? and origin.websocket == "wss://app.example.test", "origin derives secure WebSocket endpoint")
  assert(orbit.Origin("http://[::1]:3000").to_str == "http://[::1]:3000", "origin supports bracketed IPv6")
  assert(orbit.Origin("https://[::1]").to_str == "https://[::1]", "IPv6 origin without an explicit port")
  ["", "://", "http://", "http:///", "http://[]", "http://:80", "http://host:", "http://[::1]:", "ftp://app.example.test", "//app.example.test", "http://user@host", "http://host/path",
    "http://host?query", "http://host#fragment", "http://host\\evil", "http://host:0", "http://host:65536",
    "http://host\r\nx-header: injected", "http://127.1", "http://127.0.0.01"].each |value|:
    invalid_config(): orbit.Origin(value)

  app = orbit.App(routes: routes, security: orbit.SecurityPolicy(origin: "http://app.example.test:3000"))
  accepted = app.call(testing.get("/ok", headers: {host: "app.example.test:3000"}))
  wrong_port = app.call(testing.get("/ok", headers: {host: "app.example.test:3001"}))
  assert(accepted.status == 200 and wrong_port.status == 403, "origin binds host and port before routing")
  wrong_host = app.call(testing.get("/ok", headers: {host: "elsewhere.example.test:3000"}))
  assert(wrong_host.status == 403, "origin supplies the allowed host default")
  canonical = orbit.App(routes: routes, security: orbit.SecurityPolicy(origin: "http://app.example.test"))
  assert(canonical.call(testing.get("/ok", headers: {host: "APP.EXAMPLE.TEST:00080"})).status == 200,
    "equivalent default ports and host case match the origin")

  proxy = orbit.App(routes: routes, security: orbit.SecurityPolicy(origin: origin,
    allowed_hosts: ["app.example.test", "internal.example"], trusted_proxy_cidrs: ["10.0.0.0/8"],
    forwarded: :x_forwarded, forwarded_hops: 1))
  headers = {host: "internal.example", "x-forwarded-host": "app.example.test:443", "x-forwarded-proto": "https"}
  trusted = proxy.call(orbit.Request(path: "/ok", target: "/ok", headers: headers, remote_endpoint: "10.1.2.3:4567"))
  spoofed = proxy.call(orbit.Request(path: "/ok", target: "/ok", headers: headers, remote_endpoint: "192.0.2.1:4567"))
  headers["x-forwarded-proto"] = "http"
  wrong_scheme = proxy.call(orbit.Request(path: "/ok", target: "/ok", headers: headers, remote_endpoint: "10.1.2.3:4567"))
  assert(trusted.status == 200 and spoofed.status == 403 and wrong_scheme.status == 403,
    "origin uses validated proxy provenance, including scheme")
  headers["x-forwarded-proto"] = "https"
  headers["x-forwarded-host"] = "app.example.test:444"
  assert(proxy.call(orbit.Request(path: "/ok", target: "/ok", headers: headers, remote_endpoint: "10.1.2.3:4567")).status == 403,
    "trusted proxy cannot bypass origin port constraints")

def csp_checks():
  baseline = orbit.ContentSecurityPolicy()
  assert(baseline.to_str == "default-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
    "structured CSP preserves existing core defaults")
  images = [:self, "https://IMAGES.EXAMPLE.TEST:443/"]
  extended = baseline.with(img_src: images, worker_src: [:self, :blob])
  images.push!("https://mutated.example.test")
  assert(not baseline.to_str.contains?("img-src"), "extending CSP preserves the original")
  assert(extended.to_str.contains?("img-src 'self' https://images.example.test") and not extended.to_str.contains?("mutated"),
    "CSP normalizes sources and snapshots caller collections")
  assert(extended.to_str.contains?("worker-src 'self' blob:"), "explicit scheme keywords")
  narrowed = extended.with(img_src: [])
  assert(narrowed.to_str.contains?("img-src 'none'") and not narrowed.to_str.contains?("images.example.test"),
    "with replaces a source list; an empty list denies that resource")
  assert(baseline.with(script_src_elem: [:self, :self]).to_str.contains?("script-src-elem 'self'"),
    "directive serialization and source deduplication")
  invalid_config(): baseline.with(img_src: [:none, :self])
  invalid_config(): baseline.with(script_src: "https://scripts.example.test")
  invalid_config(): baseline.with(unknown_src: [:self])
  invalid_config(): baseline.with(script_src: [:unknown])
  ["https://safe.example; script-src *", "https://safe.example\nscript-src *", "https://user@safe.example",
    "https://safe.example/path", "javascript:alert(1)", "https://safe.example?x=1"].each |source|:
    invalid_config(): baseline.with(script_src: [source])
  too_many = []
  129.times: too_many.push!(:self)
  invalid_config(): baseline.with(script_src: too_many)
  long_label = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  large = []
  128.times |index|:
    large.push!("https://" + index.to_str + "." + long_label + "." + long_label + ".example.test")
  invalid_config(): baseline.with(img_src: large)

  app = orbit.App(routes: routes, security: orbit.SecurityPolicy(content_security_policy: extended))
  response = app.call(testing.get("/ok"))
  assert(response.header("content-security-policy") == extended.to_str, "SecurityPolicy serializes structured CSP")
  defaults = orbit.App(routes: routes)
  assert(defaults.call(testing.get("/ok")).header("content-security-policy") == baseline.to_str,
    "existing applications retain the same default CSP header")
  raw_app = orbit.App(routes: routes, security: orbit.SecurityPolicy(content_security_policy: "default-src 'none'"))
  disabled = orbit.App(routes: routes, security: orbit.SecurityPolicy(content_security_policy: null))
  assert(raw_app.call(testing.get("/ok")).header("content-security-policy") == "default-src 'none'",
    "existing string CSP configuration is preserved")
  assert(disabled.call(testing.get("/ok")).header("content-security-policy") == null,
    "explicit null CSP configuration is preserved")

def main():
  origin_checks()
  csp_checks()
  print "PASS Orbit origin and structured CSP"
