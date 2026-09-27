#!/usr/bin/env python3
"""Drive the production MCP OAuth client against a local authorization server fixture."""
import base64, hashlib, json, pathlib, subprocess, sys, tempfile, threading, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
ROOT = pathlib.Path(__file__).resolve().parents[2]
state = {'registrations': 0, 'challenge': None, 'refreshed': 0}

class Fixture(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def send_json(self, value, status=200, headers=None):
        body = json.dumps(value).encode()
        self.send_response(status)
        for k, v in (headers or {}).items(): self.send_header(k, v)
        self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
    def base(self): return f'http://127.0.0.1:{self.server.server_port}'
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0)); body = self.rfile.read(length).decode()
        if self.path == '/mcp':
            return self.send_json({'error': 'unauthorized'}, 401, {'WWW-Authenticate': f'Bearer resource_metadata="{self.base()}/.well-known/oauth-protected-resource/mcp", scope="read write"'})
        if self.path == '/register':
            state['registrations'] += 1
            assert json.loads(body)['token_endpoint_auth_method'] == 'none'
            return self.send_json({'client_id': 'fixture-client'}, 201)
        if self.path == '/token':
            form = dict(urllib.parse.parse_qsl(body))
            assert form['client_id'] == 'fixture-client' and form['resource'] == f'{self.base()}/mcp'
            if form['grant_type'] == 'authorization_code':
                digest = base64.urlsafe_b64encode(hashlib.sha256(form['code_verifier'].encode()).digest()).rstrip(b'=').decode()
                assert form['code'] == 'fixture-code' and digest == state['challenge'], 'PKCE verifier mismatch'
                return self.send_json({'access_token': 'token-1', 'refresh_token': 'refresh-1', 'expires_in': 1, 'token_type': 'Bearer'})
            if form['grant_type'] == 'refresh_token':
                assert form['refresh_token'] == 'refresh-1'; state['refreshed'] += 1
                return self.send_json({'access_token': 'token-2', 'expires_in': 3600, 'token_type': 'Bearer'})
        self.send_json({'error': 'not found'}, 404)
    def do_GET(self):
        url = urllib.parse.urlparse(self.path); query = dict(urllib.parse.parse_qsl(url.query))
        if url.path == '/.well-known/oauth-protected-resource/mcp':
            return self.send_json({'resource': f'{self.base()}/mcp', 'authorization_servers': [self.base()]})
        if url.path == '/.well-known/oauth-authorization-server':
            return self.send_json({'issuer': self.base(), 'authorization_endpoint': f'{self.base()}/authorize', 'token_endpoint': f'{self.base()}/token',
                                   'registration_endpoint': f'{self.base()}/register', 'code_challenge_methods_supported': ['S256']})
        if url.path == '/authorize':
            assert query['code_challenge_method'] == 'S256' and query['scope'] == 'read write' and query['resource'] == f'{self.base()}/mcp'
            state['challenge'] = query['code_challenge']
            location = query['redirect_uri'] + '?' + urllib.parse.urlencode({'code': 'fixture-code', 'state': query['state']})
            self.send_response(302); self.send_header('Location', location); self.send_header('Content-Length', '0'); self.end_headers(); return
        self.send_json({'error': 'not found'}, 404)

MAIN = '''import Foundation
@main struct Checks {
 @MainActor static func main() async throws {
  MCPOAuth.openBrowser = { url in
   Task { _ = try? await URLSession(configuration: .ephemeral).data(from: url) }
  }
  let endpoint = URL(string: CommandLine.arguments[1])!
  var session = try await MCPOAuth.signIn(endpoint: endpoint, previous: nil)
  precondition(session.accessToken == "token-1" && session.refreshToken == "refresh-1" && session.clientID == "fixture-client")
  precondition(session.redirectURI.hasPrefix("http://127.0.0.1:") && session.scope == "read write")
  try await Task.sleep(nanoseconds: 1_200_000_000)
  precondition(session.needsRefresh, "Expiry not tracked")
  session = try await MCPOAuth.refresh(session)
  precondition(session.accessToken == "token-2" && session.refreshToken == "refresh-1", "Refresh must keep the old refresh token")
  let again = try await MCPOAuth.signIn(endpoint: endpoint, previous: session)
  precondition(again.clientID == "fixture-client" && again.accessToken == "token-1")
  print("SIGNED-IN")
 }
}
'''
server = ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
threading.Thread(target=server.serve_forever, daemon=True).start()
with tempfile.TemporaryDirectory(prefix='speek-oauth-check-') as tmp:
    folder = pathlib.Path(tmp)
    (folder/'Main.swift').write_text(MAIN)
    subprocess.run(['swiftc', '-parse-as-library', str(ROOT/'Speek/Integrations/MCPOAuth.swift'), str(folder/'Main.swift'), '-o', str(folder/'check')], check=True)
    output = subprocess.run([str(folder/'check'), f'http://127.0.0.1:{server.server_port}/mcp'], check=True, capture_output=True, text=True, timeout=60).stdout
server.shutdown()
assert 'SIGNED-IN' in output
assert state['registrations'] == 1, f"expected one client registration, got {state['registrations']}"
assert state['refreshed'] == 1
print('PASS: resource and server discovery, dynamic registration, PKCE S256, loopback redirect, state, token exchange, expiry, refresh, registration reuse')
