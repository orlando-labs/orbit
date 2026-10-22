package orbit.integrations.orm

from orbit import Integration, render
from orm.pool import ConnectionPoolClosedError
from orm.pool import ConnectionPoolLeaseError
from orm.pool import ConnectionPoolTimeoutError

export pool, connection, PoolIntegration, ConnectionMiddleware

def pool(database, name: "orm"):
  PoolIntegration(database, name: name)

def connection(database):
  ConnectionMiddleware(database)

class PoolIntegration < Integration:
  def init(@database, name: "orm"):
    @name = name.to_str
    @metrics = null

  def attach_server(server):
    if server.app.telemetry:
      @metrics = server.app.telemetry.metrics
      _publish_metrics()
    self

  def start():
    if @database.closed?():
      raise ConnectionPoolClosedError("cannot start Orbit with a closed ORM pool")
    self

  def ready?():
    not @database.closed?

  def stop():
    @database.close! unless @database.closed?()
    null

  def around_controller(request, next):
    try:
      @database.with_connection:
        next(request)
    rescue ConnectionPoolTimeoutError |error|:
      render(text: "service unavailable", status: :service_unavailable)
    rescue ConnectionPoolClosedError |error|:
      render(text: "service unavailable", status: :service_unavailable)
    rescue ConnectionPoolLeaseError |error|:
      render(text: "service unavailable", status: :service_unavailable)
    ensure:
      _publish_metrics()

  def _publish_metrics():
    return null unless @metrics
    stats = @database.stats()
    @metrics.set_integration_pool(
      @name,
      active: stats[:leased],
      capacity: stats[:max_size],
      waiting: stats[:waiting])
    null

class ConnectionMiddleware:
  def init(@database)

  def call(request, next):
    try:
      @database.with_connection:
        next(request)
    rescue ConnectionPoolTimeoutError |error|:
      render(text: "service unavailable", status: :service_unavailable)
    rescue ConnectionPoolClosedError |error|:
      render(text: "service unavailable", status: :service_unavailable)
    rescue ConnectionPoolLeaseError |error|:
      render(text: "service unavailable", status: :service_unavailable)
