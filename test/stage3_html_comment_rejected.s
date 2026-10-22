package orbit.stage3_html_comment_rejected

import orbit
from orbit.html import html

export main

value = "unsafe"
rejected = html"""
  <!-- #{value} -->
  """

def main():
  rejected
