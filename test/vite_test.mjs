import assert from 'node:assert/strict'
import { mkdtemp, mkdir, writeFile, unlink, symlink, realpath, rm } from 'node:fs/promises'
import { spawnSync } from 'node:child_process'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = fileURLToPath(new URL('../', import.meta.url))
const compiler = path.resolve(ROOT, '../sputnik-lang/build/sputnik')
const environment = { ...process.env, SPUTNIK_VM_CACHE: path.join(ROOT, 'build/vite-vm-cache'), SPUTNIK_NATIVE_RT_CACHE: path.resolve(ROOT, '../sputnik-lang/build/interop-runtime-cache') }
const manifest = {
  'src/main.ts': { file: 'assets/main.js', isEntry: true, imports: ['_shared.js'], dynamicImports: ['src/lazy.ts'], css: ['assets/entry.css', 'assets/shared.css'] },
  '_shared.js': { file: 'assets/shared.js', imports: ['src/main.ts'], css: ['assets/shared.css'] },
  'src/lazy.ts': { file: 'assets/lazy.js', isDynamicEntry: true },
  'src/style.css': { file: 'assets/entry.css', isEntry: true },
}
const fixtures = await realpath(await mkdtemp(path.join(tmpdir(), 'orbit-vite-')))
async function fixture(name, data) {
  const dist = path.join(fixtures, name, 'dist')
  await mkdir(path.join(dist, '.vite'), { recursive: true })
  await mkdir(path.join(dist, 'assets'))
  for (const file of ['main.js', 'shared.js', 'lazy.js', 'entry.css', 'shared.css']) await writeFile(path.join(dist, 'assets', file), '/* fixture */')
  await writeFile(path.join(dist, '.vite/manifest.json'), JSON.stringify(data))
  return dist
}
function run(command, args, capture = false) {
  const result = spawnSync(command, args, { cwd: ROOT, env: environment, encoding: 'utf8', stdio: capture ? 'pipe' : 'inherit', timeout: 600_000, maxBuffer: 10 * 1024 * 1024 })
  assert.equal(result.status, 0, result.error?.message || result.stdout?.slice(-6000) || result.stderr?.slice(-3000) || 'Sputnik process failed')
  return result.stdout
}
try {
  await fixture('valid', manifest)
  for (const [name, file] of [['parent', '../secret.js'], ['absolute', '/etc/passwd'], ['encoded', '%2e%2e/secret.js']]) {
    const data = structuredClone(manifest); data['src/main.ts'].file = file
    await fixture(name, data)
  }
  const missing = await fixture('missing', manifest)
  await unlink(path.join(missing, 'assets/main.js'))
  const linked = await fixture('symlink', manifest)
  await unlink(path.join(linked, 'assets/main.js'))
  await symlink(path.join(fixtures, 'valid/dist/assets/main.js'), path.join(linked, 'assets/main.js'))
  await symlink(path.join(fixtures, 'valid'), path.join(fixtures, 'rootlink'), 'dir')
  for (const name of ['unknown', 'badlist', 'missingentry', 'notentry']) {
    const data = structuredClone(manifest)
    if (name === 'unknown') data['src/main.ts'].imports = ['missing.js']
    if (name === 'badlist') data['src/main.ts'].css = false
    if (name === 'missingentry') delete data['src/main.ts']
    if (name === 'notentry') data['src/main.ts'].isEntry = false
    await fixture(name, data)
  }
  for (const [name, body] of [['duplicate', '{"src/main.ts":{},"src/main.ts":{}}'], ['badjson', '{']]) {
    const dist = await fixture(name, manifest)
    await writeFile(path.join(dist, '.vite/manifest.json'), body)
  }
  const source = path.join(ROOT, 'test/vite_selftest.build.json')
  run(compiler, ['run', source, '--grant', 'fs.read', '--grant', 'fs.metadata', '--', '--fixtures', fixtures])
  if (process.argv.includes('--native')) {
    const output = path.join(ROOT, 'build/vite-native')
    const text = run(compiler, ['build', source, '--target', 'native', '--require-full-native', '--grant', 'fs.read', '--grant', 'fs.metadata', '--out-dir', output, '--cache-dir', path.join(ROOT, 'build/vite-native-cache')], true)
    await writeFile(path.join(ROOT, 'build/vite-native-build.json'), text)
    const summary = JSON.parse(text)
    assert(summary.native_graph_full_coverage && summary.native_graph_vm_independent)
    assert(!summary.native_bytecode_fallback && !summary.native_graph_runtime_bridge)
    run(path.join(output, 'orbit.vite_selftest'), ['--fixtures', fixtures])
  }
} finally {
  await rm(fixtures, { recursive: true, force: true })
}
