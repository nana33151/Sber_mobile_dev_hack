const CAT_POSITIONS = [
  { id: "cat-1", x: 0.2, y: 0.78 },
  { id: "cat-2", x: 0.5, y: 0.78 },
  { id: "cat-3", x: 0.8, y: 0.78 }
];

// Клубки сразу появляются внутри экрана, по два на каждого котика.
const YARN_POSITIONS = [
  { x: 0.12, y: 0.18 },
  { x: 0.46, y: 0.14 },
  { x: 0.82, y: 0.2 },
  { x: 0.18, y: 0.42 },
  { x: 0.54, y: 0.38 },
  { x: 0.86, y: 0.44 }
];

export function startNativeMock(api) {
  let animationFrame;
  let runId = 0;

  function restart() {
    runId += 1;
    const currentRun = runId;
    cancelAnimationFrame(animationFrame);

    const cats = CAT_POSITIONS.map((cat) => ({ ...cat, balls: 0 }));
    const yarns = YARN_POSITIONS.map((position, index) => ({
      id: `yarn-${index}`,
      variant: index,
      ...position,
      startX: position.x,
      startY: position.y,
      rotation: 0
    }));
    const caught = new Set();
    const startedAt = performance.now();

    api.setScene({ visible: true, cats, yarns });

    function tick(now) {
      if (currentRun !== runId) return;
      const elapsed = now - startedAt;
      const visibleYarns = [];

      for (let index = 0; index < yarns.length; index += 1) {
        const yarn = yarns[index];
        const catIndex = index % cats.length;
        const local = Math.max(0, Math.min(1, (elapsed - index * 220) / 1900));
        const eased = local * local * (3 - 2 * local);
        const target = cats[catIndex];
        const previousX = yarn.x;
        const previousY = yarn.y;
        const curve = Math.sin(local * Math.PI) * (index % 2 === 0 ? 0.07 : -0.07);

        yarn.x = yarn.startX + (target.x - yarn.startX) * eased + curve;
        yarn.y = yarn.startY + (target.y - yarn.startY) * eased;
        // Вращение зависит от пройденного расстояния, поэтому клубок именно катится.
        yarn.rotation += Math.hypot(yarn.x - previousX, yarn.y - previousY) * 32;

        if (local >= 1 && !caught.has(yarn.id)) {
          caught.add(yarn.id);
          cats[catIndex].balls = Math.min(2, cats[catIndex].balls + 1);
          api.playCatch({ catId: target.id, x: target.x, y: target.y - 0.06 });
        }

        if (!caught.has(yarn.id)) visibleYarns.push({ ...yarn });
      }

      api.setScene({ visible: true, cats, yarns: visibleYarns });

      if (caught.size === yarns.length) {
        api.playDance({ durationMs: 1600 });
        return;
      }

      animationFrame = requestAnimationFrame(tick);
    }

    animationFrame = requestAnimationFrame(tick);
  }

  restart();
  return { restart };
}
