// «Котики и клубки» поверх приложения: физика здесь, картинки — общий рендер ../src/cat-animation.js.
//
// Контракт с нативным линкером:
//   window.PrankBridge = { init(config), show(payload), hide(id) } — вызывает приложение;
//   наклон приходит событием `prank:tilt` ({ x, y } в долях g) и лежит в window.PrankTilt;
//   window.postMessage({ type: "VIBRATION_EVENT" | "COMPLETED_EVENT" | "FINISH_EVENT" | "CLOSE_EVENT" }, "*").
import { installCatAnimationBridge } from "../src/bridge.js";
import { computeLayout } from "../src/animation-core.js";

const CAT_COUNT = 3;
const BALLS_PER_CAT = 2;
const GRAVITY = 900; // px/с² при полном наклоне
const DAMPING = 0.985;
const BOUNCE = 0.45;
const DANCE_MS = 1600;

const canvas = document.querySelector("#cat-animation-overlay");
const animation = installCatAnimationBridge(canvas);

let width = window.innerWidth;
let height = window.innerHeight;
let cats = [];
let balls = [];
let running = false;
let won = false;
let lastTime = 0;
let frameId = null;

function post(type) {
  window.postMessage({ type }, "*");
}

function radii() {
  const layout = computeLayout(width, height, CAT_COUNT);
  return {
    cat: layout.catHeight * 0.36, // тело котика без ушей
    ball: layout.yarnHeight * 0.42,
    // Половина картинки: спрайт целиком остаётся на экране.
    catHalf: layout.catHeight / 2,
    ballHalf: layout.yarnHeight / 2
  };
}

// Случайная расстановка без пересечений — у объектов есть коллизия.
// `half` — половина размера картинки: объект целиком внутри экрана, с отступами сверху и снизу.
function place(radius, half, taken, marginTop, marginBottom) {
  for (let attempt = 0; attempt < 300; attempt += 1) {
    const point = {
      x: half + Math.random() * (width - 2 * half),
      y: marginTop + half + Math.random() * Math.max(1, height - marginTop - marginBottom - 2 * half),
      r: radius
    };
    const free = taken.every((other) => Math.hypot(other.x - point.x, other.y - point.y) > other.r + point.r + 16);
    if (free) {
      taken.push(point);
      return point;
    }
  }
  const fallback = { x: width / 2, y: height / 2, r: radius };
  taken.push(fallback);
  return fallback;
}

function newLevel() {
  width = window.innerWidth;
  height = window.innerHeight;
  const r = radii();
  const taken = [];
  cats = Array.from({ length: CAT_COUNT }, (_, index) => ({
    ...place(r.cat, r.catHalf, taken, 60, 110),
    id: `cat-${index + 1}`,
    balls: 0
  }));
  balls = Array.from({ length: CAT_COUNT * BALLS_PER_CAT }, (_, index) => ({
    ...place(r.ball, r.ballHalf, taken, 50, 60),
    id: `yarn-${index}`,
    variant: index % 8,
    vx: 0,
    vy: 0,
    rotation: 0,
    alive: true
  }));
  won = false;
}

