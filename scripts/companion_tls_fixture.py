"""Ephemeral HTTPS fixture for iOS URLSession tests; never uses a real pairing.

The generated certificate deliberately has the production certificate's localhost
SAN and five-year lifetime, not the synthetic Tailscale address. No private key
or real device credential is checked in or retained as a build artifact.
"""
import hashlib
import json
import ssl
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def main():
    with tempfile.TemporaryDirectory(prefix="assistant-tls-fixture-") as folder:
        cert = Path(folder) / "certificate.pem"
        key = Path(folder) / "key.pem"
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:3072", "-sha256",
            "-days", "1825", "-nodes", "-keyout", str(key), "-out", str(cert),
            "-subj", "/CN=Synthetic Assistant Computer",
            "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1",
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        fingerprint = hashlib.sha256(ssl.PEM_cert_to_DER_cert(cert.read_text(encoding="ascii"))).hexdigest()
        seen = []
        lock = threading.Lock()

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_GET(self):
                with lock:
                    seen.append({"path": self.path, "authorized": self.headers.get("Authorization") == "Bearer synthetic-device-token"})
                if self.path == "/config":
                    value = {"fingerprint": fingerprint}
                elif self.path == "/observations":
                    with lock:
                        value = {"requests": list(seen)}
                elif self.path == "/v1/redirect":
                    self.send_response(302)
                    self.send_header("Location", "http://localhost:48682/credential-sink")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                else:
                    value = {"status": "ok"}
                data = json.dumps(value).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        https = ThreadingHTTPServer(("0.0.0.0", 48683), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(cert, key)
        https.socket = context.wrap_socket(https.socket, server_side=True)
        threading.Thread(target=https.serve_forever, daemon=True).start()
        print("Synthetic TLS fixture ready", flush=True)
        ThreadingHTTPServer(("127.0.0.1", 48682), Handler).serve_forever()


if __name__ == "__main__":
    main()
