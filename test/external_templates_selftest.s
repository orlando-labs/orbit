package app.external_templates
import orbit.telemetry
from orbit.html import url, raw
export main, page, query, command

@template("./templates/page.html.sv")
def page(items, target, escape: "caller shadow")

@template("./templates/filter.sql.sv")
def query(values)

@template("./templates/args.cmd.sv")
def command(values)

def check(value, message):
  raise ValueError("external providers: " + message) unless value

def main():
  result = page(["<&", raw("<b>safe</b>")], url("/a?x=1&y=2"))
  check(result.to_str == "<ul>\n  <li title=\"&lt;&amp;\">&lt;&amp;</li>\n  <li title=\"&lt;b&gt;safe&lt;/b&gt;\"><b>safe</b></li>\n</ul>\n<a href=\"/a?x=1&amp;y=2\">link</a>\n", "HTML context and safe fragments")
  denied = false
  try:
    page([], "javascript:evil")
  rescue ArgumentError:
    denied = true
  check(denied, "URL trust retained")
  sql = query(["safe", "x OR 1=1 --"])
  check(sql.text == "SELECT value FROM items WHERE 0\nOR value = ?\nOR value = ?\n", "one SQL fragment")
  check(sql.params == ["safe", "x OR 1=1 --"], "bound SQL parameters")
  check(command(["a b", "$(evil);"]).argv == ["echo", "a b", "$(evil);"], "opaque command arguments")
  print "PASS external template providers"
  true
