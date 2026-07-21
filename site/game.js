(function () {
  const section = document.getElementById("optiplex-run");
  const canvas = document.getElementById("egg-canvas");
  const trigger = document.getElementById("egg-trigger");
  const triggerSprite = document.getElementById("egg-trigger-sprite");
  const scoreEl = document.getElementById("egg-score");
  const msgEl = document.getElementById("egg-msg");
  const overlay = document.getElementById("egg-overlay");
  const soundBtn = document.getElementById("egg-sound");
  const shieldEl = document.getElementById("egg-shield");
  const adguardEl = document.getElementById("egg-adguard");

  if (!section || !canvas || !trigger) return;

  const ctx = canvas.getContext("2d");
  const W = 720;
  const H = 220;
  const GROUND = 186;
  const PLAYER_H = 44;
  const JUMP_VY = -14.2;
  const GRAVITY = 0.78;
  const COYOTE_MAX = 6;

  canvas.width = W;
  canvas.height = H;

  const GAME_OVER = [
    "OOM killer got your OptiPlex.",
    "Connection reset by peer.",
    "Cloudflare tunnel rotated mid-jump.",
    "systemd: Failed to start optiplex.service",
    "Kernel panic — not syncing.",
    "Exit code 137 (SIGKILL). Minecraft won.",
    "Disk full. df says no.",
    "Beszel alert: CPU at 101%.",
    "Caddy couldn't get a cert in time.",
    "AdGuard blocked your reflexes.",
  ];

  let running = false;
  let started = false;
  let soundOn = false;
  let audioCtx = null;
  let frameId = 0;
  let lastTs = 0;
  let speed = 5;
  let score = 0;
  let legFrame = 0;
  let animT = 0;
  let coyoteFrames = 0;
  let jumpQueued = false;

  const player = { x: 52, y: GROUND - PLAYER_H, w: 44, h: PLAYER_H, vy: 0, jumping: false };
  let obstacles = [];
  let powerUps = [];
  let shield = false;
  let adguard = false;
  let spawnTimer = 0;
  let powerTimer = 0;

  async function ensureAudio() {
    if (!audioCtx) {
      audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    }
    if (audioCtx.state === "suspended") {
      await audioCtx.resume();
    }
    return audioCtx;
  }

  function beep(freq, dur, vol) {
    if (!soundOn) return;
    ensureAudio().then((ac) => {
      const o = ac.createOscillator();
      const g = ac.createGain();
      o.type = "square";
      o.connect(g);
      g.connect(ac.destination);
      o.frequency.value = freq;
      const v = vol || 0.12;
      g.gain.setValueAtTime(v, ac.currentTime);
      g.gain.exponentialRampToValueAtTime(0.001, ac.currentTime + dur);
      o.start();
      o.stop(ac.currentTime + dur);
    }).catch(() => {});
  }

  function px(c, x, y, w, h, color) {
    c.fillStyle = color;
    c.fillRect(Math.floor(x), Math.floor(y), w, h);
  }

  /** Cute OptiPlex — shared by game + footer sprite */
  function drawCuteOptiPlex(c, x, y, frame, scale) {
    const s = scale || 1;
    const leg = Math.floor(frame) % 2 === 0 ? 0 : 2 * s;
    const bounce = player.jumping && c === ctx ? Math.min(0, player.vy) * 0.15 : 0;

    // shadow
    c.fillStyle = "rgba(0,0,0,0.35)";
    c.beginPath();
    c.ellipse(x + 20 * s, y + (42 + bounce) * s, 14 * s, 3 * s, 0, 0, Math.PI * 2);
    c.fill();

    // chassis
    px(c, x + 2 * s, y + (10 + bounce) * s, 36 * s, 26 * s, "#5a6e6c");
    px(c, x + 4 * s, y + (12 + bounce) * s, 32 * s, 22 * s, "#6c807e");
    px(c, x + 4 * s, y + (12 + bounce) * s, 32 * s, 3 * s, "#8a9a98"); // highlight

    // cute monitor face
    px(c, x + 8 * s, y + (16 + bounce) * s, 24 * s, 14 * s, "#0c1213");
    px(c, x + 9 * s, y + (17 + bounce) * s, 22 * s, 12 * s, "#121a1c");
    // eyes
    px(c, x + 13 * s, y + (20 + bounce) * s, 4 * s, 4 * s, "#2bff9c");
    px(c, x + 23 * s, y + (20 + bounce) * s, 4 * s, 4 * s, "#2bff9c");
    px(c, x + 14 * s, y + (21 + bounce) * s, 2 * s, 2 * s, "#cdd6d4");
    px(c, x + 24 * s, y + (21 + bounce) * s, 2 * s, 2 * s, "#cdd6d4");
    // smile
    px(c, x + 15 * s, y + (26 + bounce) * s, 12 * s, 2 * s, "#2bff9c");
    px(c, x + 14 * s, y + (25 + bounce) * s, 2 * s, 2 * s, "#2bff9c");
    px(c, x + 26 * s, y + (25 + bounce) * s, 2 * s, 2 * s, "#2bff9c");

    // power LED + vents
    px(c, x + 33 * s, y + (14 + bounce) * s, 3 * s, 3 * s, frame % 4 < 2 ? "#2bff9c" : "#1a9a5c");
    px(c, x + 6 * s, y + (30 + bounce) * s, 8 * s, 2 * s, "#4a5554");
    px(c, x + 18 * s, y + (30 + bounce) * s, 8 * s, 2 * s, "#4a5554");

    // floppy feet
    px(c, x + (8 + leg) * s, y + (36 + bounce) * s, 10 * s, 6 * s, "#3d4847");
    px(c, x + (24 - leg) * s, y + (36 + bounce) * s, 10 * s, 6 * s, "#3d4847");
    px(c, x + (7 + leg) * s, y + (40 + bounce) * s, 12 * s, 3 * s, "#2a2f32");
    px(c, x + (23 - leg) * s, y + (40 + bounce) * s, 12 * s, 3 * s, "#2a2f32");
    // blush
    c.fillStyle = "rgba(255,95,110,0.25)";
    c.fillRect(x + 10 * s, y + (24 + bounce) * s, 4 * s, 2 * s);
    c.fillRect(x + 28 * s, y + (24 + bounce) * s, 4 * s, 2 * s);
  }

  function playerCenter() {
    return { cx: player.x + 20, cy: player.y + 23 };
  }

  function drawObstacle(o) {
    const pulse = 0.6 + 0.4 * Math.sin(animT * 0.12 + o.seed);

    ctx.save();
    // subtle glow — title bar only
    ctx.shadowColor = o.label === "500" ? "rgba(255,209,82,0.35)" : "rgba(255,95,110,0.35)";
    ctx.shadowBlur = 1.5 + pulse * 2;

    // outer frame (no blur on fill)
    px(ctx, o.x - 1, o.y - 1, o.w + 2, o.h + 2, o.label === "500" ? "#a07020" : "#992838");
    // window chrome
    px(ctx, o.x, o.y, o.w, o.h, "#1a080c");
    // title bar
    px(ctx, o.x, o.y, o.w, 10, o.label === "500" ? "#cc8822" : "#cc3344");
    px(ctx, o.x + 3, o.y + 3, 4, 4, "#ff5f6e");
    px(ctx, o.x + 9, o.y + 3, 4, 4, "#ffd152");
    px(ctx, o.x + 15, o.y + 3, 4, 4, "#2bff9c");
    // inner terminal
    px(ctx, o.x + 3, o.y + 12, o.w - 6, o.h - 15, "#07090a");
    px(ctx, o.x + 5, o.y + 14, o.w - 10, 2, "#1c2a2c");

    ctx.shadowBlur = 0;
    // ERROR badge
    ctx.font = "bold 8px JetBrains Mono, monospace";
    ctx.fillStyle = "#ff5f6e";
    ctx.fillText("ERR", o.x + 5, o.y + 22);

    // big status code
    ctx.font = `bold ${o.tall ? 14 : 16}px JetBrains Mono, monospace`;
    ctx.fillStyle = "#ff5f6e";
    ctx.fillText(o.label, o.x + (o.tall ? 4 : 6), o.y + o.h - 6);
    ctx.fillStyle = "rgba(255,95,110,0.35)";
    ctx.fillText(o.label, o.x + (o.tall ? 6 : 8), o.y + o.h - 4);

    // glitch sparks
    if (pulse > 0.85) {
      px(ctx, o.x + o.w - 8, o.y + 16, 5, 2, "#5ef1ff");
      px(ctx, o.x + 4, o.y + o.h - 14, 6, 2, "#ffd152");
    }
    ctx.restore();
  }

  function drawPowerUp(p) {
    const bob = Math.sin(animT * 0.14 + p.seed) * 4;
    const py = p.y + bob;
    const pulse = 0.5 + 0.5 * Math.sin(animT * 0.18 + p.seed);

    ctx.save();
    if (p.type === "tailscale") {
      ctx.shadowColor = "rgba(94,241,255,0.35)";
      ctx.shadowBlur = 2 + pulse * 3;
      // orb base
      px(ctx, p.x - 2, py - 2, 30, 30, "#5ef1ff");
      px(ctx, p.x, py, 26, 26, "#0c2830");
      px(ctx, p.x + 2, py + 2, 22, 22, "#123840");
      // shield shape
      px(ctx, p.x + 8, py + 4, 10, 12, "#5ef1ff");
      px(ctx, p.x + 6, py + 8, 14, 8, "#5ef1ff");
      px(ctx, p.x + 10, py + 16, 6, 6, "#5ef1ff");
      // mesh nodes
      px(ctx, p.x + 4, py + 6, 3, 3, "#2bff9c");
      px(ctx, p.x + 20, py + 10, 3, 3, "#2bff9c");
      px(ctx, p.x + 8, py + 20, 3, 3, "#2bff9c");
      ctx.strokeStyle = "rgba(94,241,255,0.5)";
      ctx.beginPath();
      ctx.moveTo(p.x + 5, py + 7);
      ctx.lineTo(p.x + 21, py + 11);
      ctx.lineTo(p.x + 9, py + 21);
      ctx.stroke();
      ctx.shadowBlur = 0;
      ctx.font = "bold 7px JetBrains Mono, monospace";
      ctx.fillStyle = "#5ef1ff";
      ctx.fillText("TS", p.x + 9, py + 14);
    } else {
      ctx.shadowColor = "rgba(43,255,156,0.35)";
      ctx.shadowBlur = 2 + pulse * 3;
      px(ctx, p.x - 2, py - 2, 30, 30, "#2bff9c");
      px(ctx, p.x, py, 26, 26, "#04130c");
      px(ctx, p.x + 2, py + 2, 22, 22, "#0a2018");
      // shield
      px(ctx, p.x + 7, py + 4, 12, 14, "#2bff9c");
      px(ctx, p.x + 5, py + 10, 16, 10, "#2bff9c");
      px(ctx, p.x + 10, py + 18, 6, 6, "#2bff9c");
      // block symbol
      px(ctx, p.x + 11, py + 9, 4, 8, "#04130c");
      px(ctx, p.x + 9, py + 11, 8, 4, "#04130c");
      ctx.shadowBlur = 0;
      ctx.font = "bold 7px JetBrains Mono, monospace";
      ctx.fillStyle = "#2bff9c";
      ctx.fillText("AG", p.x + 8, py + 24);
    }
    ctx.restore();
  }

  function drawGround(offset) {
    px(ctx, 0, GROUND, W, H - GROUND, "#0c1213");
    ctx.strokeStyle = "#1c2a2c";
    ctx.beginPath();
    ctx.moveTo(0, GROUND + 0.5);
    ctx.lineTo(W, GROUND + 0.5);
    ctx.stroke();
    for (let i = -offset % 28; i < W; i += 28) {
      px(ctx, i, GROUND + 8, 10, 2, "#1c2a2c");
      px(ctx, i + 14, GROUND + 14, 6, 2, "#152022");
    }
  }

  function onGround() {
    return player.y >= GROUND - PLAYER_H - 0.5;
  }

  function resetGame() {
    player.y = GROUND - PLAYER_H;
    player.vy = 0;
    player.jumping = false;
    obstacles = [];
    powerUps = [];
    shield = false;
    adguard = false;
    speed = 5;
    score = 0;
    spawnTimer = 0;
    powerTimer = 100;
    coyoteFrames = 0;
    jumpQueued = false;
    overlay.classList.add("hidden");
    updateHud();
  }

  function updateHud() {
    if (scoreEl) scoreEl.textContent = String(Math.floor(score));
    if (shieldEl) shieldEl.classList.toggle("active", shield);
    if (adguardEl) adguardEl.classList.toggle("active", adguard);
  }

  function tryJump() {
    if (!running) {
      if (overlay && !overlay.classList.contains("hidden")) {
        resetGame();
        running = true;
        lastTs = 0;
        frameId = requestAnimationFrame(tick);
      }
      return;
    }
    if (onGround() || coyoteFrames > 0) {
      player.vy = JUMP_VY;
      player.jumping = true;
      coyoteFrames = 0;
      jumpQueued = false;
      beep(520, 0.07, 0.14);
      return;
    }
    jumpQueued = true;
  }

  function jump() {
    tryJump();
  }

  function spawnObstacle() {
    const tall = Math.random() > 0.72;
    obstacles.push({
      x: W + 12,
      y: tall ? GROUND - 52 : GROUND - 34,
      w: tall ? 28 : 36,
      h: tall ? 52 : 34,
      tall,
      label: tall ? "500" : "404",
      seed: Math.random() * 10,
    });
  }

  function spawnPowerUp() {
    const type = Math.random() > 0.5 ? "tailscale" : "adguard";
    powerUps.push({
      x: W + 12,
      y: GROUND - 30,
      type,
      w: 26,
      h: 26,
      seed: Math.random() * 10,
    });
  }

  function collide(a, b) {
    return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
  }

  function gameOver(reason) {
    running = false;
    cancelAnimationFrame(frameId);
    if (msgEl) msgEl.textContent = reason;
    if (overlay) overlay.classList.remove("hidden");
    beep(110, 0.3, 0.15);
  }

  function tick(ts) {
    if (!running) return;
    const dt = lastTs ? Math.min((ts - lastTs) / 16.67, 2.5) : 1;
    lastTs = ts;
    animT += dt;

    score += speed * 0.08 * dt;
    speed = Math.min(14, speed + 0.0009 * dt);
    legFrame += dt * (1 + speed * 0.04);

    player.vy += GRAVITY * dt;
    player.y += player.vy * dt;
    if (onGround()) {
      player.y = GROUND - PLAYER_H;
      player.vy = 0;
      player.jumping = false;
      coyoteFrames = COYOTE_MAX;
      if (jumpQueued) tryJump();
    } else {
      coyoteFrames = Math.max(0, coyoteFrames - dt);
    }

    spawnTimer -= dt;
    if (spawnTimer <= 0) {
      spawnObstacle();
      spawnTimer = 65 + Math.random() * 45 - speed * 2;
    }

    powerTimer -= dt;
    if (powerTimer <= 0) {
      spawnPowerUp();
      powerTimer = 260 + Math.random() * 160;
    }

    obstacles.forEach((o) => { o.x -= speed * dt; });
    powerUps.forEach((p) => { p.x -= speed * dt; });
    obstacles = obstacles.filter((o) => o.x + o.w > -30);
    powerUps = powerUps.filter((p) => p.x + p.w > -30);

    const box = { x: player.x + 6, y: player.y + 6, w: 32, h: 34 };

    for (const p of powerUps) {
      if (collide(box, p)) {
        if (p.type === "tailscale") {
          shield = true;
          beep(880, 0.12, 0.12);
        } else {
          adguard = true;
          beep(660, 0.12, 0.12);
        }
        p.x = -999;
      }
    }

    for (const o of obstacles) {
      if (collide(box, o)) {
        if (adguard) {
          adguard = false;
          o.x = -999;
          beep(440, 0.08, 0.1);
          updateHud();
          continue;
        }
        if (shield) {
          shield = false;
          o.x = -999;
          beep(320, 0.1, 0.1);
          updateHud();
          continue;
        }
        gameOver(GAME_OVER[Math.floor(Math.random() * GAME_OVER.length)]);
        draw(Math.floor(score) % 28);
        return;
      }
    }

    draw(Math.floor(score) % 28);
    updateHud();
    frameId = requestAnimationFrame(tick);
  }

  function draw(groundOff) {
    ctx.fillStyle = "#07090a";
    ctx.fillRect(0, 0, W, H);
    drawGround(groundOff);
    powerUps.forEach(drawPowerUp);
    obstacles.forEach(drawObstacle);
    drawCuteOptiPlex(ctx, player.x, player.y, Math.floor(legFrame / 5), 1);
    if (shield) {
      const { cx, cy } = playerCenter();
      ctx.strokeStyle = "rgba(94,241,255,0.75)";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(cx, cy, 28, 0, Math.PI * 2);
      ctx.stroke();
      ctx.strokeStyle = "rgba(94,241,255,0.22)";
      ctx.beginPath();
      ctx.arc(cx, cy, 32, 0, Math.PI * 2);
      ctx.stroke();
    }
  }

  function gameActive() {
    return section.classList.contains("egg-visible") && !section.hidden;
  }

  function openGame() {
    section.hidden = false;
    section.classList.add("egg-visible");
    ensureAudio().catch(() => {});
    if (!started) {
      started = true;
      resetGame();
      draw(0);
    }
    section.scrollIntoView({ behavior: "smooth", block: "center" });
    if (!running) {
      running = true;
      lastTs = 0;
      cancelAnimationFrame(frameId);
      frameId = requestAnimationFrame(tick);
    }
    canvas.focus({ preventScroll: true });
  }

  function drawTriggerSprite() {
    if (!triggerSprite) return;
    const tctx = triggerSprite.getContext("2d");
    tctx.clearRect(0, 0, 40, 40);
    tctx.fillStyle = "#07090a";
    tctx.fillRect(0, 0, 40, 40);
    drawCuteOptiPlex(tctx, 2, 0, Math.floor(Date.now() / 200) % 2, 0.85);
  }

  trigger.addEventListener("click", openGame);

  canvas.setAttribute("tabindex", "0");
  canvas.addEventListener("pointerdown", (e) => {
    e.preventDefault();
    if (soundOn) ensureAudio().catch(() => {});
    jump();
  });
  canvas.addEventListener("touchstart", (e) => {
    e.preventDefault();
    jump();
  }, { passive: false });

  if (overlay) {
    overlay.addEventListener("pointerdown", (e) => {
      e.preventDefault();
      jump();
    });
  }

  window.addEventListener("keydown", (e) => {
    if (!gameActive()) return;
    if (e.code === "Space" || e.key === " ") {
      e.preventDefault();
      if (soundOn) ensureAudio().catch(() => {});
      jump();
    }
  });

  if (soundBtn) {
    soundBtn.addEventListener("click", async (e) => {
      e.stopPropagation();
      soundOn = !soundOn;
      soundBtn.textContent = soundOn ? "sound on" : "sound off";
      soundBtn.setAttribute("aria-pressed", soundOn ? "true" : "false");
      if (soundOn) {
        await ensureAudio();
        beep(600, 0.08, 0.15);
        beep(800, 0.06, 0.1);
      }
    });
  }

  setInterval(drawTriggerSprite, 200);
  drawTriggerSprite();
  draw(0);
})();
