#!/usr/bin/env python3
# usage: snap-server.py <sim-udid> <out-dir> [port]
# Lets UI tests running in the simulator ask the Mac for a screenshot or a screen
# recording, which only xcrun simctl can take:
#   GET /snap?name=ui-card-light       -> <out-dir>/ui-card-light.png
#   GET /record/start?name=motion      -> starts <out-dir>/motion.mov
#   GET /record/stop                   -> stops the recording
import http.server
import os
import re
import signal
import subprocess
import sys
from urllib.parse import parse_qs, urlparse

udid, out_dir = sys.argv[1], sys.argv[2]
port = int(sys.argv[3]) if len(sys.argv) > 3 else 8834
recording = {}


def safe(name):
    return re.sub(r"[^A-Za-z0-9._-]", "-", name)


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        url = urlparse(self.path)
        name = safe(parse_qs(url.query).get("name", ["snap"])[0])
        if url.path == "/snap":
            subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", os.path.join(out_dir, name + ".png")],
                           check=False, capture_output=True)
        elif url.path == "/record/start":
            path = os.path.join(out_dir, name + ".mov")
            recording["proc"] = subprocess.Popen(
                ["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", "--force", path],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        elif url.path == "/record/stop" and "proc" in recording:
            proc = recording.pop("proc")
            proc.send_signal(signal.SIGINT)
            proc.wait(timeout=20)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *args):
        pass


http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
