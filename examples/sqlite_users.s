package ember.example.sqlite_users

import ember
import orm
from ember.integrations.orm import pool as orm_pool
from orm.sqlite3 import memory_pool

export main

class User:
  use orm.model(table: :users)

class Users < ember.Controller:
  def index():
    users = User.all.or_raise
    render(json: users.map: _1.attributes)

  def create():
    user = User.create(name: request.query(:name)).or_raise
    render(json: user.attributes, status: :created)

routes = ember.routes:
  get "/users", to: &Users#index, as: :users
  post "/users", to: &Users#create

def main():
  memory_pool(name: "ember_example", min_size: 1, max_size: 4) |database|:
    database.with_connection |connection|:
      connection.exec("create table users(id integer primary key, name text not null)")
    database.bind!(User).or_raise
    ember.App(
      routes: routes,
      integrations: [orm_pool(database)]
    ).run(port: 3000, workers: 2)
