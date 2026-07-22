package ember.multipart

import ember

export MultipartLimits, MultipartPart, MultipartForm, MultipartError, parse

class MultipartError < ember.RequestParamsError

class MultipartLimits:
  attr max_total_bytes
  attr max_parts
  attr max_header_bytes
  attr max_headers_per_part
  attr max_field_bytes
  attr max_file_bytes
  attr max_name_bytes
  attr max_filename_bytes

  def init(
    @max_total_bytes: 1048576,
    @max_parts: 64,
    @max_header_bytes: 8192,
    @max_headers_per_part: 32,
    @max_field_bytes: 65536,
    @max_file_bytes: 524288,
    @max_name_bytes: 128,
    @max_filename_bytes: 255
  ):
    {
      max_total_bytes: @max_total_bytes,
      max_parts: @max_parts,
      max_header_bytes: @max_header_bytes,
      max_headers_per_part: @max_headers_per_part,
      max_field_bytes: @max_field_bytes,
      max_file_bytes: @max_file_bytes,
      max_name_bytes: @max_name_bytes,
      max_filename_bytes: @max_filename_bytes
    }.each |name, value|:
      unless Int === value and value > 0:
        raise ArgumentError(name.to_str + " must be a positive Int")
    if @max_field_bytes > @max_total_bytes or @max_file_bytes > @max_total_bytes:
      raise ArgumentError("multipart part limits must not exceed max_total_bytes")

class MultipartPart:
  attr name
  attr filename
  attr content_type
  attr headers
  attr bytes

  def init(@name, @filename, @content_type, @headers, @bytes)

  def file?():
    @filename != null

  def text():
    if file?():
      raise MultipartError("file parts do not have an implicit text representation")
    @bytes.to_str()

class MultipartForm:
  attr parts

  def init(parts):
    @parts = parts.copy.freeze

  def first(name):
    @parts.find |part|: part.name == name.to_str

  def all(name):
    @parts.select |part|: part.name == name.to_str .freeze

  def fields():
    @parts.reject: _1.file?() .freeze

  def files():
    @parts.select: _1.file?() .freeze

def _boundary_from(content_type):
  unless content_type:
    raise ember.ParamsUnsupportedMediaTypeError("multipart parameters require Content-Type")
  pieces = content_type.to_str.split(";")
  unless pieces[0].trim.downcase == "multipart/form-data":
    raise ember.ParamsUnsupportedMediaTypeError("request Content-Type is not multipart/form-data")
  boundary = null
  index = 1
  while index < pieces.count:
    parameter = pieces[index].trim
    equals = parameter.index("=")
    unless equals and equals > 0:
      raise MultipartError("multipart Content-Type parameter is malformed")
    name = parameter.slice(0...equals).trim.downcase
    value = parameter.slice(equals + 1...parameter.length).trim
    if name == "boundary":
      if boundary:
        raise MultipartError("multipart boundary parameter is repeated")
      if value.starts_with?("\"") and value.ends_with?("\"") and value.length >= 2:
        value = value.slice(1...value.length - 1)
      boundary = value
    index += 1
  unless boundary and boundary.length >= 1 and boundary.length <= 70:
    raise MultipartError("multipart boundary must contain 1..70 characters")
  # Keep the native backend's value graph monomorphic after the null check.
  boundary = boundary.to_str()
  allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'()+_,-./:=?"
  boundary_chars = boundary.chars
  valid_boundary = true
  char_index = 0
  while char_index < boundary_chars.count:
    unless allowed.contains?(boundary_chars[char_index]):
      valid_boundary = false
    char_index += 1
  unless valid_boundary:
    raise MultipartError("multipart boundary contains an invalid character")
  boundary

