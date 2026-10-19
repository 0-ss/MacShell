#!/usr/bin/env python3
"""AirDrop for MacShell, speaking LocalSend's protocol (v2).

Any device running LocalSend — phone, laptop, tablet — shows up here, and anything sent from here lands
in its downloads. Nothing is installed or configured: discovery is a UDP multicast announcement on the
local network, and sending is two HTTPS-less HTTP calls.

    macshell-airdrop.py discover [seconds]        print one JSON object per device found
    macshell-airdrop.py send <ip> <port> [--protocol http|https] <file…>
                                                  send files to a device, print progress as JSON lines
    macshell-airdrop.py serve                     be visible and receive files (answers accept/decline on stdin)
"""
import fcntl
import hashlib
import http.server
import json
import mimetypes
import os
import random
import socket
import ssl
import struct
import string
import sys
import threading
import time
import urllib.error
import urllib.request

MULTICAST = "224.0.0.167"
PORT = 53317
ALIAS = os.environ.get("MACSHELL_AIRDROP_ALIAS") or socket.gethostname()
# Stable per machine: the sending half and the receiving half must agree, or each half sees the other
# as a stranger and the radar fills up with copies of this computer.
FINGERPRINT = hashlib.sha256(("macshell:" + socket.gethostname() + ":" + (os.environ.get("USER") or "")).encode()).hexdigest()


def _ipv4_interfaces():
    """Every interface with an IPv4 address: Ethernet, Wi-Fi and the hotspot all at once.

    Multicast on Linux only goes out of one interface unless you say otherwise, which is why a phone on the
    hotspot (or on Wi-Fi while this machine is on Ethernet) never saw us and we never saw it.
    """
    out = []
    try:
        names = socket.if_nameindex()
    except OSError:
        return out
    for _, name in names:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            addr = socket.inet_ntoa(fcntl.ioctl(
                s.fileno(), 0x8915,                              # SIOCGIFADDR
                struct.pack("256s", name[:15].encode()))[20:24])
        except OSError:
            addr = None
        finally:
            s.close()
        if addr and not addr.startswith("127."):
            out.append((name, addr))
    return out


def _join_all(sock):
    """Listen for announcements on every interface, not just the default one."""
    joined = 0
    for _, addr in _ipv4_interfaces():
        try:
            sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP,
                            socket.inet_aton(MULTICAST) + socket.inet_aton(addr))
            joined += 1
        except OSError:
            pass
    if joined == 0:
        try:
            sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP,
                            socket.inet_aton(MULTICAST) + socket.inet_aton("0.0.0.0"))
        except OSError:
            pass


def _announce(sock, payload=None):
    """Say hello out of every interface."""
    data = payload if payload is not None else json.dumps(ME).encode()
    addrs = [a for _, a in _ipv4_interfaces()]
    sent = False
    for addr in addrs:
        try:
            sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(addr))
            sock.sendto(data, (MULTICAST, PORT))
            sent = True
        except OSError:
            pass
    try:
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton("0.0.0.0"))
    except OSError:
        pass
    if not sent:
        try:
            sock.sendto(data, (MULTICAST, PORT))
        except OSError:
            pass


def _register_with(ip, port, protocol="http"):
    """Tell a device about us over HTTP as well as multicast.

    Multicast is the part that gets dropped on guest networks and between a hotspot and a wired link, so
    LocalSend also accepts a plain POST that says "here I am". Doing both is what makes the two lists agree.
    """
    def go():
        for scheme in (["https", "http"] if protocol == "https" else ["http", "https"]):
            url = "%s://%s:%s/api/localsend/v2/register" % (scheme, ip, port)
            try:
                _post(url, ME, timeout=4)
                return
            except Exception:
                continue

    threading.Thread(target=go, daemon=True).start()


def _own_addresses():
    """Every address this machine answers on, so we never list ourselves."""
    out = {"127.0.0.1", "::1"}
    try:
        host = socket.gethostname()
        for fam, _, _, _, sa in socket.getaddrinfo(host, None):
            out.add(sa[0])
    except OSError:
        pass
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.255.255.255", 1))
        out.add(s.getsockname()[0])
        s.close()
    except OSError:
        pass
    for _, addr in _ipv4_interfaces():
        out.add(addr)
    return out


