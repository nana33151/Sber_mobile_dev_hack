export const DANCE_FRAME_COUNT = 4;
export const DEFAULT_DANCE_DURATION_MS = 1600;

export function clamp(value, min, max) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return min;
  return Math.min(max, Math.max(min, numeric));
}

export function danceFrameIndex(elapsedMs, durationMs = DEFAULT_DANCE_DURATION_MS) {
  const safeDuration = Math.max(1, Number(durationMs) || DEFAULT_DANCE_DURATION_MS);
  const progress = clamp(Number(elapsedMs) / safeDuration, 0, 0.999999);
  return Math.floor(progress * DANCE_FRAME_COUNT);
}

export function computeLayout(width, height, catCount) {
  const safeWidth = Math.max(1, Number(width) || 1);
  const safeHeight = Math.max(1, Number(height) || 1);
  const shortSide = Math.min(safeWidth, safeHeight);
  const columns = Math.max(3, Math.min(4, Number(catCount) || 3));

  return {
    catHeight: clamp(
      Math.min(safeWidth / columns * 0.92, safeHeight * 0.24, shortSide * 0.36),
      72,
      164
    ),
    yarnHeight: clamp(
      Math.min(shortSide * 0.12, safeHeight * 0.085),
      28,
      58
    ),
    particleScale: clamp(shortSide / 390, 0.75, 1.2)
  };
}

export function normalizeScene(input = {}) {
  const cats = Array.isArray(input.cats) ? input.cats : [];
  const yarns = Array.isArray(input.yarns) ? input.yarns : [];

  return {
    visible: input.visible !== false,
    cats: cats.slice(0, 4).map((cat, index) => ({
      id: String(cat.id ?? index),
      x: clamp(cat.x, 0, 1),
      y: clamp(cat.y, 0, 1),
      balls: Math.round(clamp(cat.balls, 0, 2)),
      scale: clamp(cat.scale ?? 1, 0.6, 1.4),
      opacity: clamp(cat.opacity ?? 1, 0, 1)
    })),
    yarns: yarns.slice(0, 8).map((yarn, index) => ({
      id: String(yarn.id ?? index),
      x: clamp(yarn.x, -0.2, 1.2),
      y: clamp(yarn.y, -0.2, 1.2),
      variant: Math.round(clamp(yarn.variant ?? index, 0, 7)),
      rotation: Number.isFinite(Number(yarn.rotation)) ? Number(yarn.rotation) : 0,
      scale: clamp(yarn.scale ?? 1, 0.5, 1.5),
      opacity: clamp(yarn.opacity ?? 1, 0, 1)
    }))
  };
}
