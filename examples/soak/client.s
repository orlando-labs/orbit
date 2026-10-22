package orbit.example.soak.client

from net.http import Client, Request

export main

class RunStats:
  attr requests
  attr valid_requests
  attr invalid_requests
  attr statuses
  attr valid_statuses
  attr invalid_statuses

  def init():
    @requests = 0
    @valid_requests = 0
    @invalid_requests = 0
    @statuses = {}
    @valid_statuses = {}
    @invalid_statuses = {}

  def expect(response, expected, label, invalid: false):
    @requests += 1
    key = response[:status].to_str
    if invalid:
      @invalid_requests += 1
      @invalid_statuses[key] = (@invalid_statuses[?key] or 0) + 1
    else:
      @valid_requests += 1
      @valid_statuses[key] = (@valid_statuses[?key] or 0) + 1
    @statuses[key] = (@statuses[?key] or 0) + 1
    unless response[:status] == expected:
      raise ArgumentError(
        label + ": expected " + expected.to_str +
        ", got " + response[:status].to_str + ": " + response[:body])
    response

def response_of(response):
  result = null
  try:
    result = {status: response.status, body: response.body_text()}
  ensure:
    response.close!
  result

def request(client, method, url, headers: {}, body: null):
  response_of(client.send(Request(
    method: method,
    url: url,
    headers: headers,
    body: body)))

def json_headers(version: null):
  headers = {"content-type": "application/json"}
  headers["if-match"] = version.to_str if version != null
  headers

def json(response):
  Json.parse(response[:body])

def expect_model_validation(response, field, label):
  body = json(response)
  details = body["error"]["details"]
  valid = body["error"]["code"] == "validation_failed"
  valid = valid and details.any? |detail|: detail["field"] == field
  raise ArgumentError(label + ": model validation details are missing") unless valid
  response

def item_payload(token):
  {
    item: {
      sku: "SOAK-" + token,
      name: "Sputnik soak catalog item " + token,
      description: "Representative durable catalog item used by the Orbit RC soak client.",
      category: "hardware",
      status: "active",
      price_cents: 129900,
      currency: "USD",
      stock_count: 250,
      weight_grams: 1450,
      active: true,
      manufacturer: "Orlando Labs",
      country_code: "US",
      barcode: "90000000" + Time.now.unix_nanoseconds.to_str,
      color: "graphite",
      size: "standard",
      rating_milli: 4750,
      tags: ["sputnik", "soak", "catalog"],
      metadata: {
        source: "sputnik-client",
        batch: token,
        fragile: false
      }
    }
  }

def token(worker, iteration):
  worker.to_str + "-" + iteration.to_str + "-" + Time.now.unix_nanoseconds.to_str

def positive_cycle(client, base_url, worker, iteration, stats):
  payload = item_payload(token(worker, iteration))
  created = stats.expect(
    request(client, :post, base_url + "/v1/items",
      headers: json_headers(),
      body: Json.generate(payload)),
    201,
    "create")
  item = json(created)
  id = item["id"]
  version = item["version"]
  raise ArgumentError("create returned the wrong SKU") unless item["sku"] == payload[:item][:sku]

  shown = stats.expect(
    request(client, :get, base_url + "/v1/items/" + id.to_str),
    200,
    "show")
  shown_item = json(shown)
  unless shown_item["id"] == id and shown_item["manufacturer"] == payload[:item][:manufacturer]:
    raise ArgumentError("show returned the wrong item")

  listed = stats.expect(
    request(client, :get, base_url + "/v1/items?status=active"),
    200,
    "list")
  found = json(listed)["data"].any? |entry|: entry["id"] == id
  raise ArgumentError("list did not contain the created item") unless found

  replacement = item_payload(token(worker, iteration))
  replacement[:item][:sku] = payload[:item][:sku]
  replacement[:item][:name] = "Replaced " + payload[:item][:name]
  replacement[:item][:price_cents] = 139900
  replaced = stats.expect(
    request(client, :put, base_url + "/v1/items/" + id.to_str,
      headers: json_headers(version: version),
      body: Json.generate(replacement)),
    200,
    "replace")
  replaced_item = json(replaced)
  unless replaced_item["name"] == replacement[:item][:name] and replaced_item["price_cents"] == 139900:
    raise ArgumentError("replace did not persist the full resource")
  version = replaced_item["version"]

  patched = stats.expect(
    request(client, :patch, base_url + "/v1/items/" + id.to_str,
      headers: json_headers(version: version),
      body: Json.generate({
        item: {
          status: "paused",
          stock_count: 249,
          tags: ["sputnik", "soak", "patched"]
        }
      })),
    200,
    "patch")
  patched_item = json(patched)
  version = patched_item["version"]
  unless patched_item["status"] == "paused" and patched_item["stock_count"] == 249:
    raise ArgumentError("patch did not update the selected attributes")

  stats.expect(
    request(client, :delete, base_url + "/v1/items/" + id.to_str,
      headers: {"if-match": version.to_str}),
    204,
    "delete")
  stats.expect(
    request(client, :get, base_url + "/v1/items/" + id.to_str),
    404,
    "show deleted item",
    invalid: true)

