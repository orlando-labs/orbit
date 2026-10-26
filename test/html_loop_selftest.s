package app.html_loop_selftest

import orbit
import orbit.telemetry
from orbit.html import html, escape, url, raw

export main

def check(value, message):
  raise ValueError("HTML loops: " + message) unless value

def main():
  items = ["<b>&", "second"]
  page = html"""
    <ul>
      %for item with_index i in items:
        <li title="#{item}">#{i}:#{item}</li>
    </ul>
    """
  expected = "<ul>\n  <li title=\"&lt;b&gt;&amp;\">0:&lt;b&gt;&amp;</li>\n  <li title=\"second\">1:second</li>\n</ul>\n"
  check(page.to_str == expected, "ordered HTML and contextual escaping: " + page.to_str)
  empty = html"""
    before
    %for item in []:
      #{item}
    after
    """
  check(empty.to_str == "before\nafter\n", "empty loop")
  links = html"""
    %for target in [url("/a?x=1&y=2"), url("/b")]:
      <a href="#{target}">#{raw("<em>safe</em>")}</a>
    """
  check(links.to_str.contains?("href=\"/a?x=1&amp;y=2\""), "URL context retained")
  check(links.to_str.contains?("<em>safe</em>"), "safe HTML is not escaped twice")
  nested = html"""
    %for row in [[1, 2], [3]]:
      <ul>
        %for item in row:
          <li>#{item}</li>
      </ul>
    """
  check(nested.to_str == "<ul>\n  <li>1</li>\n  <li>2</li>\n</ul>\n<ul>\n  <li>3</li>\n</ul>\n", "nested loops and indentation")
  escaped = html"""
    %for item in ["<&"]:
      \u{3C}b>#{item}</b>
    """
  check(escaped.to_str == "<b>&lt;&amp;</b>\n", "cooked escapes retain HTML lexical context")
  rejected = false
  try:
    html"""
      %for target in ["javascript:bad"]:
        <a href="#{target}">bad</a>
      """
  rescue ArgumentError:
    rejected = true
  check(rejected, "loop does not bypass URL trust boundary")
  print "PASS Orbit HTML loops"
  true
