package orbit.session_selftest

import orbit
import orbit.testing
import orbit.telemetry
import orbit.session as sessions
import task
from orbit.security import Aead, CsrfMiddleware
from orbit.session._state import json_copy, SessionError as SessionDataError

export main
export Clock, round_trip, app_for, cookie, check
export server_store_checks, concurrent_requests

SECRET = "0123456789abcdef0123456789abcdef"

class Clock:
  def init(@stamp = 1000)
  def now(): @stamp
  def advance(seconds): @stamp += seconds

def check(value, message):
  raise ValueError("session: " + message) unless value

class Pages < sessions.Controller:
  def read(): render(json: {id: session[:account], visits: session[:visits]})
  def write():
    session[:account] = "account-42"
    session[:visits] = (session[:visits] or 0) + 1
    render(json: session.to_map)
  def rotate():
    before = session.id
    session.regenerate
    render(text: before + ":" + session.id)
  def logout():
    session.destroy
    render(text: "bye")
  def error():
    session[:account] = "should-not-save"
    raise ValueError("handler failure")
  def failure():
    session[:account] = "should-not-save"
    render(text: "failure", status: 500)
  def nested():
    session[:nested] = {items: [1]} unless session[:nested]
    session[:nested][:items].push!(2)
    render(json: session.to_map)
  def reset():
    session.reset
    render(text: session.to_map.count.to_str)
  def touch():
    session.touch
    render(text: "touched")
  def capture():
    service(:capture).push!(session)
    render(text: "captured")
  def child():
    state = session
    child = task.spawn:
      try:
        state[:account]
        false
      rescue sessions.SessionScopeError:
        true
    render(text: child.wait().to_str)
  def streaming():
    account = session[:account]
    stream() |body|: body.write(account or "anonymous")
  def late_stream():
    state = session
    stream() |body|: body.write(state[:account])
  def race():
    visits = session[:visits]
    service(:arrived).send(true)
    service(:resume).recv(timeout: 5.0)
    session[:visits] = visits + 1
    render(text: "saved")
  def cancelled():
    session[:account] = "should-not-save"
    service(:arrived).send(true)
    task.sleep(30.0)
    render(text: "saved")
  def overflow():
    session[:large] = "0123456789" * 500
    render(text: "large")
  def unrelated_cookie():
    session[:account] = "account-42"
    render(text: "ok", headers: {"set-cookie": "theme=dark; Path=/"})

def untouched(request): orbit.render(text: "public")

routes = orbit.routes:
  get "/read", to: &Pages#read
  post "/write", to: &Pages#write
  post "/rotate", to: &Pages#rotate
  post "/logout", to: &Pages#logout
  post "/error", to: &Pages#error
  post "/failure", to: &Pages#failure
  post "/nested", to: &Pages#nested
  post "/reset", to: &Pages#reset
  post "/touch", to: &Pages#touch
  get "/capture", to: &Pages#capture
  get "/child", to: &Pages#child
  get "/stream", to: &Pages#streaming
  get "/late-stream", to: &Pages#late_stream
  post "/race", to: &Pages#race
  post "/cancelled", to: &Pages#cancelled
  post "/overflow", to: &Pages#overflow
  post "/unrelated-cookie", to: &Pages#unrelated_cookie
  get "/public", to: &untouched

def cookie(response):
  value = response.header("set-cookie")
  if value then value.split(";")[0] else null

def app_for(store, clock, secret: SECRET, old_secrets: [], ttl: 60, absolute_ttl: 120, services: {}):
  middleware = sessions.Middleware(store: store, secret: secret, old_secrets: old_secrets,
    secure: false, ttl: ttl, absolute_ttl: absolute_ttl, clock: clock)
  orbit.App(routes: routes, services: services, middleware: [middleware], expose_exceptions: true)

