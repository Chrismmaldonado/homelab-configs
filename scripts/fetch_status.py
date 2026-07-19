#!/usr/bin/env python3
"""Pull Maintenant endpoint status + host metrics; write status.json for the static site."""
import json
import hashlib
import shutil
import socket
import struct
import time
import urllib.request
import pathlib
from datetime import datetime, timezone

OUT = pathlib.Path("/opt/stacks/site/status.json")
SITE = pathlib.Path("/opt/stacks/site")
BASE = "http://127.0.0.1:3020"
MC_HOST = "192.168.1.213"
MC_PORT = 25565

NAME_MAP = {
    "home.dobasmp.net": "Homepage",
    "adguard.dobasmp.net": "AdGuard",
    "paperless.dobasmp.net": "Paperless",
    "wazuh.dobasmp.net": "Wazuh",
    "cloud.dobasmp.net": "Nextcloud",
    "25565": "Fabric SMP",
}


def get(url):
    with urllib.request.urlopen(url, timeout=10) as r:
        return json.loads(r.read().decode())


def read_json(path):
    try:
        data = json.loads(path.read_text())
        return data if isinstance(data, dict) else None
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def host_uptime():
    try:
        secs = float(pathlib.Path("/proc/uptime").read_text().split()[0])
        days, rem = divmod(int(secs), 86400)
        hours, rem = divmod(rem, 3600)
        minutes, _ = divmod(rem, 60)
        parts = []
        if days:
            parts.append(f"{days}d")
        if hours or days:
            parts.append(f"{hours}h")
        parts.append(f"{minutes}m")
        return " ".join(parts)
    except (OSError, ValueError, IndexError):
        return None


def cpu_percent(sample=0.15):
    try:
        def snap():
            parts = pathlib.Path("/proc/stat").read_text().splitlines()[0].split()
            nums = [int(x) for x in parts[1:8]]
            idle = nums[3] + nums[4]
            return sum(nums), idle

        t1, i1 = snap()
        time.sleep(sample)
        t2, i2 = snap()
        dt, di = t2 - t1, i2 - i1
        if dt <= 0:
            return None
        return round(100 * (1 - di / dt), 1)
    except (OSError, ValueError, IndexError):
        return None


def mem_stats():
    try:
        info = {}
        for line in pathlib.Path("/proc/meminfo").read_text().splitlines():
            if ":" not in line:
                continue
            key, val = line.split(":", 1)
            info[key] = int(val.strip().split()[0])
        total_kb = info["MemTotal"]
        avail_kb = info.get("MemAvailable", info.get("MemFree", 0))
        used_kb = total_kb - avail_kb
        return {
            "memPct": round(100 * used_kb / total_kb, 1),
            "memUsedGiB": round(used_kb / 1024 / 1024, 1),
            "memTotalGiB": round(total_kb / 1024 / 1024, 1),
        }
    except (OSError, ValueError, KeyError, ZeroDivisionError):
        return {}


def disk_stats():
    try:
        usage = shutil.disk_usage("/")
        return {
            "diskPct": round(100 * usage.used / usage.total, 1),
            "diskUsedGiB": round(usage.used / (1024**3), 1),
            "diskTotalGiB": round(usage.total / (1024**3), 1),
        }
    except OSError:
        return {}


def host_resources():
    data = {"source": "host /proc (Maintenant for service probes)"}
    cpu = cpu_percent()
    if cpu is not None:
        data["cpuPct"] = cpu
    data.update(mem_stats())
    data.update(disk_stats())
    return data or None


def mc_players(host=MC_HOST, port=MC_PORT, timeout=5):
    def write_varint(value):
        out = b""
        while True:
            temp = value & 0x7F
            value >>= 7
            if value:
                temp |= 0x80
            out += struct.pack("B", temp)
            if not value:
                break
        return out

    def read_varint(sock):
        num, shift = 0, 0
        while shift <= 35:
            chunk = sock.recv(1)
            if not chunk:
                raise OSError("eof")
            val = chunk[0]
            num |= (val & 0x7F) << shift
            if not (val & 0x80):
                return num
            shift += 7
        raise ValueError("varint too long")

    def write_string(text):
        encoded = text.encode("utf-8")
        return write_varint(len(encoded)) + encoded

    def packet(packet_id, data=b""):
        body = write_varint(packet_id) + data
        return write_varint(len(body)) + body

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        sock.connect((host, port))
        handshake = packet(
            0,
            write_varint(767) + write_string(host) + struct.pack(">H", port) + write_varint(1),
        )
        sock.sendall(handshake)
        sock.sendall(packet(0))
        read_varint(sock)
        read_varint(sock)
        payload_len = read_varint(sock)
        payload = b""
        while len(payload) < payload_len:
            chunk = sock.recv(min(4096, payload_len - len(payload)))
            if not chunk:
                break
            payload += chunk
        sock.close()
        if not payload:
            return None
        data = json.loads(payload.decode("utf-8"))
        players = data.get("players") or {}
        return {
            "playersOnline": int(players.get("online", 0)),
            "playersMax": int(players.get("max", 0)),
        }
    except (OSError, ValueError, json.JSONDecodeError, struct.error, KeyError, TypeError):
        return None


def endpoint_name(target):
    t = target or ""
    if t.endswith(":8088") or ":8088" in t:
        return "Nextcloud"
    for key, name in NAME_MAP.items():
        if key in t:
            return name
    return t or "unknown"




def maintenant_monitors():
    data = get(f"{BASE}/api/v1/endpoints")
    monitors = []
    for i, ep in enumerate([e for e in (data.get("endpoints") or []) if e.get("active", True)]):
        target = ep.get("target") or ""
        up = (ep.get("status") or "").lower() == "up"
        entry = {
            "id": i + 1,
            "name": endpoint_name(target),
            "status": 1 if up else 0,
            "uptime24": None,
            "target": target,
            "responseMs": ep.get("last_response_time_ms"),
        }
        if "25565" in target and up:
            players = mc_players()
            if players:
                entry.update(players)
        monitors.append(entry)
    # Stable display order
    order = ["Homepage", "AdGuard", "Paperless", "Wazuh", "Nextcloud", "Fabric SMP"]
    monitors.sort(key=lambda m: order.index(m["name"]) if m["name"] in order else 99)
    return monitors


monitors = maintenant_monitors()
up = sum(1 for m in monitors if m["status"] == 1)

deploy = read_json(SITE / ".deploy.json") or {}
incident = read_json(SITE / ".incident.json") or {}

reliability = {
    "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "hostUptime": host_uptime(),
    "lastDeploy": deploy.get("deployedAt"),
    "lastIncident": incident.get("summary") if incident else None,
    "incidentAt": incident.get("occurredAt") if incident else None,
}

resources = host_resources()

payload = {
    "overall": "all systems operational" if up == len(monitors) and monitors else f"{up}/{len(monitors)} operational",
    "allUp": bool(monitors) and up == len(monitors),
    "monitors": monitors,
    "reliability": reliability,
    "source": "maintenant",
}
if resources:
    payload["hostResources"] = resources

new = json.dumps(payload, separators=(",", ":"))
old = OUT.read_text() if OUT.exists() else ""
OUT.write_text(new + "\n")
print("written", OUT, "monitors", len(monitors), "up", up)
print(
    "changed",
    hashlib.sha256(new.encode()).hexdigest() != hashlib.sha256(old.strip().encode()).hexdigest(),
)