OWN = _own_addresses()


def _is_self(d, addr):
    """Our own announcement, our loopback copy of it, or this machine's own receiver on its own port."""
    if d.get("fingerprint") == FINGERPRINT:
        return True
    if addr[0] in ("127.0.0.1", "::1"):
        return True
    try:
        return addr[0] in OWN and int(d.get("port", PORT)) == PORT
    except (TypeError, ValueError):
        return False

ME = {
    "alias": ALIAS,
    "version": "2.1",
    "deviceModel": "MacShell",
    "deviceType": "desktop",
    "fingerprint": FINGERPRINT,
    "port": PORT,
    "protocol": "http",
    "download": False,
    "announce": True,
}


def discover(seconds=3.0):
    """Announce ourselves and print every device that answers."""
    seen = {}
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    except (AttributeError, OSError):
        pass
    try:
        sock.bind(("", PORT))
        _join_all(sock)
    except OSError:
        # another LocalSend is already bound to the port; we can still announce and catch unicast replies
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)

    payload = json.dumps(ME).encode()
    for _ in range(3):
        _announce(sock, payload)
        time.sleep(0.15)

    sock.settimeout(0.4)
    end = time.time() + float(seconds)
    while time.time() < end:
        try:
            data, addr = sock.recvfrom(8192)
        except socket.timeout:
            continue
        except OSError:
            break
        try:
            d = json.loads(data.decode())
        except (ValueError, UnicodeDecodeError):
            continue
        fp = d.get("fingerprint")
        if not fp or fp in seen or _is_self(d, addr):
            continue
        seen[fp] = True
        _register_with(addr[0], d.get("port", PORT), d.get("protocol", "http"))
        print(json.dumps({
            "alias": d.get("alias", addr[0]),
            "ip": addr[0],
            "port": d.get("port", PORT),
            "deviceModel": d.get("deviceModel", ""),
            "deviceType": d.get("deviceType", "desktop"),
            "protocol": d.get("protocol", "http"),
            "fingerprint": fp,
        }), flush=True)
        # answering an announce is what makes us visible on their screen
        if d.get("announce"):
            reply = dict(ME, announce=False)
            try:
                sock.sendto(json.dumps(reply).encode(), addr)
            except OSError:
                pass
    return 0


# LocalSend serves HTTPS with a certificate it signed itself, so verification can only ever fail.
_TLS = ssl.create_default_context()
_TLS.check_hostname = False
_TLS.verify_mode = ssl.CERT_NONE


def _open(req, timeout):
    if req.full_url.startswith("https://"):
        return urllib.request.urlopen(req, timeout=timeout, context=_TLS)
    return urllib.request.urlopen(req, timeout=timeout)


def _post(url, obj, timeout=10):
    req = urllib.request.Request(url, data=json.dumps(obj).encode(),
                                 headers={"Content-Type": "application/json"}, method="POST")
    with _open(req, timeout) as r:
        body = r.read().decode()
    return json.loads(body) if body.strip() else {}


