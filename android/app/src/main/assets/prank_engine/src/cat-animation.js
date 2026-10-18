import {
  DEFAULT_DANCE_DURATION_MS,
  computeLayout,
  danceFrameIndex,
  normalizeScene
} from "./animation-core.js";

const DEFAULT_ATLAS_URL = new URL("../assets/atlas.json", import.meta.url);

function loadImage(url) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.decoding = "async";
    image.onload = () => resolve(image);
    image.onerror = () => reject(new Error(`Unable to load animation image: ${url}`));
    image.src = url;
  });
}

export class CatAnimationRenderer {
  constructor(canvas, options = {}) {
    if (!(canvas instanceof HTMLCanvasElement)) {
      throw new TypeError("CatAnimationRenderer requires a canvas element");
    }

    this.canvas = canvas;
    this.context = canvas.getContext("2d", { alpha: true });
    this.atlasUrl = new URL(options.atlasUrl ?? DEFAULT_ATLAS_URL, document.baseURI);
    this.atlas = null;
    this.images = {};
    this.scene = normalizeScene({ visible: false });
    this.particles = [];
    this.bumps = new Map();
    this.dance = null;
    this.rafId = null;
    this.previousTime = 0;
    this.width = 0;
    this.height = 0;
    this.pixelRatio = 1;
    this.boundResize = () => this.resize();
    this.boundFrame = (time) => this.frame(time);
    this.visualViewport = window.visualViewport ?? null;
  }

  async init() {
    const response = await fetch(this.atlasUrl);
    if (!response.ok) throw new Error(`Unable to load atlas: ${response.status}`);

    this.atlas = await response.json();
    const baseUrl = new URL("./", this.atlasUrl);
    const entries = ["catStates", "catDance", "yarnVariants"];

    await Promise.all(entries.map(async (key) => {
      this.images[key] = await loadImage(new URL(this.atlas[key].image, baseUrl));
    }));

    this.resize();
    window.addEventListener("resize", this.boundResize, { passive: true });
    this.visualViewport?.addEventListener("resize", this.boundResize, { passive: true });
    this.rafId = requestAnimationFrame(this.boundFrame);
    this.canvas.dispatchEvent(new CustomEvent("cat-animation:ready"));
    return this;
  }

  destroy() {
    window.removeEventListener("resize", this.boundResize);
    this.visualViewport?.removeEventListener("resize", this.boundResize);
    if (this.rafId !== null) cancelAnimationFrame(this.rafId);
    this.rafId = null;
    this.context.clearRect(0, 0, this.width, this.height);
  }

  resize() {
    const rect = this.canvas.getBoundingClientRect();
    this.width = Math.max(1, rect.width || window.innerWidth);
    this.height = Math.max(1, rect.height || window.innerHeight);
    this.pixelRatio = Math.min(window.devicePixelRatio || 1, 2);
    this.canvas.width = Math.round(this.width * this.pixelRatio);
    this.canvas.height = Math.round(this.height * this.pixelRatio);
    this.context.setTransform(this.pixelRatio, 0, 0, this.pixelRatio, 0, 0);
    this.context.imageSmoothingEnabled = true;
    this.context.imageSmoothingQuality = "high";
  }

  setScene(scene) {
    this.scene = normalizeScene(scene);
  }

  playCatch({ catId, x, y } = {}) {
    const cat = this.scene.cats.find((item) => item.id === String(catId));
    const originX = Number.isFinite(Number(x)) ? Number(x) : cat?.x ?? 0.5;
    const originY = Number.isFinite(Number(y)) ? Number(y) : cat?.y ?? 0.7;
    const now = performance.now();
    const layout = computeLayout(this.width, this.height, this.scene.cats.length);

    if (cat) this.bumps.set(cat.id, now);

    for (let index = 0; index < 12; index += 1) {
      const angle = (Math.PI * 2 * index) / 12 + Math.random() * 0.25;
      const speed = 35 + Math.random() * 65;
      this.particles.push({
        x: originX * this.width,
        y: originY * this.height,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed - 25,
        life: 0.55 + Math.random() * 0.25,
        age: 0,
        radius: (3 + Math.random() * 4) * layout.particleScale,
        color: ["#ff5f6d", "#ffd93d", "#65d6a6", "#55b8ff"][index % 4]
      });
    }
  }

