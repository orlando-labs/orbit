package ember.example.strong_params

import ember

export main

create_user_params = ember.params(root: :user):
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
  ember.render(json: attrs, status: :created)

routes = ember.routes:
  post "/users", to: &create_user

def main():
  ember.App(routes: routes).run(port: 3000)