def send(ip, port, paths, protocol=None):
    files = {}
    by_id = {}                      # the receiver answers with its own ids, so keep the mapping
    for i, p in enumerate(paths):
        if not os.path.isfile(p):
            continue
        fid = str(i)
        by_id[fid] = p
        files[fid] = {
            "id": fid,
            "fileName": os.path.basename(p),
            "size": os.path.getsize(p),
            "fileType": mimetypes.guess_type(p)[0] or "application/octet-stream",
        }
    if not files:
        print(json.dumps({"event": "error", "message": "no files"}), flush=True)
        return 1

    # Recent LocalSend builds speak HTTPS and announce it; older ones are plain HTTP. Try what the device
    # asked for first and fall back to the other, so a wrong guess is not a failed send.
    order = ["https", "http"] if protocol == "https" else ["http", "https"]
    print(json.dumps({"event": "asking"}), flush=True)
    base, res, last = None, None, None
    for scheme in order:
        attempt = "%s://%s:%s/api/localsend/v2" % (scheme, ip, port)
        try:
            res = _post(attempt + "/prepare-upload", {"info": ME, "files": files}, timeout=90)
            base = attempt
            break
        except urllib.error.HTTPError as e:
            # the device answered, so this is its decision, not the wrong scheme
            msg = "declined" if e.code in (403, 204) else ("busy" if e.code == 409 else "HTTP %s" % e.code)
            print(json.dumps({"event": "error", "message": msg}), flush=True)
            return 1
        except (OSError, ssl.SSLError) as e:
            last = e
            continue
    if base is None:
        print(json.dumps({"event": "error", "message": "could not reach the device (%s)" % last}), flush=True)
        return 1

    session = res.get("sessionId", "")
    tokens = res.get("files", {})
    if not tokens:
        print(json.dumps({"event": "error", "message": "the other device accepted nothing"}), flush=True)
        return 1
    sent = 0
    for fid, token in tokens.items():
        path = by_id.get(str(fid))
        if not path:
            continue
        url = "%s/upload?sessionId=%s&fileId=%s&token=%s" % (base, session, fid, token)
        print(json.dumps({"event": "sending", "file": os.path.basename(path)}), flush=True)
        try:
            with open(path, "rb") as fh:
                req = urllib.request.Request(url, data=fh.read(),
                                             headers={"Content-Type": "application/octet-stream"}, method="POST")
                _open(req, 600).read()
            sent += 1
        except OSError as e:
            print(json.dumps({"event": "error", "file": os.path.basename(path), "message": str(e)}), flush=True)
    print(json.dumps({"event": "done", "sent": sent, "total": len(files)}), flush=True)
    return 0 if sent else 1


