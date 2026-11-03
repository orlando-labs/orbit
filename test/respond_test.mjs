import assert from 'node:assert/strict'
import { mkdtemp, writeFile, rm } from 'node:fs/promises'
import { spawnSync } from 'node:child_process'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = fileURLToPath(new URL('../', import.meta.url))
const compiler = path.resolve(root, '../sputnik-lang/build/sputnik')
const env = { ...process.env, SPUTNIK_NATIVE_RT_CACHE: path.resolve(root, '../sputnik-lang/build/interop-runtime-cache') }
function run(args, failure) {
  const result = spawnSync(compiler, args, { cwd: root, env, encoding: 'utf8', timeout: 600_000, maxBuffer: 10 * 1024 * 1024 })
  const output = result.stdout + result.stderr
  if (failure) { assert.notEqual(result.status, 0, output); assert.match(output, failure) }
  else assert.equal(result.status, 0, output)
  return result.stdout
}
const temporary = await mkdtemp(path.join(tmpdir(), 'orbit-respond-'))
try {
  await writeFile(path.join(temporary, 'sputnik.build.json'), JSON.stringify({ dependencies: { orbit: { path: root } } }))
  const failures = [
    ['respond()', /ORBIT_RESPOND_BLOCK/],
    ['respond:\n  json', /ORBIT_RESPOND_BRANCH/],
    ['respond:\n  unknown: 1', /ORBIT_RESPOND_BRANCH/],
    ['respond:\n  json(1): 1', /ORBIT_RESPOND_BRANCH/],
    ['respond:\n  format(): 1', /ORBIT_RESPOND_FORMAT/],
    ['respond:\n  format("text/csv", typo: :text): "a"', /ORBIT_RESPOND_FORMAT/],
    ['respond:\n  format("text/csv", :text): "a"', /ORBIT_RESPOND_FORMAT/],
    ['respond:\n  json() |value|: value', /ORBIT_RESPOND_BRANCH/],
    ['respond:\n  value = 1', /ORBIT_RESPOND_BRANCH/],
  ]
  for (const [body, diagnostic] of failures) {
    const file = path.join(temporary, 'invalid.s')
    await writeFile(file, 'package invalid\nimport orbit\nfrom orbit import respond\nclass C < orbit.Controller:\n  def current():\n' + body.split('\n').map(line => '    ' + line).join('\n') + '\n')
    run(['run', file], diagnostic)
  }
  // A response expression keeps caller locals and nested declarations in scope.
  const file = path.join(temporary, 'expression.s')
  await writeFile(file, `package expression
import orbit
from orbit import respond
class C < orbit.Controller:
  def current():
    data = "caller"
    value = respond:
      json: {value: data}
      html: orbit.Html(data)
    raise ValueError("caller binding changed") unless data == "caller"
    value
export main
def main():
  response = C(orbit.Request(headers: {accept: "application/json"})).current
  raise ValueError("respond expression") unless Json.parse(response.body)[:value] == "caller"
  print "PASS respond expression"
`)
  assert.match(run(['run', file]), /PASS respond expression/)
  assert.match(run(['run', 'test/respond_selftest.build.json']), /PASS Orbit respond/)
  if (process.argv.includes('--native')) {
    const output = run(['build', 'test/respond_selftest.build.json', '--target', 'native', '--require-full-native', '--out-dir', 'build/respond-native', '--cache-dir', 'build/respond-native-cache'])
    await writeFile(path.join(root, 'build/respond-native-build.json'), output)
    const summary = JSON.parse(output)
    assert(summary.native_graph_full_coverage && summary.native_graph_vm_independent && !summary.native_graph_runtime_bridge)
    assert.equal(summary.native_graph_fallback_code_count, 0)
    const result = spawnSync(path.join(root, 'build/respond-native/orbit.respond_selftest'), [], { cwd: root, env, encoding: 'utf8', timeout: 60_000 })
    assert.equal(result.status, 0, result.stdout + result.stderr)
    assert.match(result.stdout, /PASS Orbit respond/)
  }
  console.log('PASS Orbit respond VM, DSL diagnostics and expression scope' + (process.argv.includes('--native') ? '; strict native verified' : ''))
} finally { await rm(temporary, { recursive: true, force: true }) }