def round_trip(store):
  clock = Clock()
  app = app_for(store, clock)
  public = app.call(testing.get("/public"))
  check(public.status == 200 and cookie(public) == null, "untouched request has no cookie")
  anonymous = app.call(testing.get("/read"))
  check(anonymous.status == 200 and cookie(anonymous) == null, "anonymous read does not create a session")
  written = app.call(testing.post("/write"))
  check(written.status == 200, "write response: " + written.body_text)
  token = cookie(written)
  check(token != null and not token.contains?("account-42"), "cookie is opaque")
  check(written.header("set-cookie").contains?("HttpOnly") and written.header("set-cookie").contains?("SameSite=Lax"), "safe cookie flags")
  read = app.call(testing.get("/read", headers: {cookie: token}))
  check(read.status == 200 and read.body_text.contains?("account-42"), "session survives another request: " + read.body_text)
  check(cookie(read) == null, "unchanged session does not emit a cookie")
  check(read.header("cache-control") == "private, no-store", "session-dependent response is private")
  check(read.header("vary") == "Cookie", "session-dependent response varies by cookie")
  failed = app.call(testing.post("/error", headers: {cookie: token}))
  check(failed.status == 500 and cookie(failed) == null, "handler exception does not save")
  read = app.call(testing.get("/read", headers: {cookie: token}))
  check(read.body_text.contains?("account-42"), "failed handler leaves prior session intact")
  failed = app.call(testing.post("/failure", headers: {cookie: token}))
  check(failed.status == 500 and cookie(failed) == null, "explicit 500 does not save")
  nested = app.call(testing.post("/nested", headers: {cookie: token}))
  nested = app.call(testing.post("/nested", headers: {cookie: cookie(nested)}))
  check(nested.status == 200 and nested.body_text.contains?("[1,2,2]"), "nested mutation is detected")
  token = cookie(nested)
  rotated = app.call(testing.post("/rotate", headers: {cookie: token}))
  check(rotated.status == 200 and cookie(rotated) != token, "regeneration issues new cookie")
  ids = rotated.body_text.split(":")
  check(ids.count == 2 and ids[0] != ids[1], "regeneration changes session id")
  new_token = cookie(rotated)
  logged_out = app.call(testing.post("/logout", headers: {cookie: new_token}))
  check(logged_out.status == 200 and logged_out.header("set-cookie").contains?("Max-Age=0"), "logout clears cookie")
  if store.kind != "cookie":
    stale = app.call(testing.get("/read", headers: {cookie: token}))
    check(not stale.body_text.contains?("account-42"), "old server-side id revoked by rotation")
    stale = app.call(testing.get("/read", headers: {cookie: new_token}))
    check(not stale.body_text.contains?("account-42"), "logout revokes server-side session")
  expires = app.call(testing.post("/write"))
  clock.advance(60)
  read = app.call(testing.get("/read", headers: {cookie: cookie(expires)}))
  check(not read.body_text.contains?("account-42"), "exact expiry boundary is expired")
  check(read.header("set-cookie").contains?("Max-Age=0"), "expired cookie is cleared")

def named_cookie(response, name):
  values = response.headers.all("set-cookie")
  value = values.find |header|: header.starts_with?(name + "=")
  if value then value.split(";")[0] else null

def server_store_checks(store):
  id = SecureRandom.hex(32)
  initial = sessions.Entry(id, 1, {count: 0}, 1000, 1000, 1060)
  store.commit(null, initial, now: 1000)
  left = store.load({id: id}, now: 1000)
  right = store.load({id: id}, now: 1000)
  left.data[:count] = 9
  check(store.load({id: id}, now: 1000).data[:count] == 0, "server entry snapshots do not alias storage")
  updated = sessions.Entry(id, 2, {count: 1}, 1000, 1000, 1060)
  store.commit(left, updated, now: 1000)
  conflict = false
  try:
    store.commit(right, updated, now: 1000)
  rescue sessions.SessionConflictError:
    conflict = true
  check(conflict, "stale server write rejected")
  store.destroy(left, now: 1000)
  conflict = false
  try:
    store.commit(updated, sessions.Entry(id, 3, {}, 1000, 1000, 1060), now: 1000)
  rescue sessions.SessionConflictError:
    conflict = true
  check(conflict and store.load({id: id}, now: 1000) == null, "stale write cannot resurrect deleted session")

