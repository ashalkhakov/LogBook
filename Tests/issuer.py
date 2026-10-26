#!/usr/bin/env python3
"""An OpenID Connect provider's part a service sees, for the checks: its
discovery document and its keys, on loopback; and access tokens it signs
(serve-and-check.py imports it).

    Tests/issuer.py out.json anna@example.org ben@example.org

serves until it is stopped, once it has written its URL and a token for
each user to out.json: {"url": ..., "tokens": {email: token}} (a server
started with -JWTIssuer <url> trusts them; sync-check.sh runs it so)."""
import base64
import http.server
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import uuid


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


class Issuer:
    """An OpenID Connect provider's part a service sees: its discovery
    document and its keys, on loopback; and access tokens it signs."""

    def __init__(self):
        self.directory = tempfile.mkdtemp()
        self.key = os.path.join(self.directory, "key.pem")
        subprocess.run(["openssl", "genrsa", "-out", self.key, "2048"], check=True, capture_output=True)
        modulus = subprocess.run(["openssl", "rsa", "-in", self.key, "-noout", "-modulus"], check=True,
                                 capture_output=True, text=True).stdout.strip().split("=", 1)[1]
        self.jwk = {"kty": "RSA", "kid": "test", "use": "sig", "alg": "RS256",
                    "n": b64url(bytes.fromhex(modulus)), "e": b64url((65537).to_bytes(3, "big"))}
        issuer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                answers = {"/.well-known/openid-configuration": {"issuer": issuer.url, "jwks_uri": issuer.url + "/keys"},
                           "/keys": {"keys": [issuer.jwk]}}
                answer = answers.get(self.path)
                self.send_response(200 if answer else 404)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(answer or {}).encode())

            def log_message(self, *args):
                pass

        self.http = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = "http://127.0.0.1:%d" % self.http.server_address[1]
        threading.Thread(target=self.http.serve_forever, daemon=True).start()
        self.tokens = {}

    def token(self, email):
        """An access token for the user, as the provider gives one."""
        if email not in self.tokens:
            now = int(time.time())
            header = b64url(json.dumps({"alg": "RS256", "typ": "JWT", "kid": "test"}).encode())
            claims = b64url(json.dumps({"iss": self.url, "sub": str(uuid.uuid5(uuid.NAMESPACE_URL, email)), "email": email,
                                        "iat": now, "exp": now + 3600, "scope": "openid email"}).encode())
            signed = subprocess.run(["openssl", "dgst", "-sha256", "-sign", self.key], input=(header + "." + claims).encode(),
                                    check=True, capture_output=True).stdout
            self.tokens[email] = header + "." + claims + "." + b64url(signed)
        return self.tokens[email]

    def close(self):
        self.http.shutdown()


if __name__ == "__main__":
    issuer = Issuer()
    out = {"url": issuer.url, "tokens": {email: issuer.token(email) for email in sys.argv[2:]}}
    with open(sys.argv[1] + ".part", "w") as f:
        json.dump(out, f)
    os.rename(sys.argv[1] + ".part", sys.argv[1])
    issuer.http.serve_forever()
