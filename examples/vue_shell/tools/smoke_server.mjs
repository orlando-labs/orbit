// Test-only orchestration. OAuth provider and application both execute Sputnik.
import http from 'node:http'
import net from 'node:net'
import path from 'node:path'
import { readFile, realpath, mkdir, open } from 'node:fs/promises'
import { parseArgs } from 'node:util'
import { spawn } from 'node:child_process'
import { APP, backend, vite, stop, sleep } from './common.mjs'

const { values } = parseArgs({ options: { mode: { type: 'string', default: 'production' }, port: { type: 'string', default: '3000' }, 'native-backend': { type: 'boolean', default: false } } })
if (!['development', 'production'].includes(values.mode)) throw new Error('Invalid smoke mode')
const origin = `http://127.0.0.1:${Number(values.port)}`
async function freePort() {
  const server = net.createServer()
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
  const port = server.address().port
  await new Promise(resolve => server.close(resolve))
  return port
}
async function ready(port) {
  return new Promise(resolve => {
    const socket = net.connect(port, '127.0.0.1')
    socket.once('connect', () => { socket.destroy(); resolve(true) })
    socket.once('error', () => resolve(false))
  })
}
const providerPort = await freePort(), backendPort = await freePort(), vitePort = await freePort()
const env = { ...process.env, ORBIT_ORIGIN: origin, VITE_ORIGIN: `http://127.0.0.1:${vitePort}`, SPUTNIK_VM_CACHE: path.join(APP, `build/smoke-${values.mode}-cache`) }
await mkdir(path.join(APP, 'build'), { recursive: true })
const log = await open(path.join(APP, `build/smoke-${values.mode}.log`), 'w')
const stdio = ['ignore', log.fd, log.fd]
const children = []
let ending = false
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => { ending = true })
let edge
try {
  children.push(backend(path.join(APP, 'test/github_fixture.s'), ['--port', String(providerPort), '--callback-origin', origin], { ...env, SPUTNIK_VM_CACHE: env.SPUTNIK_VM_CACHE + '-provider' }, stdio))
  if (values.mode === 'development') children.push(vite(env, stdio))
  const backendArgs = ['--mode', values.mode, '--origin', origin, '--port', String(backendPort), '--vite-origin', env.VITE_ORIGIN, '--github-origin', `http://127.0.0.1:${providerPort}`]
  children.push(values['native-backend']
    ? spawn(path.join(APP, 'build/fixture-native/fixture'), backendArgs, { cwd: APP, env, stdio, detached: process.platform !== 'win32' })
    : backend(path.join(APP, 'backend/fixture.s'), backendArgs, env, stdio))
  for (let attempt = 0; ; attempt++) {
    if (children.some(child => child.exitCode !== null || child.signalCode !== null)) throw new Error('Smoke child exited; inspect build/smoke-' + values.mode + '.log')
    if (await ready(providerPort) && await ready(backendPort) && (values.mode !== 'development' || await ready(vitePort))) break
    if (attempt > 450 || ending) throw new Error('Smoke startup timed out or was stopped')
    await sleep(100)
  }
  const root = path.join(APP, 'frontend/dist/assets')
  edge = http.createServer(async (request, response) => {
    const reject = () => { response.writeHead(404, { 'Content-Type': 'application/json' }); response.end('{}') }
    let pathname
    try { pathname = decodeURIComponent(new URL(request.url, origin).pathname) } catch { return reject() }
    if (pathname.startsWith('/assets/')) {
      if (values.mode !== 'production') return reject()
      try {
        const file = await realpath(path.join(root, pathname.slice('/assets/'.length)))
        if (!file.startsWith(await realpath(root) + path.sep)) return reject()
        const body = await readFile(file)
        const type = { '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml' }[path.extname(file)] || 'application/octet-stream'
        response.writeHead(200, { 'Content-Type': type, 'Content-Length': body.length, 'Cache-Control': 'public, max-age=31536000, immutable' })
        return response.end(body)
      } catch { return reject() }
    }
    if (pathname.startsWith('/.vite/') || pathname === '/favicon.ico') return reject()
    const proxy = http.request({ hostname: '127.0.0.1', port: backendPort, method: request.method, path: request.url, headers: { ...request.headers, connection: 'close' } }, upstream => {
      response.writeHead(upstream.statusCode, upstream.headers)
      upstream.pipe(response)
    })
    proxy.on('error', () => { response.writeHead(502); response.end() })
    request.pipe(proxy)
  })
  await new Promise(resolve => edge.listen(Number(values.port), '127.0.0.1', resolve))
  console.log(`Offline GitHub fixture / ${values.mode}: ${origin}`)
  while (!ending) await sleep(200)
} finally {
  if (edge) await new Promise(resolve => edge.close(resolve))
  for (const child of children.reverse()) await stop(child)
  await log.close()
}