class _Receiver(http.server.BaseHTTPRequestHandler):
    """The receiving half of LocalSend v2: a phone asks first, the person says yes, then the files arrive."""

    server_version = "MacShell-AirDrop"

    def log_message(self, *a):
        pass

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _copy_body(self, fh):
        """Write the request body out, however the sender chose to frame it.

        LocalSend clients stream the file: some send a Content-Length, some use chunked transfer
        encoding, and some just write until they close the connection. Reading Content-Length alone
        meant a chunked upload saved a 0-byte file and still reported success.
        """
        got = 0
        encoding = (self.headers.get("Transfer-Encoding") or "").lower()
        if "chunked" in encoding:
            while True:
                line = self.rfile.readline(1 << 16).strip()
                if not line:
                    break
                try:
                    size = int(line.split(b";", 1)[0], 16)
                except ValueError:
                    break
                if size == 0:
                    # trailers, then the blank line that ends them
                    while True:
                        trailer = self.rfile.readline(1 << 16)
                        if trailer in (b"\r\n", b"\n", b""):
                            break
                    break
                left = size
                while left > 0:
                    chunk = self.rfile.read(min(1 << 16, left))
                    if not chunk:
                        return got
                    fh.write(chunk)
                    got += len(chunk)
                    left -= len(chunk)
                self.rfile.read(2)          # the CRLF after each chunk
            return got

        length = self.headers.get("Content-Length")
        if length is not None:
            try:
                length = int(length)
            except ValueError:
                length = 0
            while got < length:
                chunk = self.rfile.read(min(1 << 16, length - got))
                if not chunk:
                    break
                fh.write(chunk)
                got += len(chunk)
            return got

        # no framing at all: the sender closes the connection when it is done
        while True:
            chunk = self.rfile.read(1 << 16)
            if not chunk:
                break
            fh.write(chunk)
            got += len(chunk)
        return got

    def do_POST(self):
        path = self.path.split("?")[0]
        if path.endswith("/register"):
            self._json(200, dict(ME, announce=False))
            return
        if path.endswith("/prepare-upload"):
            length = int(self.headers.get("Content-Length") or 0)
            try:
                req = json.loads(self.rfile.read(length).decode())
            except (ValueError, UnicodeDecodeError):
                self._json(400, {"message": "bad request"})
                return
            who = (req.get("info") or {}).get("alias", self.client_address[0])
            files = req.get("files") or {}
            session = "".join(random.choice(string.hexdigits.lower()) for _ in range(16))
            names = [f.get("fileName", "?") for f in files.values()]
            size = sum(int(f.get("size") or 0) for f in files.values())
            print(json.dumps({"event": "ask", "session": session, "from": who,
                              "files": names, "size": size}), flush=True)
            if not _wait_for_answer(session):
                self._json(403, {"message": "declined"})
                print(json.dumps({"event": "declined", "session": session}), flush=True)
                return
            tokens = {}
            for fid, f in files.items():
                tok = "".join(random.choice(string.hexdigits.lower()) for _ in range(16))
                tokens[fid] = tok
                SESSIONS.setdefault(session, {})[tok] = f.get("fileName", fid)
            self._json(200, {"sessionId": session, "files": tokens})
            print(json.dumps({"event": "accepted", "session": session}), flush=True)
            return
        if path.endswith("/upload"):
            q = dict(p.split("=", 1) for p in self.path.split("?", 1)[-1].split("&") if "=" in p)
            session, token = q.get("sessionId", ""), q.get("token", "")
            name = SESSIONS.get(session, {}).get(token)
            if not name:
                self._json(403, {"message": "unknown token"})
                return
            target = _free_path(os.path.join(DOWNLOADS, os.path.basename(name)))
            try:
                with open(target, "wb") as fh:
                    got = self._copy_body(fh)
            except OSError as e:
                self._json(500, {"message": str(e)})
                print(json.dumps({"event": "error", "file": os.path.basename(target),
                                  "message": str(e)}), flush=True)
                return
            if got <= 0:
                # nothing arrived: don't leave an empty file sitting in Downloads pretending it worked
                try:
                    os.remove(target)
                except OSError:
                    pass
                self._json(500, {"message": "empty body"})
                print(json.dumps({"event": "error", "file": os.path.basename(target),
                                  "message": "nothing was received"}), flush=True)
                return
            print(json.dumps({"event": "received", "file": os.path.basename(target),
                              "path": target, "size": got}), flush=True)
            self._json(200, {})
            return
        self._json(404, {"message": "not found"})

    def do_GET(self):
        if self.path.split("?")[0].endswith("/info"):
            self._json(200, dict(ME, announce=False))
            return
        self._json(404, {"message": "not found"})


DOWNLOADS = os.path.join(os.path.expanduser("~"), "Downloads")
SESSIONS = {}
ANSWERS = {}
ANSWER_LOCK = threading.Lock()


def _free_path(path):
    if not os.path.exists(path):
        return path
    base, ext = os.path.splitext(path)
    i = 2
    while os.path.exists("%s (%d)%s" % (base, i, ext)):
        i += 1
    return "%s (%d)%s" % (base, i, ext)


def _wait_for_answer(session, timeout=60.0):
    """Block until the UI answers on stdin, or time out as a decline."""
    end = time.time() + timeout
    while time.time() < end:
        with ANSWER_LOCK:
            if session in ANSWERS:
                return ANSWERS.pop(session)
        time.sleep(0.1)
    return False


PING = threading.Event()
ANNOUNCED = {}          # fingerprint -> address, so a device is reported once (cleared on "search")


def _read_answers():
    for line in sys.stdin:
        parts = line.strip().split()
        if len(parts) == 2 and parts[0] in ("accept", "decline"):
            with ANSWER_LOCK:
                ANSWERS[parts[1]] = parts[0] == "accept"
        elif parts and parts[0] == "search":
            # Searching again means "tell me about everyone", not "tell me about anyone new": without this
            # the radar stayed empty after the window was reopened, because every device was already known.
            ANNOUNCED.clear()
            PING.set()



def _announce_on_request(sock):
    """`search` on stdin: say hello again, so anything new answers."""
    while True:
        PING.wait()
        PING.clear()
        for _ in range(3):
            _announce(sock)
            time.sleep(0.2)


