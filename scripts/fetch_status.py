#!/usr/bin/env python3
"""Pull Uptime Kuma public status and host metrics; write status.json for the static site."""
import json
import hashlib
import shutil
import time
import urllib.request
import pathlib
from datetime import datetime, timezone

OUT = pathlib.Path("/opt/stacks/site/status.json")
SITE = pathlib.Path("/opt/stacks/site")
SLUG = "homelab"
BASE = "http://127.0.0.1:3002"


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
    data = {"source": "host /proc (same host Beszel monitors)"}
    cpu = cpu_percent()
    if cpu is not None:
        data["cpuPct"] = cpu
    data.update(mem_stats())
    data.update(disk_stats())
    return data or None


cfg = get(f"{BASE}/api/status-page/{SLUG}")
hb = get(f"{BASE}/api/status-page/heartbeat/{SLUG}")

monitors = []
for g in cfg.get("publicGroupList", []):
    for m in g.get("monitorList", []):
        beats = (hb.get("heartbeatList") or {}).get(str(m["id"])) or hb.get("heartbeatList", {}).get(m["id"]) or []
        last = beats[-1] if beats else None
        status = last["status"] if last else 2
        uptime = None
        for key, val in (hb.get("uptimeList") or {}).items():
            if key.startswith(f"{m['id']}_"):
                uptime = round(val * 100, 2)
                break
        monitors.append({"id": m["id"], "name": m["name"], "status": status, "uptime24": uptime})

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
    "overall": "all systems operational" if up == len(monitors) else f"{up}/{len(monitors)} operational",
    "allUp": up == len(monitors),
    "monitors": monitors,
    "reliability": reliability,
}
if resources:
    payload["hostResources"] = resources

new = json.dumps(payload, separators=(",", ":"))
old = OUT.read_text() if OUT.exists() else ""
OUT.write_text(new + "\n")
print("written", OUT, "monitors", len(monitors), "cpu", resources.get("cpuPct") if resources else None)
print("changed", hashlib.sha256(new.encode()).hexdigest() != hashlib.sha256(old.strip().encode()).hexdigest())
