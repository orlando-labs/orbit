package orbit.stage3_html_unquoted_rejected

import orbit
from orbit.html import html

export main

value = "/unsafe"
rejected = html"""
  <a href=#{value}>must not compile</a>
  """

def main():
  rejected
