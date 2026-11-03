package orbit.respond_selftest

import orbit
from orbit import respond
import orbit.html as html

export main

def check(value, message):
  raise ValueError("respond: " + message) unless value

class Page < orbit.Controller:
  attr calls

  def init(request):
    super(request)
    @calls = []

  def current():
    data = {ok: true, uid: "9007199254740995"}
    respond:
      html:
        @calls.push!(:html)
        html.html"<h1>#{data[:uid]}</h1>"
      json:
        @calls.push!(:json)
        data
      text:
        @calls.push!(:text)
        "plain"
      format("text/csv"):
        @calls.push!(:csv)
        "ok,uid\ntrue,9007199254740995\n"
      format("application/vnd.notebook.session+json", encode: :json):
        @calls.push!(:vendor)
        data
      format("application/pdf"):
        @calls.push!(:pdf)
        Bytes.new("%PDF-fixture")

  def short():
    respond:
      html: orbit.Html("short")
      json: {short: true}
      text: "short"

  def defaults():
    respond(default: :json):
      html: orbit.Html("default html")
      json: {default: true}

  def parameterized():
    profile = orbit.Format("application/json; profile=\"orbit,session;v=1\"", encode: :json)
    respond(default: profile):
      json: {profile: false}
      format(profile): {profile: true}

  def mime_default():
    respond(default: "application/json"):
      html: orbit.Html("default html")
      json: {default: true}

  def status_and_headers():
    status(:created)
    header("x-controller", "yes")
    append_header("vary", "Origin, accept")
    append_header("vary", "ACCEPT, Accept-Encoding")
    respond:
      json: {created: true}

  def direct():
    header("x-controller", "yes")
    header("vary", "Cookie")
    respond:
      json:
        render(json: {direct: true}, status: :accepted, headers: {vary: "Origin", "x-result": "yes"})
      html: redirect("/", status: 303)
      text: orbit.Response(status: :no_content, headers: {vary: "*"})

  def raw_response():
    respond:
      json: orbit.Response(status: :created, body: "{\"raw\":true}", headers: {"x-result": "raw"})

  def streamed():
    respond:
      format("text/csv"):
        stream(length: 4, headers: {"x-result": "stream"}) |body|:
          @calls.push!(:stream)
          body.write("a,b\n")
      json: {streamed: false}

  def wrong_html():
    respond:
      html: "unsafe"

  def null_json():
    respond:
      json: null

  def false_json():
    respond:
      json: false

  def wrong_type():
    respond:
      format("application/pdf"): {invalid: true}

  def conflicting_type():
    respond:
      json: render(text: "wrong")

  def double_render():
    render(json: {})
    respond:
      json: {}

  def committed_value():
    respond:
      json:
        render(json: {})
        "wrong"

  def duplicate():
    respond:
      json: {}
      format("Application/JSON; CHARSET=UTF-8", encode: :json): {}

  def invalid_default():
    respond(default: :text):
      json: {}

def page(accept = null):
  headers = if accept == null then {} else {accept: accept}
  Page(orbit.Request(headers: headers))

def fails(type, &block):
  caught = false
  try:
    block()
  rescue Exception |error|:
    raise error unless type === error
    caught = true
  check(caught, "expected exception was not raised")

