package orbit.example.hello

import orbit
from orbit.example.views.home import page
from orbit.middleware import request_id

export main

def home(request):
  orbit.redirect(to: request.routes.path(:hello, name: "Sputnik"))

def hello(request, name):
  orbit.render(html: page(name))

routes = orbit.routes:
  get "/", to: &home, as: :root
  get "/hello/:name", to: &hello, as: :hello

def main():
  orbit.App(routes: routes, middleware: [&request_id]).run(port: 3000)

