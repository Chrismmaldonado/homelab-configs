#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOST = os.environ.get("ALERTER_HOST", "172.17.0.1")
PORT = int(os.environ.get("ALERTER_PORT", "9055"))
SECRETS = Path(os.environ.get("NTFY_SECRETS", "/secrets.env"))
IGNORE_SRC = set(filter(None, os.environ.get("IGNORE_SRC", "127.0.0.1,::1").split(",")))
IGNORE_LOGTYPES = set(filter(None, os.environ.get("IGNORE_LOGTYPES", "1001").split(",")))
COOLDOWN_SEC = int(os.environ.get("ALERT_COOLDOWN_SEC", "90"))
_lock = threading.Lock()
_last: dict[str, float] = {}

KIND = {
    "4000": "SSH connect",
    "5001": "SSH login",
    "6001": "Telnet login",
    "3000": "HTTP request",
    "3001": "HTTP login",
    "1000": "FTP",
    "8001": "MySQL",
    "9001": "Redis",
    "11001": "RDP",
    "12001": "VNC",
}


def load_secrets() -> dict[str, str]:
    out: dict[str, str] = {}
    for line in SECRETS.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


SECRETS_MAP = load_secrets()


def parse_event(payload: dict) -> dict:
    msg = payload.get("message", payload)
    if isinstance(msg, str):
        try:
            msg = json.loads(msg)
        except json.JSONDecodeError:
            return {"raw": msg}
    return msg if isinstance(msg, dict) else {"raw": str(msg)}


def summarize(event: dict) -> tuple[str, str, str, str] | None:
    if "raw" in event and len(event) == 1:
        return None
    logtype = str(event.get("logtype") or "")
    if logtype in IGNORE_LOGTYPES:
        return None
    src = str(event.get("src_host") or "").strip()
    if not src or src in IGNORE_SRC:
        return None
    dst_port = event.get("dst_port")
    if dst_port in (-1, "-1", None, ""):
        return None
    node = event.get("node_id") or "canary"
    logdata = event.get("logdata") if isinstance(event.get("logdata"), dict) else {}
    kind = KIND.get(logtype, f"probe/{logtype}")
    details = []
    user = logdata.get("USERNAME") or logdata.get("username")
    if user:
        details.append(f"user={user}")
    if logdata.get("PASSWORD") or logdata.get("password"):
        details.append("password=***")
    path = logdata.get("PATH") or logdata.get("path")
    if path:
        details.append(f"path={path}")
    detail_s = (", " + ", ".join(details)) if details else ""
    title = f"OpenCanary · {kind}"
    body = f"{src} probed {node} on port {dst_port}{detail_s}"
    return title, body[:700], "high", "warning,triangular_flag_on_post"


def should_send(key: str) -> bool:
    now = time.time()
    with _lock:
        prev = _last.get(key, 0.0)
        if now - prev < COOLDOWN_SEC:
            return False
        _last[key] = now
        return True


def notify(title: str, msg: str, prio: str, tags: str) -> None:
    url = SECRETS_MAP["NTFY_URL"].rstrip("/") + "/" + SECRETS_MAP["NTFY_TOPIC"]
    req = urllib.request.Request(
        url,
        data=msg.encode(),
        method="POST",
        headers={
            "Authorization": f"Bearer {SECRETS_MAP['NTFY_TOKEN']}",
            "Title": title,
            "Priority": prio,
            "Tags": tags,
        },
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        resp.read()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        print("alerter: " + (fmt % args), flush=True)

    def _reply(self, code: int, body: bytes):
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self._reply(200 if self.path in ("/health", "/") else 404, b"ok" if self.path in ("/health", "/") else b"missing")

    def do_POST(self):
        if self.path not in ("/alert", "/"):
            self._reply(404, b"missing")
            return
        length = int(self.headers.get("Content-Length", "0") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(raw.decode() or "{}")
        except json.JSONDecodeError:
            payload = {"message": raw.decode(errors="replace")}
        event = parse_event(payload)
        summary = summarize(event)
        if summary is None:
            self._reply(200, b"ignored")
            return
        title, msg, prio, tags = summary
        key = f"{event.get('src_host')}:{event.get('dst_port')}:{event.get('logtype')}"
        try:
            if should_send(key):
                notify(title, msg, prio, tags)
                print(f"alerter: notified {key} -> {msg}", flush=True)
            else:
                print(f"alerter: cooldown skip {key}", flush=True)
            self._reply(200, b"ok")
        except Exception as e:
            print(f"alerter: notify failed: {e}", flush=True)
            self._reply(500, b"notify-failed")


if __name__ == "__main__":
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"alerter listening on {HOST}:{PORT}", flush=True)
    httpd.serve_forever()
