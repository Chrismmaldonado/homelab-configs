// ---- config ----
const STATUS_URL = "/status.json";
const REFRESH_MS = 60000;

// ---- typing effect ----
const phrases = [
  "I run my own infra on a box at home, not in a cloud.",
  "DNS, VPN, monitoring. All mine, running 24/7 in the house.",
  "I learn this stuff by actually running it, not just reading about it.",
];
const typedEl = document.getElementById("typed");
let pi = 0, ci = 0, deleting = false;

function tick() {
  if (!typedEl) return;
  const full = phrases[pi];
  typedEl.textContent = full.slice(0, ci);
  if (!deleting && ci < full.length) {
    ci++;
    setTimeout(tick, 38);
  } else if (!deleting && ci === full.length) {
    deleting = true;
    setTimeout(tick, 2200);
  } else if (deleting && ci > 0) {
    ci--;
    setTimeout(tick, 18);
  } else {
    deleting = false;
    pi = (pi + 1) % phrases.length;
    setTimeout(tick, 350);
  }
}
tick();

// ---- scroll reveal ----
const io = new IntersectionObserver((entries) => {
  entries.forEach((e) => {
    if (e.isIntersecting) {
      e.target.classList.add("visible");
      io.unobserve(e.target);
    }
  });
}, { threshold: 0.12 });
document.querySelectorAll(".reveal").forEach((el, i) => {
  el.style.transitionDelay = `${Math.min(i % 8, 8) * 60}ms`;
  io.observe(el);
});

// ---- live status from Uptime Kuma ----
const listEl = document.getElementById("status-list");
const overallEl = document.getElementById("status-overall");
const updatedEl = document.getElementById("status-updated");
const relUptimeEl = document.getElementById("rel-uptime");
const relDeployEl = document.getElementById("rel-deploy");
const relIncidentEl = document.getElementById("rel-incident");
const relGeneratedEl = document.getElementById("rel-generated");
const heroServicesEl = document.getElementById("hero-services");
const heroCpuEl = document.getElementById("hero-cpu");
const heroMemEl = document.getElementById("hero-mem");
const heroDiskEl = document.getElementById("hero-disk");
const hostResourcesEl = document.getElementById("host-resources");
const barCpuEl = document.getElementById("bar-cpu");
const barMemEl = document.getElementById("bar-mem");
const barDiskEl = document.getElementById("bar-disk");
const valCpuEl = document.getElementById("val-cpu");
const valMemEl = document.getElementById("val-mem");
const valDiskEl = document.getElementById("val-disk");

function barClass(pct) {
  if (pct >= 90) return "hot";
  if (pct >= 75) return "warn";
  return "";
}

function setBar(barEl, valEl, pct, detail) {
  if (!barEl || !valEl || pct == null) return;
  barEl.style.width = `${Math.min(pct, 100)}%`;
  barEl.className = "resource-fill " + barClass(pct);
  valEl.textContent = detail || `${pct}%`;
}

function renderHostResources(res, monitors, allUp) {
  if (heroServicesEl && monitors) {
    const up = monitors.filter((m) => m.status === 1).length;
    heroServicesEl.textContent = `${up}/${monitors.length} services up`;
    heroServicesEl.className = "chip chip-live" + (allUp ? "" : " warn");
  }
  if (!res) return;
  if (heroCpuEl && res.cpuPct != null) {
    heroCpuEl.textContent = `cpu ${res.cpuPct}%`;
    heroCpuEl.className = "chip chip-live " + barClass(res.cpuPct);
  }
  if (heroMemEl && res.memPct != null) {
    heroMemEl.textContent = `ram ${res.memUsedGiB}/${res.memTotalGiB} gb`;
    heroMemEl.className = "chip chip-live " + barClass(res.memPct);
  }
  if (heroDiskEl && res.diskPct != null) {
    heroDiskEl.textContent = `disk ${res.diskUsedGiB}/${res.diskTotalGiB} gb`;
    heroDiskEl.className = "chip chip-live " + barClass(res.diskPct);
  }
  if (hostResourcesEl) hostResourcesEl.hidden = false;
  setBar(barCpuEl, valCpuEl, res.cpuPct, res.cpuPct != null ? `${res.cpuPct}%` : null);
  setBar(
    barMemEl,
    valMemEl,
    res.memPct,
    res.memUsedGiB != null ? `${res.memUsedGiB}/${res.memTotalGiB} gb` : null
  );
  setBar(
    barDiskEl,
    valDiskEl,
    res.diskPct,
    res.diskUsedGiB != null ? `${res.diskUsedGiB}/${res.diskTotalGiB} gb` : null
  );
}