def security_checks():
  key = Hex.decode("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f")
  nonce = Hex.decode("070000004041424344454647")
  aad = Hex.decode("50515253c0c1c2c3c4c5c6c7")
  plaintext = Bytes.new("Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.")
  sealed = Aead(key).seal_bytes(plaintext, aad: aad, nonce: nonce)
  expected = ("d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d6" +
    "3dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b36" +
    "92ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc" +
    "3ff4def08e4b7a9de576d26586cec64b61161ae10b594f09e26a7e902ecbd0600691")
  check(sealed.slice(12).hex == expected, "RFC 8439 ChaCha20-Poly1305 vector")
  clock = Clock()
  store = sessions.MemoryStore()
  app = app_for(store, clock)
  initial = app.call(testing.post("/write"))
  token = cookie(initial)
  offset = token.index("=") + 5
  replacement = if token.slice(offset...offset + 1) == "A" then "B" else "A"
  changed = token.slice(0...offset) + replacement + token.slice(offset + 1...token.length)
  invalid = app.call(testing.get("/read", headers: {cookie: changed}))
  check(not invalid.body_text.contains?("account-42") and cookie(invalid).contains?("orbit-session="), "tampered token resets session")
  duplicate = app.call(testing.get("/read", headers: {cookie: token + "; " + token}))
  check(duplicate.status == 400, "duplicate cookie names rejected")
  repeated = app.call(testing.get("/read", headers: [["cookie", token], ["cookie", token]]))
  check(repeated.status == 400, "multiple cookie headers rejected")
  different_name = orbit.App(routes: routes, middleware: [sessions.Middleware(
    store: store, secret: SECRET, name: "other-session", secure: false, clock: clock)])
  rebound = "other-session=" + token.split("=")[1]
  invalid = different_name.call(testing.get("/read", headers: {cookie: rebound}))
  check(not invalid.body_text.contains?("account-42"), "tokens are bound to cookie policy")
  new_secret = "abcdef0123456789abcdef0123456789"
  rotated = app_for(store, clock, secret: new_secret, old_secrets: [SECRET])
  check(rotated.call(testing.get("/read", headers: {cookie: token})).body_text.contains?("account-42"), "previous key accepted")
  reissued = rotated.call(testing.post("/write", headers: {cookie: token}))
  check(reissued.status == 200 and cookie(reissued) != token, "mutation reissues with active key")
  check(not app.call(testing.get("/read", headers: {cookie: cookie(reissued)})).body_text.contains?("account-42"), "old key cannot decode new cookie")
  secure = orbit.App(routes: routes, middleware: [sessions.Middleware(store: sessions.CookieStore(), secret: SECRET)])
  check(secure.call(testing.post("/write")).status == 400, "secure sessions reject HTTP before handler")
  overflow = app_for(sessions.CookieStore(), clock).call(testing.post("/overflow"))
  check(overflow.status == 500 and cookie(overflow) == null, "cookie overflow fails without response cookie")
  additional = app.call(testing.post("/unrelated-cookie"))
  check(additional.status == 200 and additional.headers.all("set-cookie").count == 2, "unrelated Set-Cookie preserved")
  check(app.call(testing.get("/child", headers: {cookie: token})).body_text == "true", "child task cannot use parent's session")
  captured = []
  capture_app = orbit.App(routes: routes, services: {capture: captured},
    middleware: [sessions.Middleware(store: store, secret: SECRET, secure: false, clock: clock)])
  check(capture_app.call(testing.get("/capture")).status == 200, "request service survives routing")
  escaped = false
  try:
    captured[0][:account]
  rescue sessions.SessionScopeError:
    escaped = true
  check(escaped, "session cannot escape response construction")
  body = StreamBody()
  response = app.call(testing.get("/stream", headers: {cookie: token}))
  response._producer_block()(body)
  check(body.text == "account-42", "stream can use a session snapshot captured by its action")
  escaped = false
  response = app.call(testing.get("/late-stream", headers: {cookie: token}))
  try:
    response._producer_block()(body)
  rescue sessions.SessionScopeError:
    escaped = true
  check(escaped, "stream producer cannot reopen a completed request session")
  bounded = app_for(sessions.CookieStore(), clock, ttl: 60, absolute_ttl: 120)
  first = bounded.call(testing.post("/write"))
  clock.advance(50)
  second = bounded.call(testing.post("/touch", headers: {cookie: cookie(first)}))
  clock.advance(50)
  third = bounded.call(testing.post("/touch", headers: {cookie: cookie(second)}))
  check(third.header("set-cookie").contains?("Max-Age=20"), "renewal bounded by absolute lifetime")
  clock.advance(20)
  check(not bounded.call(testing.get("/read", headers: {cookie: cookie(third)})).body_text.contains?("account-42"), "absolute lifetime enforced")

