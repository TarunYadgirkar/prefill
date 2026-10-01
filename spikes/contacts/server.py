import http.server, sys, os

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0))).decode()
        sys.stderr.write(f"POST {self.path} body={body}\n")
        self.path = self.path.split('?')[0]
        return self.do_GET()

os.chdir(os.path.join(os.path.dirname(__file__), 'web'))
http.server.ThreadingHTTPServer(('127.0.0.1', 8802), Handler).serve_forever()