function step(dt) {
  const tilt = window.PrankTilt || { x: 0, y: 0 };
  for (const ball of balls) {
    if (!ball.alive) continue;
    ball.vx = (ball.vx + tilt.x * GRAVITY * dt) * DAMPING;
    ball.vy = (ball.vy + tilt.y * GRAVITY * dt) * DAMPING;
    ball.x += ball.vx * dt;
    ball.y += ball.vy * dt;
    ball.rotation += (ball.vx * dt) / Math.max(ball.r, 1);

    // Края экрана — жёсткие границы.
    if (ball.x < ball.r) { ball.x = ball.r; ball.vx = -ball.vx * BOUNCE; }
    if (ball.x > width - ball.r) { ball.x = width - ball.r; ball.vx = -ball.vx * BOUNCE; }
    if (ball.y < ball.r) { ball.y = ball.r; ball.vy = -ball.vy * BOUNCE; }
    if (ball.y > height - ball.r) { ball.y = height - ball.r; ball.vy = -ball.vy * BOUNCE; }

    for (const cat of cats) {
      const distance = Math.hypot(ball.x - cat.x, ball.y - cat.y);
      if (distance >= ball.r + cat.r) continue;
      if (cat.balls < BALLS_PER_CAT) {
        cat.balls += 1;
        ball.alive = false;
        animation.playCatch({ catId: cat.id, x: cat.x / width, y: (cat.y - cat.r * 0.4) / height });
        post("VIBRATION_EVENT");
        break;
      }
      // Котик с двумя клубками — просто препятствие.
      const nx = (ball.x - cat.x) / (distance || 1);
      const ny = (ball.y - cat.y) / (distance || 1);
      ball.x = cat.x + nx * (ball.r + cat.r);
      ball.y = cat.y + ny * (ball.r + cat.r);
      const dot = ball.vx * nx + ball.vy * ny;
      ball.vx -= (1 + BOUNCE) * dot * nx;
      ball.vy -= (1 + BOUNCE) * dot * ny;
    }
  }

  // Клубки сталкиваются друг с другом.
  const alive = balls.filter((ball) => ball.alive);
  for (let i = 0; i < alive.length; i += 1) {
    for (let j = i + 1; j < alive.length; j += 1) {
      const a = alive[i];
      const b = alive[j];
      const dx = b.x - a.x;
      const dy = b.y - a.y;
      const distance = Math.hypot(dx, dy) || 1;
      const overlap = a.r + b.r - distance;
      if (overlap <= 0) continue;
      const nx = dx / distance;
      const ny = dy / distance;
      a.x -= nx * overlap / 2; a.y -= ny * overlap / 2;
      b.x += nx * overlap / 2; b.y += ny * overlap / 2;
      const relative = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
      if (relative < 0) {
        const impulse = -(1 + BOUNCE) * relative / 2;
        a.vx -= impulse * nx; a.vy -= impulse * ny;
        b.vx += impulse * nx; b.vy += impulse * ny;
      }
    }
  }

  if (!won && cats.every((cat) => cat.balls >= BALLS_PER_CAT)) {
    won = true;
    post("COMPLETED_EVENT");
    animation.playDance({ durationMs: DANCE_MS });
    setTimeout(() => {
      running = false;
      post("FINISH_EVENT");
      post("CLOSE_EVENT");
    }, DANCE_MS + 600);
  }
}

function render() {
  animation.setScene({
    visible: true,
    cats: cats.map((cat) => ({ id: cat.id, x: cat.x / width, y: cat.y / height, balls: cat.balls })),
    yarns: balls
      .filter((ball) => ball.alive)
      .map((ball) => ({ id: ball.id, x: ball.x / width, y: ball.y / height, variant: ball.variant, rotation: ball.rotation }))
  });
}

function frame(time) {
  if (!running) return;
  const dt = Math.min((time - lastTime) / 1000, 1 / 30);
  lastTime = time;
  step(dt);
  render();
  frameId = requestAnimationFrame(frame);
}

window.PrankTilt = window.PrankTilt || { x: 0, y: 0 };

window.PrankBridge = {
  // Атлас и картинки грузятся до показа: прикол появляется сразу целиком.
  init: async () => {
    await animation.ready();
  },
  show: () => {
    newLevel();
    render();
    running = true;
    return new Promise((resolve) => {
      requestAnimationFrame((time) => {
        lastTime = time;
        // Ещё кадр — чтобы рендер успел нарисовать сцену до того, как оверлей проявится.
        requestAnimationFrame(() => {
          resolve();
          frameId = requestAnimationFrame(frame);
        });
      });
    });
  },
  hide: () => {
    running = false;
    if (frameId !== null) cancelAnimationFrame(frameId);
    animation.hide();
  },
  on: () => {},
  getVersion: () => "1"
};
