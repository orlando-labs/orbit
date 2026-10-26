package orbit.html

from orbit import Html

export escape, escape_text, escape_attribute, raw, join
export url, trusted_script, trusted_style
export HtmlUrl, TrustedScript, TrustedStyle
export _url_attribute, _script_body, _style_body
export _script_attribute, _style_attribute, _srcdoc_attribute
export macro html

def escape(value, context = :text):
  return escape_text(value) if context == :text
  return escape_attribute(value) if context == :attribute
  return _url_attribute(value) if context == :url_attribute
  return _script_body(value) if context == :script
  return _style_body(value) if context == :style
  return _script_attribute(value) if context == :script_attribute
  return _style_attribute(value) if context == :style_attribute
  return _srcdoc_attribute(value) if context == :srcdoc_attribute
  raise ArgumentError("unknown HTML escaping context")

def escape_text(value):
  Html.escape(value)

def escape_attribute(value):
  text = if value == null then "" else value.to_str
  Html.escape(text)

def raw(value):
  Html.raw(value)

def join(parts):
  Html.join(parts)

class HtmlUrl:
  def init(value):
    text = value.to_str
    lowered = text.downcase
    invalid_control = text.contains?("\r") or text.contains?("\n") or text.contains?("\t") or text.contains?("\\")
    ambiguous_list = text.contains?(" ") or text.contains?(",")
    if text.empty? or invalid_control or ambiguous_list or text.starts_with?("//"):
      raise ArgumentError("HTML URL is empty, protocol-relative, or contains a forbidden character")
    absolute = lowered.starts_with?("https://") or lowered.starts_with?("http://")
    allowed_scheme = absolute or lowered.starts_with?("mailto:") or lowered.starts_with?("tel:")
    relative = text.starts_with?("/") or text.starts_with?("#") or not text.contains?(":")
    unless allowed_scheme or relative:
      raise ArgumentError("HTML URL scheme is not allowed")
    @value = text

  def to_str():
    @value

def url(value):
  return value if HtmlUrl === value
  HtmlUrl(value)

class TrustedScript:
  def init(value):
    text = value.to_str
    if text.downcase.contains?("</script"):
      raise ArgumentError("trusted script must not contain a closing script tag")
    @value = text

  def to_str():
    @value

def trusted_script(value):
  return value if TrustedScript === value
  TrustedScript(value)

class TrustedStyle:
  def init(value):
    text = value.to_str
    if text.downcase.contains?("</style"):
      raise ArgumentError("trusted style must not contain a closing style tag")
    @value = text

  def to_str():
    @value

def trusted_style(value):
  return value if TrustedStyle === value
  TrustedStyle(value)

def _url_attribute(value):
  unless HtmlUrl === value:
    raise ArgumentError("URL attribute interpolation requires orbit.html.url(...)")
  escape_attribute(value.to_str)

def _script_body(value):
  unless TrustedScript === value:
    raise ArgumentError("script interpolation requires orbit.html.trusted_script(...)")
  Html.raw(value.to_str)

def _style_body(value):
  unless TrustedStyle === value:
    raise ArgumentError("style interpolation requires orbit.html.trusted_style(...)")
  Html.raw(value.to_str)

def _script_attribute(value):
  unless TrustedScript === value:
    raise ArgumentError("event-handler interpolation requires orbit.html.trusted_script(...)")
  escape_attribute(value.to_str)

def _style_attribute(value):
  unless TrustedStyle === value:
    raise ArgumentError("style-attribute interpolation requires orbit.html.trusted_style(...)")
  escape_attribute(value.to_str)

def _srcdoc_attribute(value):
  unless Html === value:
    raise ArgumentError("srcdoc interpolation requires explicit orbit.html.raw(...)")
  escape_attribute(value.to_str)

