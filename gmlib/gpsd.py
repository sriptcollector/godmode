"""`gm gpsd` — a tiny LAN daemon so the phone drives the whole-phone GPS spoof itself.

The phone can't move its *system* location without a USB host (no jailbreak). So we run this on
the Mac: leave it plugged into the phone, and the GODMODE app's map POSTs {lat,lon} here to set or
clear the location. You operate entirely from the phone; the Mac is just the plugged-in relay.

    gm gpsd                 # start it; prints the URL + token to type into the app

Endpoints (all require the token, via ?token= or the X-GM-Token header):
    POST /set   {"lat": .., "lon": ..}
    POST /off
    GET  /status
"""
import json
import os
import secrets
import socket
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import gps
from .device import DeviceError

PORT = 8777
TOKENFILE = os.path.expanduser("~/.godmode/gpsd.token")
_held = {"lat": None, "lon": None}


def _token():
    os.makedirs(os.path.dirname(TOKENFILE), exist_ok=True)
    if os.path.exists(TOKENFILE):
        return open(TOKENFILE).read().strip()
    t = secrets.token_hex(4)
    with open(TOKENFILE, "w") as f:
        f.write(t)
    return t


def _lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except OSError:
        return "127.0.0.1"


def serve():
    token = _token()
    ip = _lan_ip()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass  # quiet

        def _auth(self):
            from urllib.parse import urlparse, parse_qs
            q = parse_qs(urlparse(self.path).query)
            got = self.headers.get("X-GM-Token") or (q.get("token", [""])[0])
            return got == token

        def _send(self, code, obj):
            body = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Headers", "X-GM-Token, Content-Type")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_OPTIONS(self):
            self._send(200, {"ok": True})

        def do_GET(self):
            if not self._auth():
                return self._send(401, {"error": "bad token"})
            if self.path.split("?")[0] == "/status":
                return self._send(200, {"held": _held["lat"] is not None, **_held})
            self._send(404, {"error": "not found"})

        def do_POST(self):
            if not self._auth():
                return self._send(401, {"error": "bad token"})
            path = self.path.split("?")[0]
            n = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(n) if n else b"{}"
            try:
                data = json.loads(raw or b"{}")
            except ValueError:
                data = {}
            try:
                if path == "/off":
                    gps.clear()
                    _held["lat"] = _held["lon"] = None
                    print("  ↻ cleared (back to real GPS)")
                    return self._send(200, {"held": False})
                if path == "/set":
                    lat, lon = float(data["lat"]), float(data["lon"])
                    # run the (slow, blocking) tunnel+hold off the HTTP thread so the app gets a fast reply
                    print(f"  → set {lat:.5f}, {lon:.5f}")
                    threading.Thread(target=_apply, args=(lat, lon), daemon=True).start()
                    _held["lat"], _held["lon"] = lat, lon
                    return self._send(200, {"held": True, "lat": lat, "lon": lon})
            except (KeyError, ValueError):
                return self._send(400, {"error": "need lat and lon"})
            except DeviceError as e:
                return self._send(500, {"error": str(e)})
            self._send(404, {"error": "not found"})

    def _apply(lat, lon):
        try:
            gps.set_location(f"{lat},{lon}")
        except DeviceError as e:
            print(f"  ✗ {e}")
            _held["lat"] = _held["lon"] = None

    httpd = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print("GODMODE gpsd — control your phone's location from the phone.")
    print("Leave this running, phone plugged in. In the app's GPS tab, enter:")
    print(f"\n   host:   http://{ip}:{PORT}")
    print(f"   token:  {token}\n")
    print("Tap the map in the app → your phone (and Snapchat) moves. Ctrl+C to stop.")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nstopping; clearing any held location…")
        gps.clear()
        httpd.shutdown()
