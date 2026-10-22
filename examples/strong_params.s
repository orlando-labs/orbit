package orbit.example.strong_params

import orbit

export main

create_user_params = orbit.params(root: :user):
  field(:name, required: true)
  field(:age, type: Int)
  field(:newsletter, type: Bool)
  array(:tags, of: Str)
  object(:profile):
    field(:bio)
  array(:addresses):
    field(:city, required: true)
    field(:zip)

def create_user(request):
  attrs = request.params.json.expect(create_user_params)
  orbit.render(json: attrs, status: :created)

routes = orbit.routes:
  post "/users", to: &create_user

def main():
  orbit.App(routes: routes).run(port: 3000)
