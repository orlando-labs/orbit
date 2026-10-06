package ember.stage3_html_comment_rejected

import ember
from ember.html import html

export main

value = "unsafe"
rejected = html"""
  <!-- #{value} -->
  """

def main():
  rejected
