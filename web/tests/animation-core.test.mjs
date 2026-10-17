import assert from "node:assert/strict";
import test from "node:test";

import {
  computeLayout,
  danceFrameIndex,
  normalizeScene
} from "../src/animation-core.js";

test("dance cycles quickly through four frames", () => {
  assert.equal(danceFrameIndex(0, 1600), 0);
  assert.equal(danceFrameIndex(140, 1600), 1);
  assert.equal(danceFrameIndex(280, 1600), 2);
  assert.equal(danceFrameIndex(420, 1600), 3);
  assert.equal(danceFrameIndex(560, 1600), 0);
});

test("layout adapts to portrait and landscape phones", () => {
  const portrait = computeLayout(390, 844, 3);
  const compact = computeLayout(320, 568, 4);
  const landscape = computeLayout(844, 390, 3);

  assert.equal(Math.round(portrait.catHeight), 120);
  assert.equal(Math.round(compact.catHeight), 74);
  assert.equal(Math.round(landscape.catHeight), 94);
  assert.ok(compact.yarnHeight < portrait.yarnHeight);
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
