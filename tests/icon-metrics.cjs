// Checks IconMetrics.js optical measurements on synthetic RGBA icons.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const ctx = {};
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname, "..", "IconMetrics.js"), "utf8")
  .replace(".pragma library", ""), ctx);

function icon(size, paint) {
  const data = new Uint8ClampedArray(size * size * 4);
  for (let y = 0; y < size; y++)
    for (let x = 0; x < size; x++)
      if (paint(x, y)) data[(y * size + x) * 4 + 3] = 255;
  return data;
}

// Padded square: 10px transparent margin on a 100px canvas.
const sq = ctx.measure("sq", icon(100, (x, y) => x >= 10 && x < 90 && y >= 10 && y < 90), 100, 100);
assert.equal(sq.x0, 0.1); assert.equal(sq.x1, 0.9);
assert.ok(sq.fill > 0.99);

// Edge-to-edge circle.
const c = ctx.measure("c", icon(100, (x, y) => (x - 49.5) ** 2 + (y - 49.5) ** 2 <= 50 * 50), 100, 100);
assert.ok(Math.abs(c.fill - Math.PI / 4) < 0.02);

// Empty image falls back to the full canvas instead of dividing by zero.
const e = ctx.measure("e", icon(10, () => false), 10, 10);
assert.equal(e.x1 - e.x0, 1);

// Squares are drawn smaller than circles; results are cached by source.
assert.ok(ctx.targetRatio(sq.fill, 0.86) < ctx.targetRatio(c.fill, 0.86));
assert.equal(ctx.get("sq"), sq);
console.log("icon-metrics ok");
