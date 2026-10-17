const CAT_POSITIONS = [
  { id: "cat-1", x: 0.2, y: 0.78 },
  { id: "cat-2", x: 0.5, y: 0.78 },
  { id: "cat-3", x: 0.8, y: 0.78 }
];

export function startNativeMock(api) {
  let animationFrame;
  let runId = 0;

  function restart() {
    runId += 1;
    const currentRun = runId;
    cancelAnimationFrame(animationFrame);

    const cats = CAT_POSITIONS.map((cat) => ({ ...cat, balls: 0 }));
    const yarns = Array.from({ length: 6 }, (_, index) => ({
      id: `yarn-${index}`,
      variant: index,
      x: 0.12 + (index % 3) * 0.36,
      y: -0.12 - Math.floor(index / 3) * 0.12,
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
        const local = Math.max(0, Math.min(1, (elapsed - index * 420) / 1800));
        const eased = 1 - Math.pow(1 - local, 3);
        const target = cats[catIndex];

        yarn.x += (target.x - yarn.x) * 0.035;
        yarn.y = -0.1 + (target.y + 0.02) * eased;
        yarn.rotation += 0.045;

        if (local >= 1 && !caught.has(yarn.id)) {
          caught.add(yarn.id);
          cats[catIndex].balls = Math.min(2, cats[catIndex].balls + 1);
          api.playCatch({ catId: target.id, x: target.x, y: target.y - 0.06 });
        }

        if (!caught.has(yarn.id)) visibleYarns.push({ ...yarn });
      }

      api.setScene({ visible: true, cats, yarns: visibleYarns });

      if (caught.size === yarns.length) {
        api.playDance({ durationMs: 2400 });
        return;
      }

      animationFrame = requestAnimationFrame(tick);
    }

    animationFrame = requestAnimationFrame(tick);
  }

  restart();
  return { restart };
}
