package orbit.oauth_http_selftest

import orbit
import orbit.telemetry
import orbit.session as sessions
import orbit.oauth as oauth
import orbit.oauth.github as github
import task
from net.http import Server, ServerResponse

export main

VERIFIER = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

def check(value, message):
  raise ValueError("OAuth HTTP: " + message) unless value

def main():
  requests = []
  server = Server(host: "127.0.0.1", port: 0, workers: 1)
  runner = task.spawn:
    server.serve(max_requests: 7) |request|:
      form = if request.method == "POST" then Url.parse_query(request.body_text) else {}
      requests.push!({path: request.path, method: request.method, form: form,
        authorization: request.headers.first("authorization"),
        user_agent: request.headers.first("user-agent")})
      data = {access_token: "gho_http", token_type: "bearer", refresh_token: "refresh-http", scope: "read:user,user:email"}
      if request.path == "/user":
        data = {id: 987, login: "loopback"}
      elif request.path == "/user/emails":
        data = [{email: "local@example.com", primary: true, verified: true}]
      elif form[?:grant_type] == "refresh_token":
        data = {access_token: "gho_rotated", token_type: "bearer", refresh_token: "refresh-rotated"}
      elif form[?:code] == "oversize":
        data = {access_token: "x" * 20000, token_type: "bearer"}
      if request.path == "/redirect":
        ServerResponse(status: 302, headers: {location: "/must-not-follow", connection: "close"}, body: "")
      else:
        ServerResponse(status: 200, headers: {"content-type": "application/json", connection: "close"}, body: Json.generate(data))
  base = "http://127.0.0.1:" + server.port.to_str
  client = github.Provider(client_id: "client", client_secret: "secret", redirect_uri: base + "/callback",
    site_url: base, api_url: base, allow_http_loopback: true)
  try:
    token = client.exchange("real-http-code", VERIFIER)
    identity = client.identity(token)
    check(identity.uid == "987" and identity.info[:email] == "local@example.com", "profile over real HTTP transport")
    refreshed = client.refresh(token)
    check(refreshed.access_token == "gho_rotated" and refreshed.refresh_token == "refresh-rotated", "refresh token rotation")
    redirected = false
    try:
      client.json_request(:get, base + "/redirect")
    rescue oauth.TransportError:
      redirected = true
    check(redirected, "HTTP redirects are never followed")
    limited = false
    try:
      client.exchange("oversize", VERIFIER)
    rescue oauth.TransportError:
      limited = true
    check(limited, "streamed response size is bounded before JSON parsing")
    check(client.exchange("after-failure", VERIFIER).access_token == "gho_http", "response lease is closed after body limit failure")
    runner.wait
    check(requests.count == 7, "no unexpected redirect or retries")
    check(requests[0][:form][:code_verifier] == VERIFIER and requests[0][:form][:client_secret] == "secret", "wire token request")
    check(requests[1][:authorization] == "Bearer gho_http" and requests[1][:user_agent] == "orbit-oauth-github", "wire profile headers")
    check(requests[3][:form][:refresh_token] == "refresh-http", "wire refresh request")
  ensure:
    client.close!
    server.close!
  print "PASS orbit OAuth HTTP transport"
  true