def oversized_text():
  text = ""
  700.times:
    text += "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  text

def repeated_text(value, count):
  text = ""
  count.times:
    text += value
  text

def expect_invalid_item(client, path, suffix, label, changes, status, stats):
  payload = item_payload(suffix + "-" + Time.now.unix_nanoseconds.to_str)
  changes.each |name, value|:
    payload[:item][name] = value
  response = stats.expect(
    request(client, :post, path,
      headers: json_headers(),
      body: Json.generate(payload)),
    status,
    label,
    invalid: true)
  if status == 422:
    expect_model_validation(response, changes.keys[0].to_str, label)
  response

def negative_suite(client, base_url, worker, iteration, stats):
  path = base_url + "/v1/items"
  suffix = "NEG-" + token(worker, iteration)
  payload = item_payload(suffix)

  stats.expect(
    request(client, :post, path, body: Json.generate(payload)),
    415,
    "missing content type",
    invalid: true)
  stats.expect(
    request(client, :post, path,
      headers: {"content-type": "text/plain"},
      body: Json.generate(payload)),
    415,
    "unsupported content type",
    invalid: true)
  stats.expect(
    request(client, :post, path, headers: json_headers(), body: "{\"item\":"),
    400,
    "malformed JSON",
    invalid: true)
  stats.expect(
    request(client, :post, path, headers: json_headers(), body: "[]"),
    400,
    "array root",
    invalid: true)
  stats.expect(
    request(client, :post, path, headers: json_headers(), body: "{\"other\":{}}"),
    400,
    "missing item root",
    invalid: true)
  stats.expect(
    request(client, :post, path, headers: json_headers(), body: "{\"item\":{\"sku\":\"ABC\"}}"),
    400,
    "missing required attributes",
    invalid: true)

  wrong_type = item_payload(suffix + "-TYPE")
  wrong_type[:item][:price_cents] = "expensive"
  stats.expect(
    request(client, :post, path, headers: json_headers(), body: Json.generate(wrong_type)),
    400,
    "wrong attribute type",
    invalid: true)

  unknown = item_payload(suffix + "-UNKNOWN")
  unknown[:item][:administrator] = true
  stats.expect(
    request(client, :post, path, headers: json_headers(), body: Json.generate(unknown)),
    400,
    "unknown attribute",
    invalid: true)

  too_many_tags = []
  17.times:
    too_many_tags.push!("tag")
  [
    ["invalid SKU", {sku: "lower case"}, 422],
    ["short SKU", {sku: "AB"}, 422],
    ["long SKU", {sku: repeated_text("A", 65)}, 422],
    ["empty name", {name: ""}, 422],
    ["long name", {name: repeated_text("n", 161)}, 422],
    ["empty description", {description: ""}, 422],
    ["long description", {description: repeated_text("d", 2001)}, 422],
    ["unsupported category", {category: "mystery"}, 422],
    ["unsupported status", {status: "deleted"}, 422],
    ["negative price", {price_cents: -1}, 422],
    ["excessive price", {price_cents: 1000000001}, 422],
    ["invalid currency", {currency: "usd"}, 422],
    ["short currency", {currency: "US"}, 422],
    ["negative stock", {stock_count: -1}, 422],
    ["excessive stock", {stock_count: 1000001}, 422],
    ["zero weight", {weight_grams: 0}, 422],
    ["excessive weight", {weight_grams: 10000001}, 422],
    ["empty manufacturer", {manufacturer: ""}, 422],
    ["long manufacturer", {manufacturer: repeated_text("m", 121)}, 422],
    ["invalid country", {country_code: "usa"}, 422],
    ["lowercase country", {country_code: "us"}, 422],
    ["invalid barcode", {barcode: "not-digits"}, 422],
    ["short barcode", {barcode: "1234567"}, 422],
    ["long barcode", {barcode: repeated_text("1", 33)}, 422],
    ["empty color", {color: ""}, 422],
    ["long color", {color: repeated_text("c", 41)}, 422],
    ["empty size", {size: ""}, 422],
    ["long size", {size: repeated_text("s", 41)}, 422],
    ["negative rating", {rating_milli: -1}, 422],
    ["excessive rating", {rating_milli: 5001}, 422],
    ["too many tags", {tags: too_many_tags}, 422],
    ["empty tag", {tags: [""]}, 422],
    ["long tag", {tags: [repeated_text("t", 33)]}, 422],
    ["invalid metadata", {
      metadata: {source: "", batch: suffix, fragile: false}
    }, 422],
    ["long metadata source", {
      metadata: {
        source: repeated_text("s", 65),
        batch: suffix,
        fragile: false
      }
    }, 422],
    ["empty metadata batch", {
      metadata: {source: "client", batch: "", fragile: false}
    }, 422],
    ["long metadata batch", {
      metadata: {
        source: "client",
        batch: repeated_text("b", 65),
        fragile: false
      }
    }, 422],
    ["wrong boolean type", {active: "yes"}, 400],
    ["wrong tag type", {tags: ["valid", 7]}, 400],
    ["wrong metadata type", {
      metadata: {source: "client", batch: suffix, fragile: "no"}
    }, 400],
    ["missing metadata field", {
      metadata: {source: "client", fragile: false}
    }, 400],
    ["unknown metadata field", {
      metadata: {
        source: "client",
        batch: suffix,
        fragile: false,
        hidden: true
      }
    }, 400]
  ].each |entry|:
    expect_invalid_item(
      client, path, suffix, entry[0], entry[1], entry[2], stats)

  oversized = item_payload(suffix + "-LARGE")
  oversized[:item][:description] = oversized_text()
  stats.expect(
    request(client, :post, path, headers: json_headers(), body: Json.generate(oversized)),
    413,
    "oversized body",
    invalid: true)

  created = stats.expect(
    request(client, :post, path, headers: json_headers(), body: Json.generate(payload)),
    201,
    "negative-suite fixture create")
  item = json(created)
  id = item["id"]
  version = item["version"]

  stats.expect(
    request(client, :post, path, headers: json_headers(), body: Json.generate(payload)),
    409,
    "duplicate SKU",
    invalid: true)
  stats.expect(
    request(client, :patch, path + "/" + id.to_str,
      headers: json_headers(),
      body: "{\"item\":{\"stock_count\":1}}"),
    428,
    "missing If-Match",
    invalid: true)
  stats.expect(
    request(client, :patch, path + "/" + id.to_str,
      headers: {"content-type": "application/json", "if-match": "not-a-version"},
      body: "{\"item\":{\"stock_count\":1}}"),
    400,
    "malformed If-Match",
    invalid: true)
  stats.expect(
    request(client, :patch, path + "/" + id.to_str,
      headers: json_headers(version: version + 1),
      body: "{\"item\":{\"stock_count\":1}}"),
    409,
    "stale If-Match",
    invalid: true)
  invalid_patch = stats.expect(
    request(client, :patch, path + "/" + id.to_str,
      headers: json_headers(version: version),
      body: "{\"item\":{\"stock_count\":-1}}"),
    422,
    "invalid stock patch",
    invalid: true)
  expect_model_validation(invalid_patch, "stock_count", "invalid stock patch")
  stats.expect(
    request(client, :patch, path + "/" + id.to_str,
      headers: json_headers(version: version),
      body: "{\"item\":{}}"),
    422,
    "empty patch",
    invalid: true)
  stats.expect(
    request(client, :patch, path + "/" + id.to_str,
      headers: json_headers(version: version),
      body: "{\"item\":{\"unknown\":true}}"),
    400,
    "unknown patch attribute",
    invalid: true)
  stats.expect(
    request(client, :get, path + "/not-an-integer"),
    400,
    "invalid path id",
    invalid: true)
  stats.expect(
    request(client, :get, path + "/999999999"),
    404,
    "unknown item",
    invalid: true)
  stats.expect(
    request(client, :get, path + "?unknown=value"),
    400,
    "unknown query parameter",
    invalid: true)
  stats.expect(
    request(client, :get, path + "?status=deleted"),
    422,
    "unsupported status filter",
    invalid: true)
  stats.expect(
    request(client, :trace, path),
    405,
    "unsupported method",
    invalid: true)
  stats.expect(
    request(client, :get, path, headers: {"host": "invalid.example.test"}),
    403,
    "unauthorized Host",
    invalid: true)
  stats.expect(
    request(client, :put, path + "/999999999",
      headers: json_headers(version: 1),
      body: Json.generate(item_payload(suffix + "-MISSING"))),
    404,
    "replace unknown item",
    invalid: true)

  stats.expect(
    request(client, :delete, path + "/" + id.to_str,
      headers: {}),
    428,
    "delete without If-Match",
    invalid: true)
  stats.expect(
    request(client, :delete, path + "/" + id.to_str,
      headers: {"if-match": version.to_str}),
    204,
    "negative-suite fixture delete")
  stats.expect(
    request(client, :delete, path + "/" + id.to_str,
      headers: {"if-match": version.to_str}),
    404,
    "delete unknown item",
    invalid: true)

