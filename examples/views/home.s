package orbit.example.views.home

from orbit.html import escape, html, join

export page

def page(name as Str):
  html"""
    <!doctype html>
    <html>
      <head><title>Orbit</title></head>
      <body><h1>Hello, #{name}</h1></body>
    </html>
    """

