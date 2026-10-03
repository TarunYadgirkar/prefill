#!/usr/bin/env python3
# usage: e2e-server.py <port> <simulator-udid> <screenshot-dir>
# Test-only helper for scripts/test.sh e2e. Serves testbed/sites to Safari in the simulator
# (localhost and 127.0.0.1 are two different sites to Safari and to Prefill), takes
# simulator screenshots when the UI test asks, and reports the Alex Rivera card's values
# in stored order by reading the simulator's private contacts database read-only
# (research/REPORT.md, Appendix A). Form posts are read and discarded, never logged.
import http.server
import json
import sqlite3
import subprocess
import sys
import urllib.parse
from pathlib import Path

PORT = int(sys.argv[1])
UDID = sys.argv[2]
SHOTS = Path(sys.argv[3])
SITES = Path(__file__).resolve().parent.parent / "testbed" / "sites"
CONTACTS = (
    Path.home() / "Library/Developer/CoreSimulator/Devices" / UDID / "data/Library/AddressBook/AddressBook.sqlitedb"
)
EMAIL, PHONE, ADDRESS, URL = 4, 3, 5, 22
TYPES = {".html": "text/html; charset=utf-8", ".css": "text/css"}


def card():
    db = sqlite3.connect(f"file:{CONTACTS}?mode=ro", uri=True)
    try:
        row = db.execute("select ROWID from ABPerson where First = 'Alex' and Last = 'Rivera'").fetchone()
        if row is None:
            return {"error": "Alex Rivera not found"}

        def values(prop):
            query = "select value from ABMultiValue where record_id = ? and property = ? order by identifier"
            return [value for (value,) in db.execute(query, (row[0], prop))]

        return {"emails": values(EMAIL), "phones": values(PHONE), "addressCount": len(values(ADDRESS)), "linkCount": len(values(URL))}
    finally:
        db.close()


def safe_name(raw):
    return "".join(c for c in raw if c.isalnum() or c in "-_") or "unnamed"


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, status, body, content_type="text/plain"):
        data = body if isinstance(body, bytes) else body.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def page(self, name):
        path = SITES / name
        if path.parent != SITES or path.suffix not in TYPES or not path.is_file():
            return self.reply(404, "not found")
        return self.reply(200, path.read_bytes(), TYPES[path.suffix])

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(url.query)
        if url.path == "/snap":
            dest = SHOTS / f"e2e-ext-{safe_name(query.get('name', [''])[0])}.png"
            done = subprocess.run(["xcrun", "simctl", "io", UDID, "screenshot", str(dest)], capture_output=True)
            return self.reply(200 if done.returncode == 0 else 500, str(dest))
        if url.path == "/card":
            return self.reply(200, json.dumps(card()), "application/json")
        return self.page(url.path.lstrip("/") or "signup.html")

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        return self.page("thanks.html")


SHOTS.mkdir(parents=True, exist_ok=True)
http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
