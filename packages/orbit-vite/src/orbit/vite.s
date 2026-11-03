package orbit.vite

from orbit import ContentSecurityPolicy, Origin
from orbit.html import html, url, join

export Assets, ManifestError

class ManifestError < Exception:
  attr message
  def init(@message)

def _controls?(value):
  bytes = value.bytes
  index = 0
  while index < bytes.count:
    return true if bytes[index] <= 32 or bytes[index] == 127
    index += 1
  false

def _path(value):
  unless Str === value and value.present? and value.bytesize <= 2048:
    raise ManifestError("Vite paths must be nonempty bounded strings")
  if value.starts_with?("/") or value.contains?("\\") or value.contains?(":") or value.contains?("%") or value.contains?("?") or value.contains?("#"):
    raise ManifestError("Vite paths must be relative asset paths")
  if _controls?(value):
    raise ManifestError("Vite paths cannot contain whitespace or control characters")
  invalid_component = value.split("/").any? |part|: ["", ".", ".."].include?(part)
  if invalid_component:
    raise ManifestError("Vite paths cannot contain empty, dot or parent components")
  value

def _hmr_origin(value):
  unless Str === value and (value.starts_with?("ws://") or value.starts_with?("wss://")):
    raise ArgumentError("Vite hmr_origin must be a WS(S) origin")
  Origin("http" + value.slice(2...value.length)).websocket

def _nonce(value):
  unless value == null or (Str === value and value.present? and value.bytesize <= 256 and value.contains_only?("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/_=-")):
    raise ArgumentError("Vite nonce must be a bounded CSP nonce")
  value

def _script(path, nonce):
  if nonce:
    html'<script type="module" src="#{url(path)}" crossorigin="anonymous" nonce="#{nonce}"></script>'
  else:
    html'<script type="module" src="#{url(path)}" crossorigin="anonymous"></script>'

def _link(kind, path, nonce):
  if nonce:
    html'<link rel="#{kind}" href="#{url(path)}" crossorigin="anonymous" nonce="#{nonce}">'
  else:
    html'<link rel="#{kind}" href="#{url(path)}" crossorigin="anonymous">'