def arguments():
  parser = ArgParser()
  parser.name("orbit-soak-client")
  parser.arg("--base-url", name: "base_url", default: "http://127.0.0.1:3300")
  parser.arg("--iterations", type: Int, default: 1)
  parser.arg("--worker", type: Int, default: 0)
  parser.arg("--mode", default: "mixed")
  parser.arg("--negative-every", name: "negative_every", type: Int, default: 25)
  parser.arg("--duration-seconds", name: "duration_seconds", type: Int, default: 0)
  parser.parse_or_raise()

def normalized_base_url(value):
  return value.slice(0...(value.length - 1)) if value.ends_with?("/")
  value

def main():
  args = arguments()
  unless ["positive", "negative", "mixed"].include?(args["mode"]):
    raise ArgumentError("mode must be positive, negative, or mixed")
  raise ArgumentError("iterations must be positive") unless args["iterations"] > 0
  raise ArgumentError("negative-every must be positive") unless args["negative_every"] > 0
  raise ArgumentError("duration-seconds must not be negative") unless args["duration_seconds"] >= 0

  client = Client(
    timeout: 20.0,
    pool_timeout: 5.0,
    idle_timeout: 30.0,
    max_idle_connections: 16,
    max_idle_per_origin: 8,
    max_active_per_origin: 16)
  stats = RunStats()
  started = Time.monotonic
  base_url = normalized_base_url(args["base_url"])
  index = 0
  running = true
  try:
    while running:
      positive_cycle(client, base_url, args["worker"], index, stats) unless args["mode"] == "negative"
      if args["mode"] == "negative" or (args["mode"] == "mixed" and index % args["negative_every"] == 0):
        negative_suite(client, base_url, args["worker"], index, stats)
      index += 1
      if args["duration_seconds"] > 0:
        elapsed = (Time.monotonic - started).total_nanoseconds // 1000000000
        running = elapsed < args["duration_seconds"]
      else:
        running = index < args["iterations"]
  ensure:
    client.close!

  elapsed = (Time.monotonic - started).total_nanoseconds.to_float / 1000000000.0
  io.stdout.write_line(Json.generate({
    schema: "orbit.soak-client.result.v1",
    worker: args["worker"],
    mode: args["mode"],
    iterations: index,
    requests: stats.requests,
    valid_requests: stats.valid_requests,
    invalid_requests: stats.invalid_requests,
    statuses: stats.statuses,
    valid_statuses: stats.valid_statuses,
    invalid_statuses: stats.invalid_statuses,
    elapsed_seconds: elapsed,
    requests_per_second: stats.requests.to_float / elapsed
  }))
  null
