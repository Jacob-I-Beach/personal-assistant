"""Synthetic loopback SSE fixture. No LLM, credentials, or external network calls."""
import argparse
import json
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import time


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *_):
        pass

    def do_POST(self):
        size = int(self.headers.get("Content-Length", "0"))
        if size > 2_000_000:
            self.send_error(413)
            return
        body = json.loads(self.rfile.read(size))
        if self.path.startswith("/redirect/"):
            self.send_response(307)
            self.send_header("Location", "/v1/responses")
            self.end_headers()
            return
        if self.path.startswith("/unauthorized/"):
            self.send_error(401)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        if self.path.startswith("/flood/"):
            try:
                for _ in range(256):
                    self.wfile.write(b"A" * 65536)
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        if self.path.endswith("/chat/completions"):
            events = [
                {"choices": [{"delta": {"content": "Hello 🌎"}, "finish_reason": None}]},
                {"choices": [{"delta": {}, "finish_reason": "stop"}]},
                "[DONE]",
            ]
        elif self.path.startswith("/empty/"):
            events = [{"type": "response.completed", "response": {"status": "completed", "output": []}}]
        elif self.path.startswith(("/tool/", "/tool-empty/")) and not any(item.get("type") == "function_call_output" for item in body.get("input", [])):
            # Attachments are app metadata, never invented user-authored text.
            capture_id = re.search(r'"capture_id":"([A-Fa-f0-9-]+)"', body["instructions"]).group(1)
            call = {"type": "function_call", "id": "fc_fixture", "call_id": "call_fixture", "name": "read_capture", "arguments": json.dumps({"capture_id": capture_id})}
            events = [{"type": "response.output_item.done", "output_index": 0, "item": call}, {"type": "response.completed", "response": {"output": [] if self.path.startswith("/tool-empty/") else [call]}}]
        else:
            text = "Verified saved capture." if self.path.startswith(("/tool/", "/tool-empty/")) else "Hello 🌎"
            events = [{"type": "response.output_text.delta", "delta": text}]
            if self.path.startswith("/failed/"):
                events.append({"type": "response.failed", "response": {"error": {"message": "Synthetic failure after a partial answer"}}})
            elif not self.path.startswith("/cut/"):
                events.append({"type": "response.completed", "response": {"output": [{"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": text}]}]}})
        try:
            for event in events:
                payload = event if isinstance(event, str) else json.dumps(event, ensure_ascii=False)
                wire = ("data: " + payload + "\r\n\r\n").encode("utf-8")
                for start in range(0, len(wire), 7):
                    self.wfile.write(wire[start:start + 7])
                    self.wfile.flush()
                    time.sleep(0.001)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port-file", required=True)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    port_file = Path(args.port_file)
    port_file.parent.mkdir(parents=True, exist_ok=True)
    port_file.write_text(str(server.server_port), encoding="utf-8")
    server.serve_forever()