class StreamBody:
  attr text
  def init(): @text = ""
  def write(value): @text += value

class ObservedStore:
  attr reads
  attr writes
  def init():
    @delegate = sessions.MemoryStore()
    @reads = 0
    @writes = 0
  def kind(): "observed"
  def dump(entry): @delegate.dump(entry)
  def load(payload, now:):
    @reads += 1
    @delegate.load(payload, now: now)
  def commit(previous, entry, now:):
    @writes += 1
    @delegate.commit(previous, entry, now: now)
  def destroy(previous, now:): @delegate.destroy(previous, now: now)

class UnavailableStore < sessions.MemoryStore:
  def load(payload, now:): raise sessions.SessionStoreError("offline")

def store_policy_checks():
  clock = Clock()
  observed = ObservedStore()
  app = app_for(observed, clock)
  app.call(testing.get("/public"))
  app.call(testing.get("/read"))
  check(observed.reads == 0 and observed.writes == 0, "unused and anonymous sessions do not touch storage")
  written = app.call(testing.post("/write"))
  check(written.status == 200 and observed.writes == 1, "custom store receives a committed entry: " + written.body_text)
  app.call(testing.get("/read", headers: {cookie: cookie(written)}))
  check(observed.reads == 1 and observed.writes == 1, "read-only request loads without writing")
  bounded = orbit.App(routes: routes, middleware: [sessions.Middleware(
    store: observed, secret: SECRET, secure: false, clock: clock, max_data_bytes: 100)])
  overflow = bounded.call(testing.post("/overflow"))
  check(overflow.status == 500 and cookie(overflow) == null and observed.writes == 1,
    "serialization limits are checked before custom store side effects")
  memory = sessions.MemoryStore(max_entries: 1)
  app = app_for(memory, clock)
  token = cookie(app.call(testing.post("/write")))
  full = app.call(testing.post("/write"))
  check(full.status == 503 and cookie(full) == null and memory.size == 1, "memory capacity is bounded")
  rotated = app.call(testing.post("/rotate", headers: {cookie: token}))
  check(rotated.status == 200 and memory.size == 1, "rotation works at full capacity")
  unavailable = app_for(UnavailableStore(), clock)
  failed = unavailable.call(testing.get("/read", headers: {cookie: cookie(rotated)}))
  check(failed.status == 503 and cookie(failed) == null, "store outage fails without replacing authenticated session")
  clock.advance(60)
  check(app.call(testing.post("/write")).status == 200 and memory.size == 1, "capacity cleanup removes expired entries")
  check(memory.prune(now: 1120) == 1 and memory.size == 0, "explicit memory cleanup")

def json_checks():
  original = {items: [null, false, 1, 1.25, "text", StrictMap{child: [2]}]}
  copied = json_copy(original)
  copied[:items][5][:child].push!(3)
  check(original[:items][5][:child].count == 1, "JSON copy isolates nested maps and arrays")
  check(copied[:items][0] == null and copied[:items][1] == false and copied[:items][3] == 1.25,
    "JSON copy preserves scalar types")
  for invalid in [StrictMap{name: 1, "name": 2}, {1: "invalid key"}, :symbol, Bytes.new("bytes")]:
    rejected = false
    try:
      json_copy(invalid)
    rescue SessionDataError:
      rejected = true
    check(rejected, "JSON copy rejects ambiguous keys and unsupported values")
  deep = null
  34.times:
    deep = [deep]
  rejected = false
  try:
    json_copy(deep)
  rescue SessionDataError:
    rejected = true
  check(rejected, "JSON copy bounds nesting")

