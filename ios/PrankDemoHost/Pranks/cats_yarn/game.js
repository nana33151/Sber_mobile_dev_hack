// МОК игры «Котики и клубки» — только чтобы проверить линкер.
// Показывает, какой контракт ждёт нативная сторона:
//   window.PrankBridge = { init(config), show(payload), hide(id) } — вызывает приложение;
//   наклон приходит событием `prank:tilt` ({ x, y } в долях g) и лежит в window.PrankTilt;
//   window.postMessage({ type: "VIBRATION_EVENT" | "COMPLETED_EVENT" | "FINISH_EVENT" | "CLOSE_EVENT" }, "*").
(function () {
  'use strict';

  var canvas = document.getElementById('stage');
  var ctx = canvas.getContext('2d');
  var dpr = Math.min(window.devicePixelRatio || 1, 2);
  var W = 0, H = 0;
  var cats = [], balls = [];
  var running = false, won = false, wonAt = 0, last = 0;

  var CAT_R = 34, BALL_R = 14, GRAVITY = 900, DAMPING = 0.985, BOUNCE = 0.45;

  function post(type) { window.postMessage({ type: type }, '*'); }

  function resize() {
    W = window.innerWidth; H = window.innerHeight;
    canvas.width = W * dpr; canvas.height = H * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  // Случайная расстановка без пересечений: объекты имеют коллизию.
  function place(r, taken) {
    for (var attempt = 0; attempt < 200; attempt++) {
      var p = { x: r + Math.random() * (W - 2 * r), y: 80 + r + Math.random() * (H - 160 - 2 * r), r: r };
      var ok = taken.every(function (o) { return Math.hypot(o.x - p.x, o.y - p.y) > o.r + p.r + 12; });
      if (ok) { taken.push(p); return p; }
    }
    var fallback = { x: W / 2, y: H / 2, r: r }; taken.push(fallback); return fallback;
  }

  function level() {
    var taken = [];
    cats = []; balls = [];
    for (var i = 0; i < 3; i++) { var c = place(CAT_R, taken); c.caught = 0; cats.push(c); }
    for (var j = 0; j < 6; j++) { var b = place(BALL_R, taken); b.vx = 0; b.vy = 0; b.alive = true; balls.push(b); }
  }

  function step(dt) {
    var tilt = window.PrankTilt || { x: 0, y: 0 };
    balls.forEach(function (b) {
      if (!b.alive) { return; }
      b.vx = (b.vx + tilt.x * GRAVITY * dt) * DAMPING;
      b.vy = (b.vy + tilt.y * GRAVITY * dt) * DAMPING;
      b.x += b.vx * dt; b.y += b.vy * dt;
      // Края экрана — жёсткие границы.
      if (b.x < b.r) { b.x = b.r; b.vx = -b.vx * BOUNCE; }
      if (b.x > W - b.r) { b.x = W - b.r; b.vx = -b.vx * BOUNCE; }
      if (b.y < b.r) { b.y = b.r; b.vy = -b.vy * BOUNCE; }
      if (b.y > H - b.r) { b.y = H - b.r; b.vy = -b.vy * BOUNCE; }

      cats.forEach(function (c) {
        var d = Math.hypot(b.x - c.x, b.y - c.y);
        if (d >= b.r + c.r) { return; }
        if (c.caught < 2) {
          c.caught += 1; b.alive = false; post('VIBRATION_EVENT');
        } else {
          // Котик с двумя клубками — просто препятствие.
          var nx = (b.x - c.x) / d, ny = (b.y - c.y) / d;
          b.x = c.x + nx * (b.r + c.r); b.y = c.y + ny * (b.r + c.r);
          var dot = b.vx * nx + b.vy * ny;
          b.vx -= (1 + BOUNCE) * dot * nx; b.vy -= (1 + BOUNCE) * dot * ny;
        }
      });
    });

    if (!won && cats.every(function (c) { return c.caught === 2; })) {
      won = true; wonAt = performance.now();
      post('COMPLETED_EVENT');
    }
    if (won && performance.now() - wonAt > 2400) {
      running = false;
      post('FINISH_EVENT');
      post('CLOSE_EVENT');
    }
  }

  function draw(now) {
    ctx.clearRect(0, 0, W, H);
    var dance = won ? Math.sin((now - wonAt) / 120) * 0.15 : 0;
    cats.forEach(function (c) {
      ctx.save();
      ctx.translate(c.x, c.y);
      ctx.rotate(dance);
      ctx.fillStyle = ['#F2C094', '#F7A86B', '#E9824A'][c.caught];
      ctx.beginPath(); ctx.arc(0, 0, c.r, 0, Math.PI * 2); ctx.fill();
      ctx.beginPath(); ctx.moveTo(-c.r * 0.8, -c.r * 0.5); ctx.lineTo(-c.r * 0.5, -c.r * 1.2); ctx.lineTo(-c.r * 0.15, -c.r * 0.8); ctx.fill();
      ctx.beginPath(); ctx.moveTo(c.r * 0.8, -c.r * 0.5); ctx.lineTo(c.r * 0.5, -c.r * 1.2); ctx.lineTo(c.r * 0.15, -c.r * 0.8); ctx.fill();
      ctx.fillStyle = '#3B2A20';
      ctx.font = '600 14px -apple-system, sans-serif'; ctx.textAlign = 'center';
      ctx.fillText(c.caught + '/2', 0, 5);
      ctx.restore();
    });
    balls.forEach(function (b) {
      if (!b.alive) { return; }
      ctx.fillStyle = '#7C9CF5';
      ctx.beginPath(); ctx.arc(b.x, b.y, b.r, 0, Math.PI * 2); ctx.fill();
    });
  }

  function frame(now) {
    if (!running) { return; }
    var dt = Math.min((now - last) / 1000, 1 / 30);
    last = now;
    step(dt);
    draw(now);
    requestAnimationFrame(frame);
  }

  window.addEventListener('resize', resize);

  window.PrankBridge = {
    init: function () { resize(); return Promise.resolve(); },
    show: function () {
      level();
      running = true; won = false;
      return new Promise(function (resolve) {
        // Резолвимся после первого кадра — так требует контракт.
        requestAnimationFrame(function (now) { last = now; draw(now); resolve(); requestAnimationFrame(frame); });
      });
    },
    hide: function () { running = false; },
    on: function () {},
    getVersion: function () { return '1'; }
  };
})();