def _disposition_parameters(raw):
  pieces = raw.split(";")
  unless pieces[0].trim.downcase == "form-data":
    raise MultipartError("Content-Disposition must be form-data")
  values = {}
  index = 1
  while index < pieces.count:
    parameter = pieces[index].trim
    equals = parameter.index("=")
    unless equals and equals > 0:
      raise MultipartError("Content-Disposition parameter is malformed")
    name = parameter.slice(0...equals).trim.downcase
    value = parameter.slice(equals + 1...parameter.length).trim
    unless value.starts_with?("\"") and value.ends_with?("\"") and value.length >= 2:
      raise MultipartError("Content-Disposition values must be quoted")
    value = value.slice(1...value.length - 1)
    if value.contains?("\"") or value.contains?("\\") or value.contains?("\r") or value.contains?("\n"):
      raise MultipartError("Content-Disposition value contains a forbidden character")
    if values.has_key?(name):
      raise MultipartError("duplicate Content-Disposition parameter")
    unless name == "name" or name == "filename":
      raise MultipartError("unsupported Content-Disposition parameter: " + name)
    values.store!(name, value)
    index += 1
  values

def _parse_part(block, limits):
  separator = block.index("\r\n\r\n")
  unless separator:
    raise MultipartError("multipart part does not contain a header terminator")
  header_text = block.slice(0...separator)
  if header_text.bytesize > limits.max_header_bytes:
    raise MultipartError("multipart part headers exceed the configured byte limit")
  lines = header_text.split("\r\n")
  if lines.empty? or lines.count > limits.max_headers_per_part:
    raise MultipartError("multipart part header count exceeds the configured limit")
  pairs = []
  lines.each |line|:
    if line.empty? or line.starts_with?(" ") or line.starts_with?("\t"):
      raise MultipartError("multipart folded or empty header line is forbidden")
    colon = line.index(":")
    unless colon and colon > 0:
      raise MultipartError("multipart part header is malformed")
    pairs.push!([line.slice(0...colon), line.slice(colon + 1...line.length).trim])
  headers = try:
    ember.Headers(pairs)
  rescue InvalidHeaderError |error|:
    raise MultipartError("invalid multipart header: " + error.message)
  dispositions = headers.all("content-disposition")
  unless dispositions.count == 1:
    raise MultipartError("multipart part requires exactly one Content-Disposition")
  parameters = _disposition_parameters(dispositions[0])
  name = parameters[?"name"]
  filename = parameters[?"filename"]
  unless name and name.present?() and name.bytesize <= limits.max_name_bytes:
    raise MultipartError("multipart field name is missing or too long")
  if filename and (filename.bytesize > limits.max_filename_bytes or filename.contains?("/") or filename.contains?("\\") or filename == "." or filename == ".."):
    raise MultipartError("multipart filename is invalid or too long")
  data_text = block.slice(separator + 4...block.length)
  data = Bytes.new(data_text)
  if filename and data.count() > limits.max_file_bytes:
    raise MultipartError("multipart file exceeds the configured byte limit")
  if not filename and data.count() > limits.max_field_bytes:
    raise MultipartError("multipart field exceeds the configured byte limit")
  content_types = headers.all("content-type")
  if content_types.count > 1:
    raise MultipartError("multipart Content-Type must not be repeated")
  content_type = if content_types.empty? then null else content_types[0]
  MultipartPart(name, filename, content_type, headers, data)

def parse(request, limits: MultipartLimits()):
  unless ember.Request === request:
    raise ArgumentError("multipart.parse expects ember.Request")
  boundary = _boundary_from(request.header("content-type"))
  request.body_stream.claim_params!()
  bytes = request.body_bytes()
  if bytes.count() > limits.max_total_bytes:
    raise MultipartError("multipart body exceeds the configured aggregate byte limit")
  text = bytes.to_str()
  opening = "--" + boundary + "\r\n"
  delimiter = "\r\n--" + boundary + "\r\n"
  closing = "\r\n--" + boundary + "--"
  unless text.starts_with?(opening):
    raise MultipartError("multipart body is missing its opening boundary")
  close_index = text.rindex(closing)
  unless close_index:
    raise MultipartError("multipart body is missing its closing boundary")
  suffix = text.slice(close_index + closing.length...text.length)
  unless suffix == "" or suffix == "\r\n":
    raise MultipartError("multipart epilogue is forbidden")
  content = text.slice(opening.length...close_index)
  blocks = content.split(delimiter)
  if blocks.empty? or blocks.count > limits.max_parts:
    raise MultipartError("multipart part count exceeds the configured limit")
  parts = blocks.map |block|: _parse_part(block, limits)
  MultipartForm(parts)