def negotiation_checks():
  cases = [
    (null, :html), ("*/*", :html), ("text/html", :html),
    ("application/json", :json), ("application/xml, application/json;q=0.8", :json),
    ("text/*;q=0.5,application/json;q=0.7", :json),
    ("application/json;q=0.4,text/html;q=0.6", :html),
    ("text/html;q=0,*/*;q=0.5", :json),
    ("application/json;q=0,text/*;q=0.8,*/*;q=1", :vendor),
    ("text/plain;q=0.000,text/html;q=0.001", :html),
    ("TEXT/HTML; CHARSET=\"UTF-8\"", :html),
    ("text/csv", :csv), ("application/pdf", :pdf),
    ("application/vnd.notebook.session+json", :vendor)
  ]
  cases.each |(accept, expected)|:
    controller = page(accept)
    response = controller.current
    check(response.status == 200 and controller.calls == [expected], "single lazy branch for " + accept.to_str)
    check(response.header("vary") == "Accept", "Vary for " + accept.to_str)
  json = page("application/json").current
  check(Json.parse(json.body)[:uid] == "9007199254740995", "JSON encoder preserves explicit string IDs")
  check(json.header("content-type") == "application/json; charset=utf-8", "standard JSON MIME")
  vendor = page("application/vnd.notebook.session+json").current
  check(vendor.header("content-type") == "application/vnd.notebook.session+json" and Json.parse(vendor.body)[:ok], "vendor MIME and explicit JSON encoder")
  pdf = page("application/pdf").current
  check(Bytes === pdf.body and pdf.body.to_str == "%PDF-fixture", "raw binary body")
  ["image/png", "*/*;q=0", "text/html;charset=iso-8859-1", ""].each |accept|:
    controller = page(accept)
    response = controller.current
    check(response.status == 406 and controller.calls.empty? and response.header("vary") == "Accept", "unacceptable: " + accept)
  ["broken", "*/json", "application/*+json", "text/html;q=2", "text/html;q=-1", "text/html;q=0.0001", "text/html;q=nan", "text/html;q=\"0.8\"", "text/html;q=0.2;q=0.4", "text/html; charset=\"broken"].each |accept|:
    controller = page(accept)
    response = controller.current
    check(response.status == 400 and controller.calls.empty? and response.header("vary") == "Accept", "malformed Accept: " + accept)
  ["text/html;q=0.", "text/html;q=1.", "text/html;q=1.000"].each |accept|:
    expected = if accept.contains?("q=0") then 406 else 200
    check(page(accept).current.status == expected, "quality grammar: " + accept)
  controller = Page(orbit.Request(headers: [["accept", "text/html;q=0.2"], ["Accept", "application/json;q=0.9"]]))
  check(Json.parse(controller.current.body)[:ok] and controller.calls == [:json], "all Accept field lines participate")
  bounded = page("text/html," * 129)
  check(bounded.current.status == 400 and bounded.calls.empty?, "Accept range bound")
  bounded = page("text/html; padding=" + "x" * 8192)
  check(bounded.current.status == 400 and bounded.calls.empty?, "Accept byte bound")

def representation_checks():
  check(Json.parse(page().defaults.body)[:default], "explicit default with absent Accept")
  check(Json.parse(page().mime_default.body)[:default], "MIME default matches standard charset representation")
  check(page("text/html").defaults.body.to_str == "default html", "default does not override preference")
  check(page("application/json;q=0,text/html").defaults.body.to_str == "default html", "default cannot bypass exclusion")
  check(Json.parse(page("*/*").parameterized.body)[:profile], "descriptor as default")
  check(Json.parse(page("application/json; profile=\"orbit,session;v=1\"").parameterized.body)[:profile], "quoted MIME separators and equals")
  response = page("application/json").status_and_headers
  check(response.status == 201 and response.header("x-controller") == "yes", "controller status and headers")
  check(response.header("vary") == "Origin, accept, Accept-Encoding", "Vary case-insensitive deduplication across field lines")
  response = page("application/json").direct
  check(response.status == 202 and response.header("x-result") == "yes" and response.header("x-controller") == "yes", "explicit render response and headers")
  check(response.header("vary") == "Cookie, Accept, Origin", "controller and branch Vary are both preserved")
  response = page("text/html").direct
  check(response.status == 303 and response.header("location") == "/" and response.header("content-type") == null, "redirect response passes through")
  response = page("text/plain").direct
  check(response.status == 204 and response.header("content-type") == null and response.header("vary") == "*", "204 and wildcard Vary")
  response = page("application/json").raw_response
  check(response.status == 201 and response.header("content-type") == "application/json; charset=utf-8" and Json.parse(response.body)[:raw], "raw Response inherits selected MIME")
  controller = page("text/csv")
  response = controller.streamed
  check(orbit.StreamingResponse === response and response.length == 4 and response.header("content-type") == "text/csv" and controller.calls.empty?, "stream producer stays deferred")
  check(orbit.Response === page("application/json").streamed, "unselected streaming branch is not constructed")
  check(Json.parse(page("application/json").short.body)[:short], "inline branch body")
  check(page("application/json").null_json.body == "null", "JSON null remains a represented value")
  check(page("application/json").false_json.body == "false", "JSON false remains a represented value")
  fails(orbit.InvalidResponseError): page("text/html").wrong_html
  fails(orbit.InvalidResponseError): page("application/pdf").wrong_type
  fails(orbit.InvalidResponseError): page("application/json").conflicting_type
  fails(orbit.DoubleRenderError): page("application/json").double_render
  fails(orbit.DoubleRenderError): page("application/json").committed_value
  fails(ArgumentError): page().duplicate
  fails(ArgumentError): page().invalid_default
  ["text/*", "broken", "text/plain\r\nx: bad", "text/plain;q=1", "text/plain; a=1; A=2"].each |mime|:
    fails(ArgumentError): orbit.Format(mime)
  fails(ArgumentError): orbit.Format("text/plain", encode: :unknown)
  request = orbit.Request(headers: {accept: "application/json;q=0"})
  check(request.negotiate([orbit.Format("application/json")]) == null, "public Request negotiation returns null for no match")

def main():
  negotiation_checks()
  representation_checks()
  print "PASS Orbit respond: negotiation, lazy branches, MIME encoders and response lifecycle"