def concurrent_requests(store):
  arrived = Channel.new(capacity: 2)
  resume = Channel.new(capacity: 2)
  app = app_for(store, Clock(), services: {arrived: arrived, resume: resume})
  token = cookie(app.call(testing.post("/write")))
  first = task.spawn: app.call(testing.post("/race", headers: {cookie: token}))
  second = task.spawn: app.call(testing.post("/race", headers: {cookie: token}))
  2.times: arrived.recv(timeout: 5.0)
  2.times: resume.send(true)
  responses = [first.wait(), second.wait()]
  successes = responses.count |response|: response.status == 200
  conflicts = responses.count |response|: response.status == 409 and cookie(response) == null
  check(successes == 1 and conflicts == 1, "concurrent requests return one success and one conflict")
  read = app.call(testing.get("/read", headers: {cookie: token}))
  check(Json.parse(read.body_text)[:visits] == 2, "concurrent writes do not overwrite each other")
  writer = task.spawn: app.call(testing.post("/race", headers: {cookie: token}))
  arrived.recv(timeout: 5.0)
  check(app.call(testing.post("/logout", headers: {cookie: token})).status == 200, "logout completes while another request is suspended")
  resume.send(true)
  check(writer.wait().status == 409, "suspended writer cannot undo logout")
  check(not app.call(testing.get("/read", headers: {cookie: token})).body_text.contains?("account-42"), "logout revocation survives concurrent writer")
  token = cookie(app.call(testing.post("/write")))
  cancelled = task.async: app.call(testing.post("/cancelled", headers: {cookie: token}))
  arrived.recv(timeout: 5.0)
  cancelled.cancel()
  caught = false
  completed = null
  try:
    completed = cancelled.wait()
  rescue CancelledError:
    caught = true
  rescue FlowCancelledError:
    caught = true
  detail = if completed then completed.body_text else "no response"
  check(caught, "request cancellation propagates: " + detail)
  check(app.call(testing.get("/read", headers: {cookie: token})).body_text.contains?("account-42"), "cancelled request does not save")

def csrf_checks(store):
  clock = Clock()
  app = orbit.App(routes: routes, expose_exceptions: true, middleware: [
    sessions.Middleware(store: store, secret: SECRET, secure: false, clock: clock),
    CsrfMiddleware(secret: SECRET, session_service: :session)])
  initial = app.call(testing.get("/read"))
  check(initial.status == 200, "CSRF initial response: " + initial.body_text)
  identity = named_cookie(initial, "orbit-session")
  csrf = named_cookie(initial, "orbit-csrf")
  headers = {cookie: identity + "; " + csrf, "x-csrf-token": csrf.split("=")[1], origin: "http://localhost"}
  written = app.call(testing.post("/write", headers: headers))
  check(written.status == 200, "CSRF permits first mutation after session creation")
  headers[:cookie] = named_cookie(written, "orbit-session") + "; " + csrf
  written_again = app.call(testing.post("/write", headers: headers))
  check(written_again.status == 200, "CSRF identity stable across encrypted cookie revisions")
  headers[:cookie] = named_cookie(written_again, "orbit-session") + "; " + csrf
  rotated = app.call(testing.post("/rotate", headers: headers))
  check(rotated.status == 200 and named_cookie(rotated, "orbit-csrf") != csrf, "rotation refreshes CSRF cookie")

def main():
  json_checks()
  store_policy_checks()
  round_trip(sessions.CookieStore())
  round_trip(sessions.MemoryStore())
  server_store_checks(sessions.MemoryStore())
  concurrent_requests(sessions.MemoryStore())
  security_checks()
  csrf_checks(sessions.CookieStore())
  csrf_checks(sessions.MemoryStore())
  print "PASS orbit sessions"
  0
