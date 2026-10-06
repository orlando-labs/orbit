package ember.example.hello

import ember
from ember.example.views.home import page
from ember.middleware import request_id

export main

def home(request):
  ember.redirect(to: request.routes.path(:hello, name: "Sputnik"))

def hello(request, name):
  ember.render(html: page(name))

routes = ember.routes:
  get "/", to: &home, as: :root
  get "/hello/:name", to: &hello, as: :hello

def main():
  ember.App(routes: routes, middleware: [&request_id]).run(port: 3000)

