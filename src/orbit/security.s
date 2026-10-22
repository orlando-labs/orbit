package orbit.security

import orbit
import io

export CookieLimits, CookieJar, SetCookie
export Aead, SignedCookieCodec, SessionCodec
export CorsMiddleware, CsrfProtection, CsrfMiddleware
export SecurityError, CookieError, SessionError, CsrfError

class SecurityError < orbit.OrbitError
class CookieError < SecurityError
class SessionError < SecurityError
class CsrfError < SecurityError

def _bytes(value):
  return value if Bytes === value
  return Bytes.new(value) if Str === value
  raise TypeError("security byte input must be Str or Bytes")

def _concat(parts):
  size = 0
  parts.each |part|:
    size += part.count()
  buffer = io.ByteBuffer(size)
  parts.each |part|:
    buffer.put_all!(part)
  buffer.bytes()

def _zero_bytes(count):
  buffer = io.ByteBuffer(count)
  count.times:
    buffer.put!(0)
  buffer.bytes()

def _constant_bytes_equal(left, right):
  return false unless Bytes === left and Bytes === right
  return false unless left.count() == right.count()
  different = false
  index = 0
  while index < left.count():
    different = true unless left[index] == right[index]
    index += 1
  not different

def _constant_text_equal(left, right):
  return false unless Str === left and Str === right
  _constant_bytes_equal(Bytes.new(left), Bytes.new(right))

def _u32(value):
  value % 4294967296

def _rotl32(value, count):
  lower = (value * (2 ** count)) % 4294967296
  upper = value // (2 ** (32 - count))
  lower + upper

def _quarter!(state, a, b, c, d):
  state[a] = _u32(state[a] + state[b])
  state[d] = _rotl32(state[d] ^ state[a], 16)
  state[c] = _u32(state[c] + state[d])
  state[b] = _rotl32(state[b] ^ state[c], 12)
  state[a] = _u32(state[a] + state[b])
  state[d] = _rotl32(state[d] ^ state[a], 8)
  state[c] = _u32(state[c] + state[d])
  state[b] = _rotl32(state[b] ^ state[c], 7)

def _word_le(bytes, offset):
  bytes[offset] + bytes[offset + 1] * 256 + bytes[offset + 2] * 65536 + bytes[offset + 3] * 16777216

