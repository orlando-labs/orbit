import 'vite/modulepreload-polyfill'
import { createApp } from 'vue'
import App from './App.vue'
import { snapshot } from './session'
import './style.css'

const bootstrap = document.getElementById('orbit-bootstrap')
if (!bootstrap?.textContent) throw new Error('Orbit bootstrap data is missing')
const initial = snapshot(JSON.parse(bootstrap.textContent))
createApp(App, { initial }).mount('#notebook-app')