macro def _html_template_parts(template_parts, loop_body: false):
  parts = []
  mode = :text
  tag_name = ""
  attr_name = ""
  token = ""
  closing = false
  reading_tag = false
  expecting_value = false

  template_parts.each |part|:
    if part.kind == "AstStringFor":
      raise ArgumentError("ORBIT_HTML_CONTROL_CONTEXT: %for requires HTML text context") unless mode == :text
      body = _html_template_parts(part.parts, loop_body: true)
      parts.push!(Ast.node("AstStringFor", {iteration: part.iteration, parts: body}))
    elif part.kind == "AstStringText" or part.kind == "AstStringEscape":
      text = part.value
      index = 0
      while index < text.length:
        char = text.slice(index...index + 1)
        four = if index + 4 <= text.length then text.slice(index...index + 4).downcase else ""
        three = if index + 3 <= text.length then text.slice(index...index + 3).downcase else ""
        eight = if index + 8 <= text.length then text.slice(index...index + 8).downcase else ""
        seven = if index + 7 <= text.length then text.slice(index...index + 7).downcase else ""

        if mode == :text:
          if four == "<!--":
            mode = :comment
            index += 4
          elif char == "<":
            mode = :tag
            tag_name = ""
            attr_name = ""
            token = ""
            closing = false
            reading_tag = true
            expecting_value = false
            index += 1
          else:
            index += 1
          next

        if mode == :comment:
          if three == "-->":
            mode = :text
            index += 3
          else:
            index += 1
          next

        if mode == :script:
          if eight == "</script":
            mode = :tag
            tag_name = "script"
            closing = true
            reading_tag = false
            token = ""
            index += 8
          else:
            index += 1
          next

        if mode == :style:
          if seven == "</style":
            mode = :tag
            tag_name = "style"
            closing = true
            reading_tag = false
            token = ""
            index += 7
          else:
            index += 1
          next

        if mode == :attr_double:
          if char == "\"":
            mode = :tag
            attr_name = ""
          index += 1
          next

        if mode == :attr_single:
          if char == "'":
            mode = :tag
            attr_name = ""
          index += 1
          next

        if mode == :unquoted:
          if char == ">":
            mode = if not closing and tag_name == "script" then :script else (if not closing and tag_name == "style" then :style else :text)
          elif " \t\r\n".contains?(char):
            mode = :tag
            attr_name = ""
          index += 1
          next

        if reading_tag:
          if char == "/" and tag_name.empty?:
            closing = true
          elif char == ">":
            mode = if not closing and tag_name == "script" then :script else (if not closing and tag_name == "style" then :style else :text)
          elif " \t\r\n".contains?(char):
            reading_tag = false if tag_name.present?
          else:
            tag_name = tag_name + char.downcase
          index += 1
          next

        if expecting_value:
          if char == "\"":
            mode = :attr_double
            expecting_value = false
          elif char == "'":
            mode = :attr_single
            expecting_value = false
          elif not " \t\r\n".contains?(char):
            mode = :unquoted
            expecting_value = false
          index += 1
          next

        if char == ">":
          mode = if not closing and tag_name == "script" then :script else (if not closing and tag_name == "style" then :style else :text)
        elif char == "=":
          attr_name = token.downcase if token.present?
          token = ""
          expecting_value = true
        elif " \t\r\n".contains?(char):
          if token.present?:
            attr_name = token.downcase
            token = ""
        else:
          token = token + char
        index += 1

      html_type = Ast.node("AstQualifiedRef", {module: "orbit", name: "Html"})
      node = quote:
        #{html_type}.raw(#{Ast.lift(part.value)})
      parts.push!(node)
    elif part.kind == "AstStringExpr":
      kind = null
      if mode == :text:
        kind = :text
      elif mode == :script:
        kind = :script
      elif mode == :style:
        kind = :style
      elif mode == :attr_double or mode == :attr_single:
        if attr_name.starts_with?("on"):
          kind = :script_attribute
        elif attr_name == "style":
          kind = :style_attribute
        elif attr_name == "srcdoc":
          kind = :srcdoc_attribute
        elif ["href", "src", "action", "formaction", "poster", "cite", "data", "srcset", "xlink:href"].include?(attr_name):
          kind = :url_attribute
        else:
          kind = :attribute
      else:
        raise ArgumentError("ORBIT_HTML_CONTEXT: interpolation is forbidden in tags, comments, and unquoted attributes")
      lifted_kind = Ast.node("AstLiteral", {token: "SYMBOL", value: kind.to_str})
      escape_ref = Ast.node("AstQualifiedRef", {module: "orbit.html", name: "escape"})
      node = quote:
        #{escape_ref}(#{part.expr}, #{lifted_kind})
      parts.push!(node)
    else:
      raise ArgumentError("ORBIT_HTML_PART: unsupported HTML template part")
  if loop_body and mode != :text:
    raise ArgumentError("ORBIT_HTML_CONTROL_CONTEXT: loop body must finish in HTML text context")
  return parts

string_tag macro def html(template as Ast.StringTemplate) -> Ast:
  html_type = Ast.node("AstQualifiedRef", {module: "orbit", name: "Html"})
  finish = quote:
    #{html_type}.join
  return Ast.node("AstTemplateRender", {
    parts: _html_template_parts(template.parts),
    finish: finish
  })
