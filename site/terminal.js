(function () {
  const DEFAULT_FALLBACKS = ["wss://terminal.christopher-lab.pages.dev"];
  const mount = document.getElementById("terminal-mount");
  const statusEl = document.getElementById("terminal-status");
  if (!mount) return;

  let term, fitAddon, ws, connected = false, line = "", booted = false, connId = 0;

  function setStatus(text, ok) {
    if (!statusEl) return;
    statusEl.textContent = text;
    statusEl.style.color = ok ? "var(--green)" : "var(--dim)";
  }

  function scrollBottom() {
    if (term) term.scrollToBottom();
  }

  function refit() {
    if (!fitAddon || !term) return;
    try {
      fitAddon.fit();
      scrollBottom();
    } catch (_) {}
  }

  function loadScript(src) {
    return new Promise((resolve, reject) => {
      if (document.querySelector(`script[src="${src}"]`)) return resolve();
      const s = document.createElement("script");
      s.src = src;
      s.onload = resolve;
      s.onerror = reject;
      document.head.appendChild(s);
    });
  }

  function uniq(arr) {
    const out = [];
    const seen = new Set();
    for (const u of arr) {
      if (!u || seen.has(u)) continue;
      seen.add(u);
      out.push(u);
    }
    return out;
  }

  async function wsEndpoints() {
    const urls = [];

    try {
      const r = await fetch("/api/ws", { cache: "no-store" });
      if (r.ok) {
        const j = await r.json();
        if (j.url) urls.push(j.url);
        if (Array.isArray(j.fallbacks)) urls.push(...j.fallbacks);
      }
    } catch (_) {}

    try {
      const r = await fetch("/ws-config.json", { cache: "no-store" });
      if (r.ok) {
        const j = await r.json();
        if (j.url) urls.push(j.url);
        if (Array.isArray(j.fallbacks)) urls.push(...j.fallbacks);
      }
    } catch (_) {}

    urls.push(...DEFAULT_FALLBACKS);
    return uniq(urls);
  }

  function tryConnect(url, timeoutMs) {
    return new Promise((resolve) => {
      let done = false;
      const finish = (ok) => {
        if (done) return;
        done = true;
        try { sock.close(); } catch (_) {}
        resolve(ok ? url : null);
      };
      const sock = new WebSocket(url);
      const timer = setTimeout(() => finish(false), timeoutMs);
      sock.onopen = () => { clearTimeout(timer); finish(true); };
      sock.onerror = () => { clearTimeout(timer); finish(false); };
      sock.onclose = () => { clearTimeout(timer); finish(false); };
    });
  }

  async function resolveLiveUrl() {
    const endpoints = await wsEndpoints();
    for (const url of endpoints) {
      setStatus("probing tunnel…", false);
      const ok = await tryConnect(url, 6000);
      if (ok) return ok;
    }
    return endpoints[0] || DEFAULT_FALLBACKS[0];
  }

  async function boot() {
    if (booted) return;
    booted = true;
    try {
      await loadScript("https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.min.js");
      await loadScript("https://cdn.jsdelivr.net/npm/xterm-addon-fit@0.8.0/lib/xterm-addon-fit.min.js");
    } catch {
      setStatus("failed to load terminal", false);
      return;
    }

    term = new Terminal({
      theme: {
        background: "#07090a",
        foreground: "#cdd6d4",
        cursor: "#2bff9c",
        selectionBackground: "rgba(43,255,156,0.25)",
      },
      fontFamily: "'JetBrains Mono', ui-monospace, Menlo, monospace",
      fontSize: 13,
      cursorBlink: true,
      scrollback: 2000,
      convertEol: true,
      scrollOnUserInput: true,
    });
    fitAddon = new FitAddon.FitAddon();
    term.loadAddon(fitAddon);
    term.open(mount);
    requestAnimationFrame(() => {
      refit();
      requestAnimationFrame(refit);
    });

    await connectWithRetry();

    term.onData((data) => {
      if (!connected || !ws || ws.readyState !== WebSocket.OPEN) return;

      if (data === "\r") {
        term.write("\r\n");
        ws.send(line);
        line = "";
        scrollBottom();
        return;
      }
      if (data === "\u007F") {
        if (line.length) {
          line = line.slice(0, -1);
          term.write("\b \b");
        }
        scrollBottom();
        return;
      }
      if (data === "\u0003") return;
      if (data < " " && data !== "\t") return;

      line += data;
      term.write(data);
      scrollBottom();
    });

    term.onLineFeed(() => scrollBottom());

    const ro = new ResizeObserver(() => refit());
    ro.observe(mount);
    window.addEventListener("resize", refit);
  }

  async function connectWithRetry() {
    const maxAttempts = 12;
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      const url = await resolveLiveUrl();
      setStatus(`connecting (${attempt}/${maxAttempts})…`, false);
      const ok = await connect(url);
      if (ok) return;
      const wait = Math.min(1500 * attempt, 8000);
      setStatus(`tunnel recovering… retry in ${Math.round(wait / 1000)}s`, false);
      await new Promise((r) => setTimeout(r, wait));
    }
    setStatus("disconnected", false);
    if (term) {
      term.write("\r\n\x1b[90m[connection closed — tunnel is reconnecting; refresh in a minute]\x1b[0m\r\n");
      scrollBottom();
    }
  }

  function connect(url) {
    return new Promise((resolve) => {
      const id = ++connId;
      if (ws) {
        ws.onclose = null;
        ws.onerror = null;
        ws.onmessage = null;
        ws.onopen = null;
        try { ws.close(); } catch (_) {}
      }
      ws = new WebSocket(url);
      let settled = false;

      const finish = (ok) => {
        if (settled || id !== connId) return;
        settled = true;
        resolve(ok);
      };

      ws.onopen = () => {
        if (id !== connId) return;
        connected = true;
        setStatus("live · read-only", true);
        refit();
        finish(true);
      };

      ws.onmessage = (ev) => {
        if (id !== connId) return;
        const text = ev.data;
        if (text.includes("\x1b[2J")) {
          term.clear();
          scrollBottom();
          return;
        }
        term.write(text);
        scrollBottom();
      };

      ws.onclose = () => {
        if (id !== connId) return;
        connected = false;
        setStatus("disconnected", false);
        finish(false);
      };

      ws.onerror = () => {
        if (id !== connId) return;
        setStatus("connection error", false);
        finish(false);
      };
    });
  }

  const io = new IntersectionObserver((entries) => {
    entries.forEach((e) => {
      if (e.isIntersecting) {
        boot().then(refit);
      }
    });
  }, { threshold: 0.15 });
  io.observe(mount.closest("section") || mount);
})();
