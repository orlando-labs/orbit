package orbit.benchmark.orm_pool

import orm
import task
from orm.sqlite3 import memory_pool
from orm.pool import ConnectionPoolTimeoutError

export main

def percentile(sorted, percent):
  sorted[((sorted.count - 1) * percent) // 100]

def checkout(database):
  try:
    database.with_connection(timeout: 0):
      null
    true
  rescue ConnectionPoolTimeoutError:
    false

def exhausted_pool(database, iterations):
  result = null
  database.with_connection:
    contender = task.spawn:
      measure_rejections(database, iterations)
    result = contender.wait()
  result

def measure_rejections(database, iterations):
  samples = []
  rejected = 0
  total_started = Time.monotonic
  iterations.times:
    started = Time.monotonic
    rejected += 1 unless checkout(database)
    samples.push!((Time.monotonic - started).total_nanoseconds)
  total_ns = (Time.monotonic - total_started).total_nanoseconds
  ordered = samples.sorted
  {
    "iterations": iterations,
    "p50_us": percentile(ordered, 50).to_float / 1000.0,
    "p95_us": percentile(ordered, 95).to_float / 1000.0,
    "p99_us": percentile(ordered, 99).to_float / 1000.0,
    "throughput_per_second": iterations.to_float * 1000000000.0 / total_ns.to_float,
    "rejected": rejected
  }

def main():
  result = null
  memory_pool(
    name: "orbit_benchmark_exhaustion",
    min_size: 1,
    max_size: 1,
    checkout_timeout: 0
  ) |database|:
    result = exhausted_pool(database, 500)
  io.stdout.write_line(Json.generate({
    "schema": "orbit.benchmark.result.v1",
    "suite": "orm",
    "workloads": {"orm_pool_exhaustion": result}
  }))
  null
