"""
Helper script to authenticate with Audio.com via OAuth 2.1 PKCE
and obtain an AUDIO_COM_TOKEN for services/transcriber/.env.
"""

import base64
import hashlib
import http.server
import json
import secrets
import sys
import urllib.parse
import webbrowser
import requests

CLIENT_REGISTRATION_URL = "https://api.audio.com/auth/client"
AUTHORIZE_URL = "https://api.audio.com/auth/authorize"
TOKEN_URL = "https://api.audio.com/auth/token"
REDIRECT_URI = "http://localhost:8080/callback"


def generate_code_verifier() -> str:
    return secrets.token_urlsafe(64)


def generate_code_challenge(verifier: str) -> str:
    digest = hashlib.sha256(verifier.encode("utf-8")).digest()
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode("utf-8")


def register_client() -> str:
    resp = requests.post(
        CLIENT_REGISTRATION_URL,
        json={
            "client_name": "ChristianTubeTranscriber",
            "redirect_uris": [REDIRECT_URI],
        },
        timeout=15,
    )
    if resp.status_code not in (200, 201):
        raise RuntimeError(f"Client registration failed ({resp.status_code}): {resp.text}")
    data = resp.json()
    return data["client_id"]


def main():
    print("1. Registering dynamic OAuth client with Audio.com...")
    try:
        client_id = register_client()
    except Exception as e:
        print(f"Failed to register client: {e}")
        sys.exit(1)

    code_verifier = generate_code_verifier()
    code_challenge = generate_code_challenge(code_verifier)
    state = secrets.token_hex(16)

    auth_params = {
        "client_id": client_id,
        "response_type": "code",
        "redirect_uri": REDIRECT_URI,
        "code_challenge": code_challenge,
        "code_challenge_method": "S256",
        "state": state,
    }
    auth_url = f"{AUTHORIZE_URL}?{urllib.parse.urlencode(auth_params)}"

    auth_code = None

    class OAuthHandler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            nonlocal auth_code
            parsed = urllib.parse.urlparse(self.path)
            if parsed.path == "/callback":
                params = urllib.parse.parse_qs(parsed.query)
                code = params.get("code", [None])[0]
                if code:
                    auth_code = code
                    self.send_response(200)
                    self.send_header("Content-Type", "text/html")
                    self.end_headers()
                    self.wfile.write(
                        b"<h2>Authentication successful!</h2><p>You can close this tab and return to the console.</p>"
                    )
                else:
                    err = params.get("error", ["Unknown error"])[0]
                    self.send_response(400)
                    self.end_headers()
                    self.wfile.write(f"Authentication failed: {err}".encode("utf-8"))
            else:
                self.send_response(404)
                self.end_headers()

        def log_message(self, format, *args):
            pass

    server = http.server.HTTPServer(("localhost", 8080), OAuthHandler)
    server.timeout = 180

    print("2. Opening browser for Audio.com authorization...")
    print(f"URL: {auth_url}")
    webbrowser.open(auth_url)

    print("Waiting for login authorization callback on http://localhost:8080/callback (timeout 3m)...")
    while not auth_code:
        server.handle_request()

    print("3. Exchanging code for Access Token...")
    token_resp = requests.post(
        TOKEN_URL,
        data={
            "grant_type": "authorization_code",
            "client_id": client_id,
            "code": auth_code,
            "redirect_uri": REDIRECT_URI,
            "code_verifier": code_verifier,
        },
        timeout=15,
    )

    if token_resp.status_code != 200:
        print(f"Failed to exchange token ({token_resp.status_code}): {token_resp.text}")
        sys.exit(1)

    data = token_resp.json()
    access_token = data.get("access_token")
    if not access_token:
        print(f"No access_token found in response: {data}")
        sys.exit(1)

    print("\n" + "=" * 60)
    print("SUCCESS! Here is your AUDIO_COM_TOKEN:")
    print("=" * 60)
    print(access_token)
    print("=" * 60)
    print("\nAdd this line to your services/transcriber/.env file:")
    print(f"AUDIO_COM_TOKEN={access_token}")


if __name__ == "__main__":
    main()
