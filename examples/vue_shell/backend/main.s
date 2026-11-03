package main

from orbit import Origin
import orbit.oauth.github as github
from orbit.vite import Assets
from app import application

export main

def main():
  parser = ArgParser(name: "orbit-vue-shell")
  parser.arg("--mode", choices: ["development", "production"], default: "production", env: "ORBIT_MODE")
  parser.arg("--port", type: Int, default: 3000, env: "ORBIT_PORT")
  parser.arg("--origin", default: "http://127.0.0.1:3000", env: "ORBIT_ORIGIN")
  parser.arg("--vite-origin", default: "http://127.0.0.1:5173", env: "VITE_ORIGIN")
  parser.arg("--client-id", required: true, env: "GITHUB_CLIENT_ID")
  parser.arg("--client-secret", required: true, env: "GITHUB_CLIENT_SECRET")
  parser.arg("--session-secret", required: true, env: "ORBIT_SESSION_SECRET")
  parser.arg("--csrf-secret", required: true, env: "ORBIT_CSRF_SECRET")
  parser.flag("--behind-proxy")
  args = parser.parse_or_raise
  origin = Origin(args[:origin])
  mode = if args[:mode] == "development" then :development else :production
  assets = Assets(mode: mode, dev_origin: args[:vite_origin])
  provider = github.Provider(client_id: args[:client_id], client_secret: args[:client_secret],
    redirect_uri: origin.to_str + "/auth/github/callback", scopes: ["read:user"], fetch_emails: false,
    allow_http_loopback: mode == :development)
  try:
    application(provider, assets, session_secret: args[:session_secret], csrf_secret: args[:csrf_secret],
      origin: origin, behind_proxy: args[:behind_proxy]).run(port: args[:port])
  ensure:
    provider.close!