class Assets:
  attr mode
  attr dev_origin
  attr hmr_origin
  attr csp

  def init(
    @mode: :production,
    frontend: "./frontend",
    entries: ["src/main.ts"],
    dev_origin: "http://127.0.0.1:5173",
    hmr_origin: null,
    asset_base: "/",
    dist: "dist",
    manifest: ".vite/manifest.json",
    max_manifest_bytes: 1048576,
    max_chunks: 4096
  ):
    raise ArgumentError("Vite mode must be :development or :production") unless [:development, :production].include?(@mode)
    unless Array === entries and entries.present? and entries.count <= 32:
      raise ArgumentError("Vite entries must contain between one and 32 paths")
    @entries = entries.map |entry|: _path(entry) .freeze
    unless Str === frontend and frontend.present?:
      raise ArgumentError("Vite frontend must be a directory path")
    @root = fs.Path(frontend).normalize.to_str
    @dist = @root + "/" + _path(dist)
    unless Str === asset_base and asset_base.starts_with?("/") and not asset_base.starts_with?("//") and asset_base.ends_with?("/"):
      raise ArgumentError("Vite asset_base must be a same-origin path ending in /")
    _path(asset_base.slice(1...asset_base.length - 1)) unless asset_base == "/"
    @asset_base = asset_base
    @csp = ContentSecurityPolicy(script_src: [:self], style_src: [:self],
      connect_src: [:self], form_action: [:self])
    if @mode == :development:
      dev = Origin(dev_origin)
      @dev_origin = dev.to_str
      @hmr_origin = if hmr_origin then _hmr_origin(hmr_origin) else dev.websocket
      @csp = @csp.with(script_src: [:self, @dev_origin],
        style_src: [:self, :unsafe_inline],
        connect_src: [:self, @dev_origin, @hmr_origin])
    unless Int === max_manifest_bytes and max_manifest_bytes > 0 and max_manifest_bytes <= 4194304:
      raise ArgumentError("Vite manifest limit must be between one byte and 4 MiB")
    unless Int === max_chunks and max_chunks > 0 and max_chunks <= 16384:
      raise ArgumentError("Vite chunk limit must be between one and 16384")
    if @mode == :production:
      path = _file(_path(manifest))
      @manifest = try:
        Json.parse(fs.read_text(path, limit: max_manifest_bytes), duplicate_keys: :reject)
      rescue JsonParseError:
        raise ManifestError("Vite manifest cannot be read as bounded, duplicate-free JSON")
      _validate(max_chunks)

  # A release directory is immutable while serving. Check every component,
  # including the configured root, so symlinks cannot escape the asset root.
  def _file(relative):
    target = fs.Path(@dist + "/" + _path(relative)).normalize.to_str
    current = if target.starts_with?("/") then "/" else ""
    target.split("/").each |part|:
      next if part == "" or part == "."
      current += (if current == "" or current == "/" then "" else "/") + part
      raise ManifestError("Vite asset is missing: " + relative) unless fs.exists?(current)
      raise ManifestError("Vite asset paths cannot contain symlinks") if fs.metadata(current).symlink?
    raise ManifestError("Vite asset is not a regular file: " + relative) unless fs.file?(target)
    target

  def _list(chunk, name):
    values = if chunk.has_key?(name) then chunk[name] else []
    unless Array === values and values.count <= 4096:
      raise ManifestError("Vite manifest lists must be bounded arrays")
    values.each: _path(_1)
    values

  def _validate(limit):
    unless Map === @manifest and @manifest.present? and @manifest.count <= limit:
      raise ManifestError("Vite manifest must be a nonempty bounded map")
    @manifest.each |key, chunk|:
      _path(key)
      raise ManifestError("Vite manifest chunks must be maps") unless Map === chunk
      _file(_path(chunk[?:file]))
      ["css", "assets"].each |field|:
        _list(chunk, field).each: _file(_1)
      ["imports", "dynamicImports"].each |field|:
        _list(chunk, field).each |dependency|:
          raise ManifestError("Vite manifest references an unknown chunk") unless @manifest.has_key?(dependency)
    @entries.each |entry|:
      chunk = @manifest[?entry]
      raise ManifestError("Vite entry is missing or is not an entry: " + entry) unless chunk and chunk[?:isEntry] == true
      unless chunk[:file].ends_with?(".js") or chunk[:file].ends_with?(".css"):
        raise ManifestError("Vite entries must emit JavaScript or CSS")

  def _imports(key, seen, result, depth = 0):
    raise ManifestError("Vite imports exceed 128 nesting levels") if depth > 128
    _list(@manifest[key], "imports").each |dependency|:
      next if seen.has_key?(dependency)
      seen[dependency] = true
      _imports(dependency, seen, result, depth + 1)
      result.push!(dependency)

  def tags(entry: null, nonce: null, preload: true):
    selected = entry or @entries[0]
    raise ArgumentError("Vite entry was not configured") unless @entries.include?(selected)
    _nonce(nonce)
    raise ArgumentError("Vite preload must be Bool") unless Bool === preload
    if @mode == :development:
      return join([_script(@dev_origin + "/@vite/client", nonce), _script(@dev_origin + "/" + selected, nonce)])
    imports = []
    seen = {}
    seen[selected] = true
    _imports(selected, seen, imports)
    css = {}
    parts = []
    ([selected] + imports).each |key|:
      _list(@manifest[key], "css").each |path|:
        next if css.has_key?(path)
        css[path] = true
        parts.push!(_link("stylesheet", @asset_base + path, nonce))
    entry_file = @manifest[selected][:file]
    if entry_file.ends_with?(".css"):
      parts.push!(_link("stylesheet", @asset_base + entry_file, nonce)) unless css.has_key?(entry_file)
    else:
      parts.push!(_script(@asset_base + entry_file, nonce))
    preloaded = {}
    imports.each |key|:
      path = @manifest[key][:file]
      next unless preload and path.ends_with?(".js") and not preloaded.has_key?(path)
      preloaded[path] = true
      parts.push!(_link("modulepreload", @asset_base + path, nonce))
    join(parts)
