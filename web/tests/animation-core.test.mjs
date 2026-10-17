import assert from "node:assert/strict";
import test from "node:test";

import {
  danceFrameIndex,
  normalizeScene
} from "../src/animation-core.js";

test("dance uses four frames across 2.4 seconds", () => {
  assert.equal(danceFrameIndex(0, 2400), 0);
  assert.equal(danceFrameIndex(600, 2400), 1);
  assert.equal(danceFrameIndex(1200, 2400), 2);
  assert.equal(danceFrameIndex(1800, 2400), 3);
  assert.equal(danceFrameIndex(2400, 2400), 3);
});

test("scene input is bounded for safe rendering", () => {
  const scene = normalizeScene({
    cats: [{ id: 1, x: -5, y: 7, balls: 9 }],
    yarns: [{ id: 2, x: -4, y: 8, variant: 99, opacity: -2 }]
  });

  assert.deepEqual(scene.cats[0], {
    id: "1",
    x: 0,
    y: 1,
    balls: 2,
    scale: 1,
    opacity: 1
  });
  assert.equal(scene.yarns[0].x, -0.2);
  assert.equal(scene.yarns[0].y, 1.2);
  assert.equal(scene.yarns[0].variant, 7);
  assert.equal(scene.yarns[0].opacity, 0);
});