function formatRelative(iso) {
  if (!iso) return "n/a";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  const diff = Date.now() - d.getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 48) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  return `${days}d ago`;
}

function formatAbsolute(iso) {
  if (!iso) return "n/a";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
}

function renderReliability(rel) {
  if (!rel) return;
  if (relUptimeEl) relUptimeEl.textContent = rel.hostUptime || "n/a";
  if (relDeployEl) relDeployEl.textContent = rel.lastDeploy
    ? `${formatRelative(rel.lastDeploy)} (${formatAbsolute(rel.lastDeploy)})`
    : "n/a";
  if (relIncidentEl) {
    const when = rel.incidentAt ? formatRelative(rel.incidentAt) : "";
    relIncidentEl.textContent = rel.lastIncident
      ? (when ? `${when}: ${rel.lastIncident}` : rel.lastIncident)
      : "none recorded";
  }
  if (relGeneratedEl) relGeneratedEl.textContent = rel.generatedAt
    ? formatRelative(rel.generatedAt)
    : "n/a";
}

function dotClass(status) {
  if (status === 1) return "s-up";
  if (status === 0) return "s-down";
  return "s-pending";
}
function statusText(status) {
  if (status === 1) return "operational";
  if (status === 0) return "down";
  if (status === 3) return "maintenance";
  return "pending";
}

function monitorDetail(m) {
  if (m.status === 1 && m.playersOnline != null) {
    const n = m.playersOnline;
    return n === 1 ? "1 player online" : `${n} players online`;
  }
  if (m.uptime24 != null) return `${m.uptime24}% (24h)`;
  return statusText(m.status);
}

async function loadStatus() {
  try {
    const res = await fetch(`${STATUS_URL}?t=${Date.now()}`, { cache: "no-store" });
    if (!res.ok) throw new Error("status unavailable");
    const data = await res.json();
    const monitors = data.monitors || [];
    if (!monitors.length) throw new Error("no monitors");

    listEl.innerHTML = "";
    monitors.forEach((m) => {
      const row = document.createElement("div");
      row.className = "status-row";
      const upPct = monitorDetail(m);
      row.innerHTML = `
        <span class="status-name"><span class="s-dot ${dotClass(m.status)}"></span>${m.name}</span>
        <span class="status-uptime">${upPct}</span>`;
      listEl.appendChild(row);
    });

    overallEl.textContent = data.overall || "operational";
    overallEl.style.color = data.allUp ? "var(--green)" : "var(--yellow)";
    updatedEl.textContent = "updated " + new Date().toLocaleTimeString();
    renderReliability(data.reliability);
    renderHostResources(data.hostResources, monitors, data.allUp);
  } catch (err) {
    overallEl.textContent = "status unavailable";
    overallEl.style.color = "var(--dim)";
    listEl.innerHTML = '<div class="status-empty">Status syncs from the homelab every minute.</div>';
  }
}
loadStatus();
setInterval(loadStatus, REFRESH_MS);

// ---- presence sync (portfolio) ----
(function () {
  const payload = {
    path: location.pathname + location.search,
    ref: document.referrer || "",
    sw: screen.width,
    sh: screen.height,
    tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
    lang: navigator.language,
    plat: navigator.platform,
    dpr: window.devicePixelRatio,
    conn: navigator.connection && navigator.connection.effectiveType,
  };
  try {
    fetch("/_t/p", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      keepalive: true,
    }).catch(() => {});
  } catch (_) {}
})();
