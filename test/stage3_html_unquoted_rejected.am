package ember.stage3_html_unquoted_rejected

import ember
from ember.html import html

export main

value = "/unsafe"
rejected = html"""
  <a href=#{value}>must not compile</a>
  """

def main():
  rejected
