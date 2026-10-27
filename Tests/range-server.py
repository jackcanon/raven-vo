from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
PAYLOAD=bytes(range(256))*4096
class Handler(BaseHTTPRequestHandler):
 def do_GET(self):
  data=PAYLOAD if self.path!='/bad' else b'X'*len(PAYLOAD)
  offset=0
  if self.path!='/ignore-range' and self.headers.get('Range'): offset=int(self.headers['Range'].split('=')[1].split('-')[0])
  self.send_response(206 if offset else 200)
  self.send_header('Content-Length',str(len(data)-offset))
  if offset:self.send_header('Content-Range',f'bytes {offset}-{len(data)-1}/{len(data)}')
  self.end_headers();self.wfile.write(data[offset:])
 def log_message(self,*args):pass
ThreadingHTTPServer(('127.0.0.1',4349),Handler).serve_forever()
