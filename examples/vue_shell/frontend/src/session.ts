export interface Account {
  provider: 'github'
  uid: string
  login: string
  name: string | null
}

export interface SessionSnapshot {
  schema: 'orbit.vue-shell.v1'
  account: Account | null
  session: { authenticated: boolean; store: 'cookie'; ttl_seconds: number; authenticated_at: number | null }
  auth_error: boolean
}

export function snapshot(value: unknown): SessionSnapshot {
  const data = value as SessionSnapshot
  if (data?.schema !== 'orbit.vue-shell.v1' || typeof data.session?.authenticated !== 'boolean' ||
      data.session.store !== 'cookie' || !Number.isSafeInteger(data.session.ttl_seconds) ||
      typeof data.auth_error !== 'boolean' ||
      (data.session.authenticated_at !== null && !Number.isSafeInteger(data.session.authenticated_at)) ||
      (data.account !== null && (data.account?.provider !== 'github' || typeof data.account.uid !== 'string' ||
        typeof data.account.login !== 'string' || (data.account.name !== null && typeof data.account.name !== 'string'))) ||
      data.session.authenticated !== (data.account !== null)) {
    throw new Error('The session response could not be read. Please reload the page.')
  }
  return data
}

export async function post(path: string): Promise<unknown> {
  const token = document.cookie.split('; ').find(cookie => cookie.startsWith('orbit-csrf='))?.slice('orbit-csrf='.length)
  if (!token) throw new Error('Your session needs to be refreshed. Reload the page and try again.')
  const response = await fetch(path, {
    method: 'POST', credentials: 'same-origin',
    headers: { 'X-CSRF-Token': decodeURIComponent(token), 'Accept': 'application/json' },
  })
  if (!response.ok) throw new Error('The request could not be completed. Reload the page and try again.')
  if (response.status === 204) return
  return response.json()
}
