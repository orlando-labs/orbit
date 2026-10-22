package orbit.example.sqlite_users

import orbit
import orm
from orbit.integrations.orm import pool as orm_pool
from orm.sqlite3 import memory_pool

export main

class User:
  use orm.model(table: :users)

class Users < orbit.Controller:
  def index():
    users = User.all.or_raise
    render(json: users.map: _1.attributes)

  def create():
    user = User.create(name: request.query(:name)).or_raise
    render(json: user.attributes, status: :created)

routes = orbit.routes:
  get "/users", to: &Users#index, as: :users
  post "/users", to: &Users#create

def main():
  memory_pool(name: "orbit_example", min_size: 1, max_size: 4) |database|:
    database.with_connection |connection|:
      connection.exec("create table users(id integer primary key, name text not null)")
    database.bind!(User).or_raise
    orbit.App(
      routes: routes,
      integrations: [orm_pool(database)]
    ).run(port: 3000, workers: 2)
