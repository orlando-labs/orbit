<script setup lang="ts">
import { computed, ref } from 'vue'
import { post, snapshot, type SessionSnapshot } from './session'

const props = defineProps<{ initial: SessionSnapshot }>()
const state = ref(props.initial)
const busy = ref(false)
const error = ref(props.initial.auth_error ? 'GitHub sign-in was not completed. You can try again.' : '')
const account = computed(() => state.value.account)
const signedInAt = computed(() => state.value.session.authenticated_at === null ? '—' :
  new Date(state.value.session.authenticated_at * 1000).toLocaleString())

async function login() {
  busy.value = true
  error.value = ''
  try {
    const result = await post('/auth/github') as { authorize_url: string }
    const target = new URL(result.authorize_url)
    if (!['https:', 'http:'].includes(target.protocol)) throw new Error('Invalid sign-in destination')
    window.location.assign(target.href)
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : 'Sign-in could not be started.'
    busy.value = false
  }
}

async function logout() {
  busy.value = true
  error.value = ''
  try { await post('/auth/logout'); window.location.assign('/') }
  catch { error.value = 'Sign-out could not be completed. Please try again.'; busy.value = false }
}

async function refresh() {
  busy.value = true
  error.value = ''
  try {
    const response = await fetch('/api/session', { credentials: 'same-origin', cache: 'no-store', headers: { Accept: 'application/json' } })
    if (!response.ok) throw new Error('Session could not be refreshed.')
    state.value = snapshot(await response.json())
  } catch { error.value = 'Session could not be refreshed. Please reload the page.' }
  finally { busy.value = false }
}
</script>

<template>
  <section class="intro">
    <p class="eyebrow">YOUR WORKSPACE STARTS HERE</p>
    <h1>One account.<br><em>A place to begin.</em></h1>
    <p class="lede">Sign in with GitHub to connect your account.<br>This preview shows your session and profile.</p>
  </section>

  <section class="account-card" aria-labelledby="account-title" data-testid="vue-account">
    <div class="card-heading"><span class="eyebrow">ACCOUNT / 01</span><span class="status" :class="{ active: account }">{{ account ? 'Connected' : 'Not signed in' }}</span></div>
    <p v-if="error" class="error" role="alert">{{ error }}</p>
    <template v-if="account">
      <div class="profile"><div class="avatar" aria-hidden="true">{{ account.login.slice(0, 1).toUpperCase() }}</div><div><h2 id="account-title">{{ account.name || account.login }}</h2><p class="handle">@{{ account.login }}</p></div></div>
      <dl class="details"><div><dt>Provider</dt><dd>GitHub</dd></div><div><dt>Account ID</dt><dd data-testid="account-id">{{ account.uid }}</dd></div><div><dt>Signed in</dt><dd>{{ signedInAt }}</dd></div></dl>
      <div class="actions"><button class="button secondary" @click="refresh" :disabled="busy">Refresh session <span aria-hidden="true">↻</span></button><button class="text-button" @click="logout" :disabled="busy">Sign out ↗</button></div>
    </template>
    <template v-else>
      <div class="profile anonymous"><div class="avatar" aria-hidden="true">⌘</div><div><h2 id="account-title">Make yourself at home.</h2><p class="handle">Your GitHub account is your way in.</p></div></div>
      <button class="button primary" @click="login" :disabled="busy"><svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12 .8a11.2 11.2 0 0 0-3.54 21.83c.56.1.77-.24.77-.54v-2.1c-3.13.68-3.79-1.33-3.79-1.33-.51-1.3-1.25-1.65-1.25-1.65-1.02-.7.08-.68.08-.68 1.13.08 1.73 1.16 1.73 1.16 1 1.72 2.63 1.22 3.27.93.1-.73.4-1.22.71-1.5-2.5-.28-5.13-1.25-5.13-5.57 0-1.23.44-2.23 1.16-3.02-.12-.28-.5-1.43.11-2.98 0 0 .95-.3 3.08 1.15a10.7 10.7 0 0 1 5.6 0c2.14-1.45 3.08-1.15 3.08-1.15.62 1.55.23 2.7.12 2.98.72.79 1.15 1.79 1.15 3.02 0 4.33-2.63 5.28-5.14 5.56.4.35.76 1.03.76 2.08v3.1c0 .3.2.65.77.54A11.2 11.2 0 0 0 12 .8Z"/></svg>{{ busy ? 'Connecting…' : 'Continue with GitHub' }}<span aria-hidden="true">↗</span></button>
      <p class="permission-note">Read-only profile access. Your repositories stay private.</p>
    </template>
    <div class="session-strip"><span class="session-dot" aria-hidden="true"></span><span>{{ state.session.authenticated ? 'Authenticated session' : 'Anonymous session' }}</span><span class="session-meta">Cookie · {{ state.session.ttl_seconds / 60 }} min</span></div>
  </section>
  <aside class="next-note"><span class="note-icon" aria-hidden="true">↳</span><p><strong>A small first step.</strong> Notebook features will arrive here next.</p></aside>
</template>
