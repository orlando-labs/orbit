package orbit.assets

import orbit

export StaticFiles

def _part?(part):
  return false unless part.present? and part.bytesize <= 2048
  return false if part.starts_with?(".") or part.contains?("/") or part.contains?("\\")
  return false if part.contains?(":") or part.contains?("%")
  bytes = part.bytes
  index = 0
  while index < bytes.count:
    return false if bytes[index] < 32 or bytes[index] == 127
    index += 1
  true

def _parts(path):
  return null unless Str === path and path.starts_with?("/") and path.bytesize <= 8192
  return [] if path == "/"
  parts = path.slice(1...path.length).split("/")
  return null if parts.count > 128
  decoded = try:
    parts.map: Url.percent_decode(_1)
  rescue UrlDecodeError:
    null
  return null unless decoded
  valid = decoded.all?: _part?(_1)
  if valid then decoded else null

def _metadata(path):
  current = if path.starts_with?("/") then "/" else ""
  metadata = null
  path.split("/").each |part|:
    next if part == "" or part == "."
    current += (if current == "" or current == "/" then "" else "/") + part
    metadata = try:
      fs.metadata(current)
    rescue FileNotFoundError:
      null
    return null unless metadata
    return null if metadata.symlink?
  metadata

def _content_type(path):
  types = {
    svg: "image/svg+xml", ico: "image/x-icon", png: "image/png",
    jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif",
    webp: "image/webp", avif: "image/avif", css: "text/css; charset=utf-8",
    js: "text/javascript; charset=utf-8", mjs: "text/javascript; charset=utf-8",
    json: "application/json", txt: "text/plain; charset=utf-8",
    html: "text/html; charset=utf-8", woff: "font/woff", woff2: "font/woff2",
    ttf: "font/ttf", pdf: "application/pdf"
  }
  types[?path.split(".").last.downcase] or "application/octet-stream"

class StaticFiles:
  def init(root: "./assets", at: "/", @chunk_size: 65536,
    cache_control: "public, max-age=3600"):
    unless Str === root and root.present?:
      raise ArgumentError("static asset root must be a directory path")
    @root = fs.Path(root).normalize.to_str
    metadata = _metadata(@root)
    raise ArgumentError("static asset root must be an existing directory without symlinks") unless metadata and metadata.dir?
    parts = _parts(at)
    raise ArgumentError("static asset mount must be an absolute URL path") unless parts
    @prefix = if parts.empty? then "/" else "/" + parts.join("/") + "/"
    unless Int === @chunk_size and @chunk_size > 0 and @chunk_size <= 1048576:
      raise ArgumentError("static asset chunk_size must be between one byte and 1 MiB")
    @headers = orbit.Headers({"cache-control": cache_control})

  def call(request, next):
    return next(request) unless ["GET", "HEAD"].include?(request.method)
    path = request.path
    return next(request) unless path.starts_with?(@prefix) and path.length > @prefix.length
    relative = path.slice(@prefix.length...path.length)
    parts = _parts("/" + relative)
    return next(request) unless parts and parts.present?
    file = @root + "/" + parts.join("/")
    metadata = _metadata(file)
    return next(request) unless metadata and metadata.file?
    headers = @headers.set("content-type", _content_type(file))
    size = @chunk_size
    orbit.stream(length: metadata.size, headers: headers) |body|:
      fs.File.open(file, :read) |input|:
        input.each_chunk(size: size) |chunk|: body.write(chunk)