def _die_with_parent():
    """Don't outlive the shell: an orphaned receiver keeps port 53317 and the next one can never bind,
    which left AirDrop saying "Starting…" for ever after a restart."""
    # (PR_SET_PDEATHSIG is no use here: it fires when the *thread* that forked us exits, and Qt spawns
    # processes from a worker thread, so the receiver was killed the moment it started.)
    parent = os.getppid()

    def watch():
        while True:
            # reparented (to init, or to a subreaper) means whoever started us is gone
            if os.getppid() != parent:
                os._exit(0)
            time.sleep(3.0)

    threading.Thread(target=watch, daemon=True).start()


def serve():
    """Be visible to the devices around you, and take what they send."""
    os.makedirs(DOWNLOADS, exist_ok=True)
    _die_with_parent()
    threading.Thread(target=_read_answers, daemon=True).start()

    # a previous instance may still be letting go of the port: wait for it rather than giving up
    httpd = None
    for attempt in range(20):
        try:
            httpd = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), _Receiver)
            break
        except OSError as e:
            if attempt == 0:
                print(json.dumps({"event": "waiting", "message": str(e)}), flush=True)
            time.sleep(1.0)
    if httpd is None:
        print(json.dumps({"event": "error", "message": "port %d is busy" % PORT}), flush=True)
        return 1
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    print(json.dumps({"event": "ready", "alias": ALIAS, "port": PORT, "downloads": DOWNLOADS}), flush=True)

    # answer every announce on the network, so we show up on their screen without them searching
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    except (AttributeError, OSError):
        pass
    try:
        sock.bind(("", PORT))
        _join_all(sock)
    except OSError:
        pass
    _announce(sock)
    sock.settimeout(1.0)
    announced = ANNOUNCED
    threading.Thread(target=_announce_on_request, args=(sock,), daemon=True).start()
    # interfaces come and go (the hotspot, a cable, a VPN): rejoin and say hello again every now and then,
    # so a device that appears on a new network still finds us without anyone pressing Search
    def _keepalive():
        while True:
            time.sleep(20.0)
            try:
                _join_all(sock)
                _announce(sock)
            except OSError:
                pass

    threading.Thread(target=_keepalive, daemon=True).start()
    while True:
        try:
            data, addr = sock.recvfrom(8192)
        except socket.timeout:
            continue
        except OSError:
            break
        try:
            d = json.loads(data.decode())
        except (ValueError, UnicodeDecodeError):
            continue
        if _is_self(d, addr):
            continue
        if announced.get(d.get("fingerprint")) == addr[0]:
            # already on the list; answering again is enough
            if d.get("announce"):
                try:
                    sock.sendto(json.dumps(dict(ME, announce=False)).encode(), addr)
                except OSError:
                    pass
            continue
        announced[d.get("fingerprint")] = addr[0]
        _register_with(addr[0], d.get("port", PORT), d.get("protocol", "http"))
        print(json.dumps({"event": "device", "alias": d.get("alias", addr[0]), "ip": addr[0],
                          "port": d.get("port", PORT), "deviceModel": d.get("deviceModel", ""),
                          "deviceType": d.get("deviceType", "desktop"),
                          "protocol": d.get("protocol", "http"),
                          "fingerprint": d.get("fingerprint", addr[0])}), flush=True)
        if d.get("announce"):
            try:
                sock.sendto(json.dumps(dict(ME, announce=False)).encode(), addr)
            except OSError:
                pass
    return 0


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd = argv[1]
    if cmd == "discover":
        return discover(argv[2] if len(argv) > 2 else 3.0)
    if cmd == "send" and len(argv) >= 5:
        # send <ip> <port> [--protocol http|https] <file…>
        rest, proto = argv[4:], None
        if rest and rest[0] == "--protocol" and len(rest) > 1:
            proto, rest = rest[1], rest[2:]
        if not rest:
            print(__doc__)
            return 2
        return send(argv[2], argv[3], rest, proto)
    if cmd == "serve":
        return serve()
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
