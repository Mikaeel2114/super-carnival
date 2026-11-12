"""LumaLink: opt-in, view-only LAN screen sharing."""
from __future__ import annotations
import io, ipaddress, json, os, queue, secrets, socket, sys, threading, time
from http import cookies
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

BASE = getattr(sys, '_MEIPASS', os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WEB = os.path.join(BASE, 'host', 'web', 'index.html')


def private_ipv4(s):
    try:
        ip = ipaddress.ip_address(s)
        return ip.version == 4 and (ip.is_private or ip.is_loopback) and not ip.is_link_local and not ip.is_unspecified
    except ValueError:
        return False


def detect_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # No data is sent; this only asks the OS which interface it would use.
        s.connect(('192.168.1.1', 9))
        addr = s.getsockname()[0]
        return addr if private_ipv4(addr) and not addr.startswith('127.') else ''
    except OSError:
        return ''
    finally:
        s.close()

class State:
    def __init__(self, address, port):
        self.address, self.port = address, port
        self.code = f'{secrets.randbelow(1000000):06d}'
        self.lock = threading.Lock()
        self.sessions = {}
        self.attempts = {}
        self.requests = queue.Queue()
        self.running = True
    def valid(self, token, ip):
        with self.lock:
            rec = self.sessions.get(token)
            return self.running and bool(rec) and rec[0] == ip and rec[1] > time.time()
    def stop(self):
        with self.lock:
            self.running = False
            self.sessions.clear()

class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    def __init__(self, address, state):
        super().__init__(address, Handler)
        self.state = state

class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *_): pass  # Never log pairing codes or cookies.
    @property
    def state(self): return self.server.state
    def peer_ok(self): return private_ipv4(self.client_address[0])
    def host_ok(self):
        return self.headers.get('Host', '') == f'{self.state.address}:{self.state.port}'
    def origin_ok(self):
        return self.headers.get('Origin', '') == f'http://{self.state.address}:{self.state.port}'
    def headers_common(self):
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'DENY')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' blob: data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'")
    def reply(self, code, body, content='text/plain; charset=utf-8', extra=None):
        if isinstance(body, str): body = body.encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', content)
        self.send_header('Content-Length', str(len(body)))
        self.headers_common()
        if extra:
            for k, v in extra.items(): self.send_header(k, v)
        self.end_headers()
        try: self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError): pass
    def token(self):
        try:
            jar = cookies.SimpleCookie(self.headers.get('Cookie', ''))
            return jar['ll_session'].value if 'll_session' in jar else ''
        except cookies.CookieError: return ''
    def permitted(self): return self.state.valid(self.token(), self.client_address[0])
    def gate(self):
        if not self.state.running or not self.peer_ok() or not self.host_ok():
            self.reply(403, 'Unavailable')
            return False
        return True
    def do_GET(self):
        if not self.gate(): return
        url = urlparse(self.path)
        if url.path == '/':
            try:
                with open(WEB, 'rb') as f: self.reply(200, f.read(), 'text/html; charset=utf-8')
            except OSError: self.reply(500, 'Web interface missing')
        elif url.path == '/api/status':
            self.reply(200, json.dumps({'connected': self.permitted()}), 'application/json')
        elif url.path == '/api/frame':
            if not self.permitted():
                self.reply(401, 'Approval required'); return
            query = parse_qs(url.query)
            try:
                width = max(320, min(1920, int(query.get('w', ['1280'])[0])))
                quality = max(30, min(85, int(query.get('q', ['65'])[0])))
                # ImageGrab is only run after the PC owner approves this device.
                from PIL import ImageGrab
                image = ImageGrab.grab(all_screens=False).convert('RGB')
                if image.width > width:
                    image.thumbnail((width, 4000))
                out = io.BytesIO()
                image.save(out, format='JPEG', quality=quality, optimize=False)
                self.reply(200, out.getvalue(), 'image/jpeg')
            except Exception:
                self.reply(503, 'Screen capture failed. Check the Windows desktop is unlocked.')
        else: self.reply(404, 'Not found')
    def do_POST(self):
        if not self.gate(): return
        if not self.origin_ok(): self.reply(403, 'Invalid origin'); return
        path = urlparse(self.path).path
        if path == '/api/disconnect':
            with self.state.lock: self.state.sessions.pop(self.token(), None)
            self.reply(200, '{}', 'application/json', {'Set-Cookie': 'll_session=; Max-Age=0; HttpOnly; SameSite=Strict; Path=/'})
            return
        if path != '/api/pair': self.reply(404, 'Not found'); return
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if length < 1 or length > 256: raise ValueError()
            data = json.loads(self.rfile.read(length).decode())
            code = str(data.get('code', ''))
        except (ValueError, UnicodeError, AttributeError):
            self.reply(400, 'Invalid request'); return
        ip = self.client_address[0]
        now = time.time()
        with self.state.lock:
            attempts = [t for t in self.state.attempts.get(ip, []) if t > now - 600]
            if len(attempts) >= 5:
                self.reply(429, 'Too many attempts. Wait ten minutes.'); return
            attempts.append(now)
            self.state.attempts[ip] = attempts
        if not secrets.compare_digest(code, self.state.code):
            self.reply(401, 'Wrong code'); return
        req = {'ip': ip, 'event': threading.Event(), 'accepted': False, 'deadline': time.time() + 60}
        self.state.requests.put(req)
        req['event'].wait(60)
        if not req['accepted'] or not self.state.running or time.time() > req['deadline']:
            self.reply(403, 'Request was denied or timed out'); return
        token = secrets.token_urlsafe(32)
        with self.state.lock:
            if not self.state.running: self.reply(403, 'Sharing stopped'); return
            self.state.sessions[token] = (ip, time.time() + 3600)
        self.reply(200, '{"ok":true}', 'application/json', {'Set-Cookie': f'll_session={token}; Max-Age=3600; HttpOnly; SameSite=Strict; Path=/'})


def serve(state):
    server = Server((state.address, state.port), state)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server