  playDance({ durationMs = DEFAULT_DANCE_DURATION_MS } = {}) {
    const duration = Math.max(1000, Math.min(3000, Number(durationMs) || DEFAULT_DANCE_DURATION_MS));
    this.dance = { startedAt: performance.now(), durationMs: duration };
  }

  hide() {
    this.scene = normalizeScene({ visible: false });
    this.dance = null;
    this.particles = [];
  }

  frame(time) {
    const deltaSeconds = Math.min(0.05, Math.max(0, (time - this.previousTime) / 1000));
    this.previousTime = time;
    this.updateParticles(deltaSeconds);
    this.draw(time);
    this.rafId = requestAnimationFrame(this.boundFrame);
  }

  updateParticles(deltaSeconds) {
    for (const particle of this.particles) {
      particle.age += deltaSeconds;
      particle.vy += 85 * deltaSeconds;
      particle.x += particle.vx * deltaSeconds;
      particle.y += particle.vy * deltaSeconds;
    }
    this.particles = this.particles.filter((particle) => particle.age < particle.life);
  }

  draw(time) {
    const context = this.context;
    context.clearRect(0, 0, this.width, this.height);
    if (!this.atlas || (!this.scene.visible && this.particles.length === 0)) return;

    const layout = computeLayout(this.width, this.height, this.scene.cats.length);
    for (const yarn of this.scene.yarns) this.drawYarn(yarn, layout);
    for (const cat of this.scene.cats) this.drawCat(cat, time, layout);
    this.drawParticles();

    if (this.dance && time - this.dance.startedAt >= this.dance.durationMs) {
      this.dance = null;
      this.canvas.dispatchEvent(new CustomEvent("cat-animation:dance-complete", { bubbles: true }));
    }
  }

  drawYarn(yarn, layout) {
    const frames = this.atlas.yarnVariants.frames;
    const frame = frames[yarn.variant % frames.length];
    const size = layout.yarnHeight * yarn.scale;
    this.drawSprite(
      this.images.yarnVariants,
      frame,
      yarn.x * this.width,
      yarn.y * this.height,
      size,
      yarn.rotation,
      yarn.opacity
    );
  }

  drawCat(cat, time, layout) {
    let frame;
    let image;
    let bounce = 0;

    if (this.dance) {
      const elapsed = time - this.dance.startedAt;
      frame = this.atlas.catDance.frames[danceFrameIndex(elapsed, this.dance.durationMs)];
      image = this.images.catDance;
    } else {
      const state = cat.balls <= 0 ? "ready" : cat.balls === 1 ? "oneBall" : "twoBalls";
      frame = this.atlas.catStates.frames[state];
      image = this.images.catStates;
      const bumpedAt = this.bumps.get(cat.id);
      if (bumpedAt) {
        const progress = (time - bumpedAt) / 350;
        if (progress < 1) bounce = Math.sin(progress * Math.PI) * layout.catHeight * 0.075;
        else this.bumps.delete(cat.id);
      }
    }

    this.drawSprite(
      image,
      frame,
      cat.x * this.width,
      cat.y * this.height - bounce,
      layout.catHeight * cat.scale,
      0,
      cat.opacity
    );
  }

  drawSprite(image, frame, centerX, centerY, targetHeight, rotation, opacity) {
    const ratio = frame.width / frame.height;
    const targetWidth = targetHeight * ratio;
    const context = this.context;

    context.save();
    context.globalAlpha = opacity;
    context.translate(centerX, centerY);
    context.rotate(rotation);
    context.drawImage(
      image,
      frame.x,
      frame.y,
      frame.width,
      frame.height,
      -targetWidth / 2,
      -targetHeight / 2,
      targetWidth,
      targetHeight
    );
    context.restore();
  }

  drawParticles() {
    const context = this.context;
    for (const particle of this.particles) {
      const progress = particle.age / particle.life;
      context.save();
      context.globalAlpha = 1 - progress;
      context.fillStyle = particle.color;
      context.beginPath();
      context.arc(particle.x, particle.y, particle.radius * (1 - progress * 0.4), 0, Math.PI * 2);
      context.fill();
      context.restore();
    }
  }
}
