import assert from 'node:assert/strict'
import { mkdtemp, mkdir, writeFile, symlink, realpath, rm } from 'node:fs/promises'
import { spawnSync } from 'node:child_process'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = fileURLToPath(new URL('../', import.meta.url))
const compiler = path.resolve(ROOT, '../sputnik-lang/build/sputnik')
const environment = { ...process.env, SPUTNIK_VM_CACHE: path.join(ROOT, 'build/assets-vm-cache'), SPUTNIK_NATIVE_RT_CACHE: path.resolve(ROOT, '../sputnik-lang/build/interop-runtime-cache') }
const fixtures = await realpath(await mkdtemp(path.join(tmpdir(), 'orbit-assets-')))
const grants = ['fs.read', 'fs.metadata', 'net.listen', 'net.connect']
function run(command, args, capture = false) {
  const result = spawnSync(command, args, { cwd: ROOT, env: environment, encoding: 'utf8', stdio: capture ? 'pipe' : 'inherit', timeout: 600_000, maxBuffer: 10 * 1024 * 1024 })
  assert.equal(result.status, 0, result.error?.message || result.stdout?.slice(-6000) || result.stderr?.slice(-3000) || 'Sputnik process failed')
  return result.stdout
}
try {
  await mkdir(path.join(fixtures, 'public/nested'), { recursive: true })
  await writeFile(path.join(fixtures, 'private.txt'), 'PRIVATE')
  await writeFile(path.join(fixtures, 'public/favicon.svg'), '<svg xmlns="http://www.w3.org/2000/svg"/>')
  await writeFile(path.join(fixtures, 'public/.env'), 'PRIVATE')
  await writeFile(path.join(fixtures, 'public/nested/.secret'), 'PRIVATE')
  await writeFile(path.join(fixtures, 'public/nested/style.css'), 'body { color: green }')
  await writeFile(path.join(fixtures, 'public/empty.txt'), '')
  await writeFile(path.join(fixtures, 'public/large.bin'), 'streamed-data!\n'.repeat(10000))
  await symlink(path.join(fixtures, 'private.txt'), path.join(fixtures, 'public/linked.txt'))
  await symlink(fixtures, path.join(fixtures, 'public/linked-dir'), 'dir')
  await symlink(path.join(fixtures, 'public'), path.join(fixtures, 'rootlink'), 'dir')
  const source = path.join(ROOT, 'test/assets_selftest.build.json')
  run(compiler, ['run', source, ...grants.flatMap(grant => ['--grant', grant]), '--', '--fixtures', fixtures])
  if (process.argv.includes('--native')) {
    const output = path.join(ROOT, 'build/assets-native')
    const metadata = run(compiler, ['build', source, '--target', 'native', '--require-full-native', ...grants.flatMap(grant => ['--grant', grant]), '--out-dir', output, '--cache-dir', path.join(ROOT, 'build/assets-native-cache')], true)
    await writeFile(path.join(ROOT, 'build/assets-native-build.json'), metadata)
    const summary = JSON.parse(metadata)
    assert(summary.native_graph_full_coverage && summary.native_graph_vm_independent)
    assert(!summary.native_bytecode_fallback && !summary.native_graph_runtime_bridge)
    run(path.join(output, 'orbit.assets_selftest'), ['--fixtures', fixtures])
  }
} finally {
  await rm(fixtures, { recursive: true, force: true })
}