def _put_word_le!(buffer, word):
  buffer.put!(word % 256)
  buffer.put!((word // 256) % 256)
  buffer.put!((word // 65536) % 256)
  buffer.put!((word // 16777216) % 256)

def _chacha_block(key, nonce, counter):
  state = [
    1634760805, 857760878, 2036477234, 1797285236,
    _word_le(key, 0), _word_le(key, 4), _word_le(key, 8), _word_le(key, 12),
    _word_le(key, 16), _word_le(key, 20), _word_le(key, 24), _word_le(key, 28),
    counter, _word_le(nonce, 0), _word_le(nonce, 4), _word_le(nonce, 8)
  ]
  working = state.copy
  10.times:
    _quarter!(working, 0, 4, 8, 12)
    _quarter!(working, 1, 5, 9, 13)
    _quarter!(working, 2, 6, 10, 14)
    _quarter!(working, 3, 7, 11, 15)
    _quarter!(working, 0, 5, 10, 15)
    _quarter!(working, 1, 6, 11, 12)
    _quarter!(working, 2, 7, 8, 13)
    _quarter!(working, 3, 4, 9, 14)
  buffer = io.ByteBuffer(64)
  index = 0
  while index < 16:
    _put_word_le!(buffer, _u32(working[index] + state[index]))
    index += 1
  buffer.bytes()

def _chacha_xor(key, nonce, input, counter):
  output = io.ByteBuffer(input.count())
  offset = 0
  block_counter = counter
  while offset < input.count():
    stream = _chacha_block(key, nonce, block_counter)
    block_size = input.count() - offset
    block_size = 64 if block_size > 64
    index = 0
    while index < block_size:
      output.put!(input[offset + index] ^ stream[index])
      index += 1
    offset += block_size
    block_counter += 1
  output.bytes()

def _big_le(bytes, offset, count):
  value = BigInt(0)
  multiplier = BigInt(1)
  index = 0
  while index < count:
    value = value + BigInt(bytes[offset + index]) * multiplier
    multiplier = multiplier * 256
    index += 1
  value

def _poly1305_tag(one_time_key, message):
  r_bytes = []
  index = 0
  while index < 16:
    byte = one_time_key[index]
    byte = byte % 16 if index == 3 or index == 7 or index == 11 or index == 15
    byte = (byte // 4) * 4 if index == 4 or index == 8 or index == 12
    r_bytes.push!(byte)
    index += 1
  r = BigInt(0)
  multiplier = BigInt(1)
  r_bytes.each |byte|:
    r = r + BigInt(byte) * multiplier
    multiplier = multiplier * 256
  s = _big_le(one_time_key, 16, 16)
  prime = (BigInt(2) ** 130) - 5
  accumulator = BigInt(0)
  offset = 0
  while offset < message.count():
    count = message.count() - offset
    count = 16 if count > 16
    number = _big_le(message, offset, count) + (BigInt(2) ** (8 * count))
    accumulator = ((accumulator + number) * r) % prime
    offset += count
  tag_number = (accumulator + s) % (BigInt(2) ** 128)
  tag = io.ByteBuffer(16)
  16.times:
    tag.put!((tag_number % 256).to_int())
    tag_number = tag_number / 256
  tag.bytes()

def _pad16(bytes):
  remainder = bytes.count() % 16
  return bytes if remainder == 0
  _concat([bytes, _zero_bytes(16 - remainder)])

def _u64_le(value):
  buffer = io.ByteBuffer(8)
  remaining = BigInt(value)
  8.times:
    buffer.put!((remaining % 256).to_int())
    remaining = remaining / 256
  buffer.bytes()

def _aead_tag(key, nonce, aad, ciphertext):
  one_time_key = _chacha_block(key, nonce, 0).slice(0, 32)
  mac_data = _concat([
    _pad16(aad),
    _pad16(ciphertext),
    _u64_le(aad.count()),
    _u64_le(ciphertext.count())
  ])
  _poly1305_tag(one_time_key, mac_data)

class Aead:
  def init(secret):
    material = _bytes(secret)
    if material.count() < 32:
      raise ArgumentError("AEAD secret must contain at least 32 bytes")
    @key = if material.count() == 32 then material else Digest.sha256(material)

  def seal_bytes(plaintext, aad: Bytes.new(""), nonce: null):
    plain = _bytes(plaintext)
    associated = _bytes(aad)
    selected_nonce = nonce or SecureRandom.bytes(12)
    unless Bytes === selected_nonce and selected_nonce.count() == 12:
      raise ArgumentError("ChaCha20-Poly1305 nonce must contain 12 bytes")
    ciphertext = _chacha_xor(@key, selected_nonce, plain, 1)
    tag = _aead_tag(@key, selected_nonce, associated, ciphertext)
    _concat([selected_nonce, ciphertext, tag])

  def open_bytes(sealed, aad: Bytes.new("")):
    input = _bytes(sealed)
    if input.count() < 28:
      raise SessionError("sealed value is too short")
    nonce = input.slice(0, 12)
    ciphertext = input.slice(12, input.count() - 28)
    supplied_tag = input.slice(input.count() - 16, 16)
    expected_tag = _aead_tag(@key, nonce, _bytes(aad), ciphertext)
    unless _constant_bytes_equal(supplied_tag, expected_tag):
      raise SessionError("sealed value authentication failed")
    _chacha_xor(@key, nonce, ciphertext, 1)

  def seal(plaintext, aad: Bytes.new("")):
    Base64Url.encode(seal_bytes(plaintext, aad: aad))

  def open(token, aad: Bytes.new("")):
    decoded = try:
      Base64Url.decode(token)
    rescue CodecDecodeError:
      raise SessionError("sealed value is malformed")
    open_bytes(decoded, aad: aad)

class CookieLimits:
  attr max_header_bytes
  attr max_cookies
  attr max_name_bytes
  attr max_value_bytes

  def init(
    @max_header_bytes: 4096,
    @max_cookies: 50,
    @max_name_bytes: 128,
    @max_value_bytes: 2048
  ):
    {
      max_header_bytes: @max_header_bytes,
      max_cookies: @max_cookies,
      max_name_bytes: @max_name_bytes,
      max_value_bytes: @max_value_bytes
    }.each |name, value|:
      unless Int === value and value > 0:
        raise ArgumentError(name.to_str + " must be a positive Int")

def _cookie_name_valid?(name):
  return false if name.empty?()
  allowed = "!#$%&'*+-.^_`|~"
  name.chars.all? |char|:
    letter = char.downcase != char.upcase
    digit = "0123456789".contains?(char)
    letter or digit or allowed.contains?(char)

def _cookie_value_valid?(value):
  value.chars.all? |char|:
    code = char.bytes[0]
    code == 33 or (code >= 35 and code <= 43) or (code >= 45 and code <= 58) or (code >= 60 and code <= 126)

class CookieJar:
  def init(values):
    @values = values.freeze

  class_method def parse(header, limits: CookieLimits()):
    return CookieJar({}) if header == null or header == ""
    unless Str === header:
      raise CookieError("Cookie header must be a string")
    if header.bytesize > limits.max_header_bytes:
      raise CookieError("Cookie header exceeds the configured byte limit")
    values = {}
    pairs = header.split(";")
    if pairs.count > limits.max_cookies:
      raise CookieError("Cookie header exceeds the configured cookie count")
    pairs.each |raw|:
      pair = raw.trim
      equals = pair.index("=")
      unless equals and equals > 0:
        raise CookieError("Cookie pair is malformed")
      name = pair.slice(0...equals)
      value = pair.slice(equals + 1...pair.length)
      unless _cookie_name_valid?(name) and name.bytesize <= limits.max_name_bytes:
        raise CookieError("Cookie name is invalid or too long")
      unless _cookie_value_valid?(value) and value.bytesize <= limits.max_value_bytes:
        raise CookieError("Cookie value is invalid or too long")
      if values.has_key?(name):
        raise CookieError("duplicate Cookie name: " + name)
      values.store!(name, value)
    CookieJar(values)

  def get(name):
    @values[?name.to_str]

  def include?(name):
    @values.has_key?(name.to_str)

  def to_map():
    @values

class SetCookie:
  def init(
    name,
    value,
    path: "/",
    domain: null,
    secure: true,
    http_only: true,
    same_site: :lax,
    max_age: null
  ):
    @name = name.to_str
    @value = value.to_str
    unless _cookie_name_valid?(@name) and @name.bytesize <= 128:
      raise CookieError("Set-Cookie name is invalid or too long")
    unless _cookie_value_valid?(@value) and @name.bytesize + @value.bytesize <= 4096:
      raise CookieError("Set-Cookie value is invalid or too long")
    unless Str === path and path.starts_with?("/") and not path.contains?(";") and not path.contains?("\r") and not path.contains?("\n"):
      raise CookieError("Set-Cookie Path must be an absolute path")
    if domain:
      normalized_domain = domain.to_str.downcase
      unless normalized_domain == domain.to_str and not normalized_domain.starts_with?(".") and normalized_domain.length <= 253:
        raise CookieError("Set-Cookie Domain must be canonical and must not start with a dot")
      valid_domain = normalized_domain.split(".").all? |label|:
        label.present?() and label.length <= 63 and not label.starts_with?("-") and not label.ends_with?("-") and label.chars.all? |char|:
          "abcdefghijklmnopqrstuvwxyz0123456789-".contains?(char)
      unless valid_domain:
        raise CookieError("Set-Cookie Domain is malformed")
    unless Bool === secure and Bool === http_only:
      raise CookieError("Set-Cookie secure/http_only flags must be Bool")
    unless same_site == :strict or same_site == :lax or same_site == :none:
      raise CookieError("SameSite must be :strict, :lax, or :none")
    if same_site == :none and not secure:
      raise CookieError("SameSite=None requires Secure")
    if @name.starts_with?("__Secure-") and not secure:
      raise CookieError("__Secure- cookies require Secure")
    if @name.starts_with?("__Host-") and (not secure or domain or path != "/"):
      raise CookieError("__Host- cookies require Secure, Path=/, and no Domain")
    unless max_age == null or (Int === max_age and max_age >= 0):
      raise CookieError("Max-Age must be a non-negative Int or null")
    @path = path
    @domain = domain
    @secure = secure
    @http_only = http_only
    @same_site = same_site
    @max_age = max_age

  def header_value():
    parts = [@name + "=" + @value, "Path=" + @path]
    parts.push!("Domain=" + @domain.to_str) if @domain
    parts.push!("Max-Age=" + @max_age.to_str) if @max_age != null
    parts.push!("Secure") if @secure
    parts.push!("HttpOnly") if @http_only
    same_site = "Lax"
    same_site = "Strict" if @same_site == :strict
    same_site = "None" if @same_site == :none
    parts.push!("SameSite=" + same_site)
    parts.join("; ")

  def to_str():
    header_value()

  def str():
    header_value()

class SignedCookieCodec:
  def init(secret:, old_secrets: [], max_payload_bytes: 2048):
    unless Array === old_secrets:
      raise ArgumentError("old_secrets must be an Array")
    unless Int === max_payload_bytes and max_payload_bytes > 0 and max_payload_bytes <= 65536:
      raise ArgumentError("max_payload_bytes must be between 1 and 65536")
    @keys = ([secret] + old_secrets).map |material|:
      bytes = _bytes(material)
      if bytes.count() < 32:
        raise ArgumentError("signed-cookie secrets must contain at least 32 bytes")
      Digest.sha256(bytes)
    .freeze
    @max_payload_bytes = max_payload_bytes

  def encode(value):
    payload = _bytes(value)
    if payload.count() > @max_payload_bytes:
      raise CookieError("signed cookie payload exceeds the configured limit")
    encoded = Base64Url.encode(payload)
    message = "v1." + encoded
    tag = Digest.hmac_sha256(@keys[0], Bytes.new(message)).hex()
    message + "." + tag

  def decode(token):
    unless Str === token and token.bytesize <= (@max_payload_bytes + 96) * 2:
      raise CookieError("signed cookie is invalid or too large")
    parts = token.split(".")
    unless parts.count == 3 and parts[0] == "v1" and parts[2].length == 64:
      raise CookieError("signed cookie is malformed")
    message = parts[0] + "." + parts[1]
    valid = @keys.any? |key|:
      expected = Digest.hmac_sha256(key, Bytes.new(message)).hex()
      _constant_text_equal(parts[2], expected)
    unless valid:
      raise CookieError("signed cookie authentication failed")
    decoded = try:
      Base64Url.decode(parts[1])
    rescue CodecDecodeError:
      raise CookieError("signed cookie payload is malformed")
    if decoded.count() > @max_payload_bytes:
      raise CookieError("signed cookie payload exceeds the configured limit")
    decoded

class SessionCodec:
  def init(secret:, old_secrets: [], max_payload_bytes: 3072, ttl: 3600, clock_skew: 60):
    unless Array === old_secrets:
      raise ArgumentError("old_secrets must be an Array")
    unless Int === max_payload_bytes and max_payload_bytes > 0 and max_payload_bytes <= 65536:
      raise ArgumentError("max_payload_bytes must be between 1 and 65536")
    unless Int === ttl and ttl > 0:
      raise ArgumentError("session ttl must be a positive Int")
    unless Int === clock_skew and clock_skew >= 0 and clock_skew <= 300:
      raise ArgumentError("session clock_skew must be between 0 and 300 seconds")
    @codecs = ([secret] + old_secrets).map |material|: Aead(material) .freeze
    @max_payload_bytes = max_payload_bytes
    @ttl = ttl
    @clock_skew = clock_skew
    @aad = Bytes.new("orbit.session.v1")

  def encode(data, now: null):
    issued_at = if now == null then Time.now.unix_seconds else now
    unless Int === issued_at:
      raise ArgumentError("session now must be Unix seconds")
    payload = Json.generate({
      "data": data,
      "issued_at": issued_at,
      "expires_at": issued_at + @ttl
    })
    if payload.bytesize > @max_payload_bytes:
      raise SessionError("session payload exceeds the configured limit")
    @codecs[0].seal(Bytes.new(payload), aad: @aad)

  def _try_open(codec, token):
    try:
      codec.open(token, aad: @aad)
    rescue SessionError:
      null

  def decode(token, now: null):
    current = if now == null then Time.now.unix_seconds else now
    unless Str === token and token.bytesize <= (@max_payload_bytes + 128) * 2:
      raise SessionError("session token is invalid or too large")
    plaintext = null
    @codecs.each |codec|:
      if plaintext == null:
        plaintext = _try_open(codec, token)
    unless plaintext:
      raise SessionError("session token authentication failed")
    if plaintext.count() > @max_payload_bytes:
      raise SessionError("session payload exceeds the configured limit")
    payload = try:
      Json.parse(plaintext.to_str())
    rescue JsonParseError:
      raise SessionError("session payload is malformed")
    unless Map === payload or StrictMap === payload:
      raise SessionError("session payload must be an object")
    issued_at = payload[?"issued_at"]
    expires_at = payload[?"expires_at"]
    unless Int === issued_at and Int === expires_at and expires_at > issued_at:
      raise SessionError("session timestamps are invalid")
    if issued_at > current + @clock_skew or expires_at < current:
      raise SessionError("session token is expired or not yet valid")
    payload[?"data"]

def _origin_valid?(origin):
  return false unless Str === origin
  return false if origin.contains?(" ") or origin.contains?("\t") or origin.contains?("\r") or origin.contains?("\n")
  prefix = if origin.starts_with?("https://") then "https://" else (if origin.starts_with?("http://") then "http://" else null)
  return false unless prefix
  authority = origin.slice(prefix.length...origin.length)
  return false if authority.empty?() or authority.contains?("/") or authority.contains?("?") or authority.contains?("#") or authority.contains?("@")
  true

def _vary_origin(response):
  existing = response.header("vary")
  return orbit.with_response_header(response, "vary", "Origin") unless existing
  values = existing.split(",").map: _1.trim.downcase
  return response if values.include?("origin") or values.include?("*")
  orbit.with_response_header(response, "vary", existing + ", Origin")

class CorsMiddleware:
  def init(
    origins:,
    methods: ["GET", "HEAD", "POST"],
    headers: ["content-type"],
    expose_headers: [],
    credentials: false,
    max_age: 600
  ):
    unless Array === origins and origins.present?:
      raise ArgumentError("CORS origins must be a non-empty Array")
    @origins = origins.map |origin|:
      unless origin == "*" or _origin_valid?(origin):
        raise ArgumentError("invalid CORS origin")
      origin
    .freeze
    unless @origins.count == 1 or not @origins.include?("*"):
      raise ArgumentError("CORS wildcard origin cannot be combined with other origins")
    if credentials and @origins.include?("*"):
      raise ArgumentError("credentialed CORS cannot use wildcard origin")
    unless Bool === credentials:
      raise ArgumentError("CORS credentials must be Bool")
    @methods = methods.map: _1.to_str.upcase .freeze
    @headers = headers.map: _1.to_str.downcase .freeze
    @expose_headers = expose_headers.map: _1.to_str.downcase .freeze
    @credentials = credentials
    unless Int === max_age and max_age >= 0 and max_age <= 86400:
      raise ArgumentError("CORS max_age must be between 0 and 86400")
    @max_age = max_age

  def call(request, next):
    origin = request.header("origin")
    return next(request) unless origin
    allowed = @origins.include?("*") or @origins.include?(origin)
    preflight = request.method == "OPTIONS" and request.header("access-control-request-method")
    if preflight:
      return orbit.render(text: "forbidden", status: :forbidden) unless allowed
      requested_method = request.header("access-control-request-method").to_str.upcase
      return orbit.render(text: "forbidden", status: :forbidden) unless @methods.include?(requested_method)
      requested_headers = []
      raw_headers = request.header("access-control-request-headers")
      if raw_headers:
        requested_headers = raw_headers.split(",").map: _1.trim.downcase
        return orbit.render(text: "bad request", status: :bad_request) if requested_headers.any? |name|: name.empty?
        return orbit.render(text: "forbidden", status: :forbidden) if requested_headers.any? |name|: not @headers.include?(name)
      response = orbit.Response(status: :no_content, body: "")
      response = orbit.with_response_header(response, "access-control-allow-methods", @methods.join(", "))
      if requested_headers.present?:
        response = orbit.with_response_header(response, "access-control-allow-headers", requested_headers.join(", "))
      response = orbit.with_response_header(response, "access-control-max-age", @max_age.to_str)
      return _cors_headers(response, origin)
    response = orbit.normalize_response(next(request))
    return response unless allowed
    _cors_headers(response, origin)

  def _cors_headers(response, origin):
    selected = if @origins.include?("*") then "*" else origin
    result = orbit.with_response_header(response, "access-control-allow-origin", selected)
    if @credentials:
      result = orbit.with_response_header(result, "access-control-allow-credentials", "true")
    if @expose_headers.present?:
      result = orbit.with_response_header(result, "access-control-expose-headers", @expose_headers.join(", "))
    _vary_origin(result)

class CsrfProtection:
  def init(secret):
    material = _bytes(secret)
    if material.count() < 32:
      raise ArgumentError("CSRF secret must contain at least 32 bytes")
    @key = Digest.sha256(material)

  def token(session_id):
    nonce = SecureRandom.base64url(24)
    mac = Digest.hmac_sha256(@key, Bytes.new(session_id.to_str + "." + nonce)).hex()
    "v1." + nonce + "." + mac

  def valid?(token, session_id):
    return false unless Str === token and token.bytesize <= 160
    parts = token.split(".")
    return false unless parts.count == 3 and parts[0] == "v1"
    nonce = parts[1]
    supplied = parts[2]
    return false unless nonce.length == 32 and supplied.length == 64
    return false unless nonce.chars.all? |char|: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_".contains?(char)
    return false unless supplied.chars.all? |char|: "0123456789abcdef".contains?(char)
    expected = Digest.hmac_sha256(@key, Bytes.new(session_id.to_str + "." + nonce)).hex()
    _constant_text_equal(supplied, expected)

class CsrfMiddleware:
  def init(
    secret:,
    session_cookie: "orbit-session",
    token_cookie: "orbit-csrf",
    header: "x-csrf-token",
    cookie_limits: CookieLimits()
  ):
    @protection = CsrfProtection(secret)
    @session_cookie = session_cookie
    @token_cookie = token_cookie
    @header = header.downcase
    @cookie_limits = cookie_limits

  def _parse_cookies(request):
    try:
      CookieJar.parse(request.header("cookie"), limits: @cookie_limits)
    rescue CookieError:
      null

  def call(request, next):
    jar = _parse_cookies(request)
    return orbit.render(text: "bad request", status: :bad_request) unless jar
    session_id = jar.get(@session_cookie) or "anonymous"
    safe = ["GET", "HEAD", "OPTIONS"].include?(request.method)
    unless safe:
      fetch_site = request.header("sec-fetch-site")
      return orbit.render(text: "forbidden", status: :forbidden) if fetch_site and fetch_site.downcase == "cross-site"
      origin = request.header("origin")
      return orbit.render(text: "forbidden", status: :forbidden) unless origin and origin == request.origin()
      cookie_token = jar.get(@token_cookie)
      header_token = request.header(@header)
      valid = cookie_token and header_token and _constant_text_equal(cookie_token, header_token)
      valid = valid and @protection.valid?(header_token, session_id)
      return orbit.render(text: "forbidden", status: :forbidden) unless valid
      return next(request)
    response = orbit.normalize_response(next(request))
    existing = jar.get(@token_cookie)
    return response if existing and @protection.valid?(existing, session_id)
    token = @protection.token(session_id)
    cookie = SetCookie(
      @token_cookie,
      token,
      secure: request.secure?(),
      http_only: false,
      same_site: :lax)
    orbit.with_response_header(response, "set-cookie", cookie.header_value(), append: true)
