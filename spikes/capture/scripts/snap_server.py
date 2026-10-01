import http.server
import subprocess
import sys
import urllib.parse
from pathlib import Path

UDID = "7395317A-E54F-4CA6-8E64-6D8D22109587"
SPIKE = Path(__file__).resolve().parent.parent
ASSETS = SPIKE.parent.parent / "assets" / "generated"
LOGS = SPIKE / "logs"


class Handler(http.server.BaseHTTPRequestHandler):
    def _name(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        name = q.get("name", ["unnamed"])[0]
        return "".join(c for c in name if c.isalnum() or c in "-_")

    def do_GET(self):
        dest = ASSETS / f"spike-capture-{self._name()}.png"
        r = subprocess.run(["xcrun", "simctl", "io", UDID, "screenshot", str(dest)], capture_output=True, text=True)
        print(f"SNAP {dest} rc={r.returncode} {r.stderr.strip()}", file=sys.stderr, flush=True)
        self.send_response(200 if r.returncode == 0 else 500)
        self.end_headers()
        self.wfile.write(str(dest).encode())

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        dest = LOGS / f"ui-{self._name()}.txt"
        dest.write_bytes(body)
        print(f"TREE {dest}", file=sys.stderr, flush=True)
        self.send_response(200)
        self.end_headers()


http.server.ThreadingHTTPServer(("127.0.0.1", 8824), Handler).serve_forever()
