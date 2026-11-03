import { defineConfig } from '@playwright/test'

const mode = process.env.ORBIT_E2E_MODE || 'production'
const native = process.env.ORBIT_E2E_NATIVE === '1'
if (!['development', 'production'].includes(mode)) throw new Error('Invalid ORBIT_E2E_MODE')

const port = mode === 'development' ? 4318 : 4317
const baseURL = `http://127.0.0.1:${port}`

export default defineConfig({
  testDir: './test',
  outputDir: `test-results/${mode}-${native ? 'native' : 'vm'}`,
  workers: 1,
  fullyParallel: false,
  timeout: 30_000,
  use: { baseURL, headless: true, trace: 'retain-on-failure' },
  webServer: {
    command: `node ../tools/smoke_server.mjs --mode ${mode} --port ${port}${native ? ' --native-backend' : ''}`,
    url: baseURL,
    timeout: 60_000,
    reuseExistingServer: false,
  },
})
