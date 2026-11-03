package fixture

# Test-only entry point. The normal application cannot select fixture endpoints.
import orbit.oauth.github as github
from orbit.vite import Assets
from app import application

export main

def main():
  parser = ArgParser()
  parser.arg("--port", type: Int, required: true)
  parser.arg("--origin", required: true)
  parser.arg("--github-origin", required: true)
  parser.arg("--mode", default: "production")
  parser.arg("--vite-origin", default: "http://127.0.0.1:5173")
  args = parser.parse_or_raise
  mode = if args[:mode] == "development" then :development else :production
  provider = github.Provider(client_id: "fixture-client", client_secret: "fixture-secret",
    redirect_uri: args[:origin] + "/auth/github/callback", scopes: ["read:user"], fetch_emails: false,
    site_url: args[:github_origin], api_url: args[:github_origin], allow_http_loopback: true)
  try:
    application(provider, Assets(mode: mode, dev_origin: args[:vite_origin]), origin: args[:origin], debug: true,
      session_secret: "fixture-session-secret-at-least-32-bytes", csrf_secret: "fixture-csrf-secret-at-least-32-bytes").run(port: args[:port])
  ensure:
    provider.close!
