package orbit.vite_selftest

import orbit

from orbit.vite import Assets, ManifestError
from orbit.html import json_script

export main

def check(value, message):
  raise ValueError("orbit-vite: " + message) unless value

def rejected(&block):
  caught = false
  try:
    block()
  rescue Exception:
    caught = true
  check(caught, "expected invalid manifest/configuration to be rejected")

def main():
  parser = ArgParser()
  parser.arg("--fixtures", required: true)
  root = parser.parse_or_raise[:fixtures]
  dev = Assets(mode: :development)
  markup = dev.tags(nonce: "abc123").to_str
  check(markup.contains?("http://127.0.0.1:5173/@vite/client"), "development client")
  check(markup.contains?("http://127.0.0.1:5173/src/main.ts"), "default frontend entry")
  check(markup.contains?("nonce=\"abc123\""), "CSP nonce")
  check(dev.csp.to_str.contains?("script-src 'self' http://127.0.0.1:5173"), "development script CSP")
  check(dev.csp.to_str.contains?("connect-src 'self' http://127.0.0.1:5173 ws://127.0.0.1:5173"), "development HMR CSP")
  check(dev.csp.to_str.contains?("style-src 'self' 'unsafe-inline'") and not dev.csp.to_str.contains?("unsafe-eval"), "development styles do not relax script policy")
  secure_dev = Assets(mode: :development, dev_origin: "https://VITE.EXAMPLE.TEST:443/", hmr_origin: "wss://hmr.example.test:8443")
  check(secure_dev.dev_origin == "https://vite.example.test" and secure_dev.hmr_origin == "wss://hmr.example.test:8443", "normalized dev/HMR configuration")
  check(secure_dev.csp.to_str.contains?("connect-src 'self' https://vite.example.test wss://hmr.example.test:8443"), "custom WebSocket CSP")
  check(Assets(mode: :development, dev_origin: "https://vite.example.test").hmr_origin == "wss://vite.example.test", "HTTPS derives WSS")
  check(dev.csp.with(img_src: [:self, "https://images.example.test"]).to_str.contains?("img-src 'self' https://images.example.test"), "application CSP extension")
  rejected(): Assets(mode: :development, dev_origin: "https://user:secret@evil.test")
  rejected(): Assets(mode: :development, dev_origin: "https://vite.test/path")
  rejected(): Assets(mode: :development, dev_origin: "//vite.test")
  rejected(): Assets(mode: :development, hmr_origin: "https://hmr.example.test")
  rejected(): Assets(mode: :development, hmr_origin: "ws://hmr.example.test/path")
  rejected(): Assets(mode: :development, hmr_origin: "ws://hmr.example.test; script-src *")
  rejected(): dev.tags(nonce: "\" onload=\"bad")
  rejected(): dev.tags(entry: "src/missing.ts")
  rejected(): Assets(mode: :development, asset_base: "//elsewhere/")
  rejected(): Assets(mode: :development, entries: ["../escape.ts"])

  prod = Assets(frontend: root + "/valid", asset_base: "/static/")
  production_csp = orbit.ContentSecurityPolicy(script_src: [:self], style_src: [:self], connect_src: [:self], form_action: [:self])
  check(prod.csp.to_str == production_csp.to_str and prod.dev_origin == null and prod.hmr_origin == null, "production has no development CSP permissions")
  output = prod.tags.to_str
  expected = '<link rel="stylesheet" href="/static/assets/entry.css" crossorigin="anonymous">'
  expected += '<link rel="stylesheet" href="/static/assets/shared.css" crossorigin="anonymous">'
  expected += '<script type="module" src="/static/assets/main.js" crossorigin="anonymous"></script>'
  expected += '<link rel="modulepreload" href="/static/assets/shared.js" crossorigin="anonymous">'
  check(output == expected, "CSS ordering, deduplication, cycle handling and script/preload tags: " + output)
  check(not output.contains?("lazy"), "dynamic import remains lazy")
  check(not prod.tags(preload: false).to_str.contains?("modulepreload"), "preload switch")
  check(prod.tags(nonce: "abc123").to_str.contains?("nonce=\"abc123\""), "production nonce")
  css = Assets(frontend: root + "/valid", entries: ["src/style.css"])
  check(css.tags.to_str == '<link rel="stylesheet" href="/assets/entry.css" crossorigin="anonymous">', "CSS-only entry")
  ["missing", "parent", "absolute", "encoded", "symlink", "rootlink", "unknown", "badlist", "duplicate", "missingentry", "notentry", "badjson"].each |name|:
    rejected(): Assets(frontend: root + "/" + name)
  rejected(): Assets(frontend: root + "/valid", max_manifest_bytes: 16)
  rejected(): Assets(frontend: root + "/valid", max_chunks: 1)

  value = {uid: "9007199254740995", text: "</ScRiPt><!--<script>\"&>\u{2028}\u{2029}Ж"}
  island = json_script(value, id: "data\" onload=\"evil", nonce: "n\"x").to_str
  check(island.starts_with?('<script type="application/json" id="data&quot; onload=&quot;evil" nonce="n&quot;x">'), "escaped data island attributes")
  start = island.index(">") + 1
  encoded = island.slice(start...island.length - 9)
  check(not encoded.contains?("<") and not encoded.contains?("&") and not encoded.contains?("\u{2028}"), "HTML and Unicode separators are escaped")
  decoded = Json.parse(encoded)
  check(decoded[:text] == value[:text] and decoded[:uid] == value[:uid], "JSON island round trip")
  rejected(): json_script({}, id: "")
  print "PASS orbit-vite assets and JSON bootstrap"
