package orbit.oauth.github

import orbit.oauth as oauth
from orbit.oauth._protocol import endpoint, text

export GitHub as Provider

class GitHub < oauth.Provider:
  def init(
    client_id:,
    client_secret:,
    redirect_uri:,
    scopes: ["read:user", "user:email"],
    fetch_emails: true,
    name: :github,
    site_url: "https://github.com",
    api_url: "https://api.github.com",
    api_version: "2026-03-10",
    user_agent: "orbit-oauth-github",
    authorization_params: {},
    transport: null,
    clock: null,
    allow_http_loopback: false
  ):
    endpoint(site_url, allow_http_loopback: allow_http_loopback)
    endpoint(api_url, allow_http_loopback: allow_http_loopback)
    raise ArgumentError("GitHub base URLs must not end in a slash") if site_url.ends_with?("/") or api_url.ends_with?("/")
    @api_url = api_url
    @fetch_emails = fetch_emails
    raise ArgumentError("fetch_emails must be Bool") unless Bool === @fetch_emails
    @api_version = text(api_version, "GitHub API version", 32)
    @user_agent = text(user_agent, "GitHub User-Agent", 256)
    super(name: name, authorize_url: site_url + "/login/oauth/authorize",
      token_url: site_url + "/login/oauth/access_token", client_id: client_id,
      client_secret: client_secret, redirect_uri: redirect_uri, scopes: scopes,
      token_auth: :post, scope_separator: ",", authorization_params: authorization_params, transport: transport,
      clock: clock, allow_http_loopback: allow_http_loopback)

  def _get(path, token):
    json_request(:get, @api_url + path, limit: 131072, headers: {
      accept: "application/vnd.github+json", authorization: token.authorization,
      "user-agent": @user_agent, "x-github-api-version": @api_version})

  def identity(token):
    profile = _get("/user", token)
    unless Map === profile and Int === profile[?:id] and profile[:id] > 0 and Str === profile[?:login] and profile[:login].present?:
      raise oauth.ProtocolError("invalid GitHub user profile")
    email = null
    if @fetch_emails:
      emails = _get("/user/emails?per_page=100", token)
      raise oauth.ProtocolError("invalid GitHub email response") unless Array === emails
      emails.each |entry|:
        unless Map === entry and Str === entry[?:email] and Bool === entry[?:primary] and Bool === entry[?:verified]:
          raise oauth.ProtocolError("invalid GitHub email entry")
        email = entry[:email] if entry[:primary] and entry[:verified]
    info = {login: profile[:login], name: profile[?:name], email: email,
      email_verified: email != null, avatar_url: profile[?:avatar_url], url: profile[?:html_url]}
    oauth.Identity(name, profile[:id].to_str, info: info, raw: profile)

  def client_credentials(scopes: []):
    raise ArgumentError("GitHub OAuth Apps do not support client credentials grants")
