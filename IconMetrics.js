// IconMetrics.js - per-icon optical size measurements, shared by every tile.
//
// Icon artwork varies wildly: some fill the canvas edge to edge, others carry
// generous transparent padding, some are circles. Each icon is rasterised once
// at SAMPLE px, and we record the bounding box of its visible pixels plus how
// much of that box is filled (≈1 for squares, ≈0.79 for circles), so tiles can
// scale every icon to the same visual size, macOS-style.
.pragma library

var SAMPLE = 96;
var cache = {};

function get(source) {
  return cache[source] || null;
}

function measure(source, data, w, h) {
  var minX = w, minY = h, maxX = -1, maxY = -1, count = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (data[(y * w + x) * 4 + 3] > 24) {
        count++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  var m;
  if (maxX < 0) {
    m = { x0: 0, y0: 0, x1: 1, y1: 1, fill: 0.8 };
  } else {
    var bw = maxX - minX + 1, bh = maxY - minY + 1;
    m = { x0: minX / w, y0: minY / h, x1: (maxX + 1) / w, y1: (maxY + 1) / h,
          fill: count / (bw * bh) };
  }
  cache[source] = m;
  return m;
}

// Size of the icon's visible extent relative to the tile. Squares read larger
// than circles of the same width, so dense shapes are pulled in a little.
function targetRatio(fill, base) {
  var f = Math.max(0.7, Math.min(1, fill));
  return base * (1 - (f - 0.7) / 0.3 * 0.12);
}
