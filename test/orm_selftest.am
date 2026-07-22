package ember.orm_selftest

import ember
import ember.testing
import orm
from ember.integrations.orm import pool as pool_integration
from orm.sqlite3 import memory_pool

export main

class User:
  use orm.model(table: :users)

class Users < ember.Controller:
  def create():
    user = User.create(email: "ember@example.test", age: 36).or_raise
    render(json: {id: user[:id], email: user[:email]}, status: :created)

routes = ember.routes:
  post "/users", to: &Users#create

def assert(condition, message):
  raise ArgumentError(message) unless condition

def main():
  memory_pool(
    name: "ember_orm_selftest",
    min_size: 1,
    max_size: 2
  ) |database|:
    database.with_connection |connection|:
      connection.exec("create table users(id integer primary key, email text not null, age integer)")

    assert(database.bind!(User).ok?, "one-time model binding")
    app = ember.App(
      routes: routes,
      integrations: [pool_integration(database)],
      expose_exceptions: true)

    created = app.call(testing.post("/users"))
    assert(created.status == 201, "controller ORM response status")
    assert(created.header("content-type") == "application/json; charset=utf-8", "controller ORM JSON type")
    assert(created.body_text.contains?("ember@example.test"), "controller ORM response body")

    found = User.find(1).or_raise
    assert(found[:age] == 36, "pool-backed model lookup")
    users = User.where().all.or_raise
    assert(users.count == 1 and User === users[0], "unfiltered model all")

    database.close!
    unavailable = app.call(testing.post("/users"))
    assert(unavailable.status == 503, "closed pool maps to safe 503")
  true
