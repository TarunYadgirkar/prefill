import http.server
import subprocess
import sys
import urllib.parse
from pathlib import Path

UDID = "CF361191-F960-4212-9B76-7C41256A11C9"
SPIKE = Path(__file__).resolve().parent.parent
ASSETS = SPIKE.parent.parent / "assets" / "generated"
LOGS = SPIKE / "logs"


class Handler(http.server.BaseHTTPRequestHandler):
    def _name(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        name = q.get("name", ["unnamed"])[0]
        return "".join(c for c in name if c.isalnum() or c in "-_")

    def do_GET(self):
        name = self._name()
        dest = ASSETS / f"spike-textinsert-{name}.png"
        r = subprocess.run(["xcrun", "simctl", "io", UDID, "screenshot", str(dest)], capture_output=True, text=True)
        print(f"SNAP {dest} rc={r.returncode} {r.stderr.strip()}", file=sys.stderr, flush=True)
        self.send_response(200 if r.returncode == 0 else 500)
        self.end_headers()
        self.wfile.write(str(dest).encode())

    def do_POST(self):
        name = self._name()
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        dest = LOGS / f"tree-{name}.txt"
        dest.write_bytes(body)
        print(f"TREE {dest}", file=sys.stderr, flush=True)
        self.send_response(200)
        self.end_headers()


http.server.ThreadingHTTPServer(("127.0.0.1", 8805), Handler).serve_forever()
