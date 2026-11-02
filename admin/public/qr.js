// Мини-генератор QR-кода (байтовый режим, уровень M, версии 1–9, проверено декодером). Без внешних библиотек.
(function () {
  // [всего слов, слов коррекции на блок, блоков1, данных1, блоков2, данных2]
  var VER = [null,
    [26, 10, 1, 16, 0, 0], [44, 16, 1, 28, 0, 0], [70, 26, 1, 44, 0, 0], [100, 18, 2, 32, 0, 0],
    [134, 24, 2, 43, 0, 0], [172, 16, 4, 27, 0, 0], [196, 18, 4, 31, 0, 0], [242, 22, 2, 38, 2, 39],
    [292, 22, 3, 36, 2, 37], [346, 26, 4, 43, 1, 44]];
  var ALIGN = [null, [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50]];
  var EXP = new Array(512), LOG = new Array(256);
  (function () { var x = 1; for (var i = 0; i < 255; i++) { EXP[i] = x; LOG[x] = i; x <<= 1; if (x & 256) x ^= 0x11d; } for (i = 255; i < 512; i++) EXP[i] = EXP[i - 255]; })();
  function mul(a, b) { return a && b ? EXP[LOG[a] + LOG[b]] : 0; }
  function rs(data, n) {
    var g = [1];
    for (var i = 0; i < n; i++) { var ng = new Array(g.length + 1).fill(0); for (var j = 0; j < g.length; j++) { ng[j] ^= g[j]; ng[j + 1] ^= mul(g[j], EXP[i]); } g = ng; }
    var res = new Array(n).fill(0);
    data.forEach(function (d) { var f = d ^ res.shift(); res.push(0); for (var k = 0; k < n; k++) res[k] ^= mul(g[k + 1], f); });
    return res;
  }
  function utf8(s) { return Array.prototype.slice.call(new TextEncoder().encode(s)); }
  function bch(v, poly, deg) { var d = v << deg; var hb = function (x) { return 31 - Math.clz32(x); }; while (hb(d) >= hb(poly)) d ^= poly << (hb(d) - hb(poly)); return (v << deg) | d; }

  function encode(text) {
    var bytes = utf8(text), ver = 0, i;
    for (i = 1; i <= 9; i++) { var v = VER[i], cap = v[2] * v[3] + v[4] * v[5]; if (bytes.length + 2 <= cap) { ver = i; break; } }
    if (!ver) return null;
    var V = VER[ver], capacity = V[2] * V[3] + V[4] * V[5];
    var bits = [];
    function put(val, len) { for (var b = len - 1; b >= 0; b--) bits.push((val >> b) & 1); }
    put(4, 4); put(bytes.length, 8); bytes.forEach(function (b) { put(b, 8); });
    put(0, Math.min(4, capacity * 8 - bits.length)); while (bits.length % 8) bits.push(0);
    var data = []; for (i = 0; i < bits.length; i += 8) { var x = 0; for (var k = 0; k < 8; k++) x = (x << 1) | bits[i + k]; data.push(x); }
    for (var pad = 0xec; data.length < capacity; pad ^= 0xec ^ 0x11) data.push(pad);
    var blocks = [], pos = 0;
    for (i = 0; i < V[2] + V[4]; i++) { var len = i < V[2] ? V[3] : V[5]; blocks.push(data.slice(pos, pos + len)); pos += len; }
    var ecs = blocks.map(function (b) { return rs(b, V[1]); }), out = [];
    for (i = 0; i < V[5] || i < V[3]; i++) blocks.forEach(function (b) { if (i < b.length) out.push(b[i]); });
    for (i = 0; i < V[1]; i++) ecs.forEach(function (e) { out.push(e[i]); });

    var size = 17 + 4 * ver, m = [], fn = [];
    for (i = 0; i < size; i++) { m.push(new Array(size).fill(0)); fn.push(new Array(size).fill(false)); }
    function set(r, c, v) { m[r][c] = v ? 1 : 0; fn[r][c] = true; }
    function finder(r, c) { for (var y = -1; y <= 7; y++) for (var x = -1; x <= 7; x++) { var rr = r + y, cc = c + x; if (rr < 0 || cc < 0 || rr >= size || cc >= size) continue; set(rr, cc, (y >= 0 && y <= 6 && (x === 0 || x === 6)) || (x >= 0 && x <= 6 && (y === 0 || y === 6)) || (y >= 2 && y <= 4 && x >= 2 && x <= 4)); } }
    finder(0, 0); finder(0, size - 7); finder(size - 7, 0);
    var al = ALIGN[ver];
    al.forEach(function (r) { al.forEach(function (c) { if (fn[r][c]) return; for (var y = -2; y <= 2; y++) for (var x = -2; x <= 2; x++) set(r + y, c + x, Math.max(Math.abs(x), Math.abs(y)) !== 1); }); });
    for (i = 8; i < size - 8; i++) { set(6, i, i % 2 === 0); set(i, 6, i % 2 === 0); }
    set(size - 8, 8, 1);
    for (i = 0; i < 9; i++) { if (!fn[8][i]) set(8, i, 0); if (!fn[i][8]) set(i, 8, 0); }
    for (i = 0; i < 8; i++) { if (!fn[8][size - 1 - i]) set(8, size - 1 - i, 0); if (!fn[size - 1 - i][8]) set(size - 1 - i, 8, 0); }
    if (ver >= 7) { var vi = bch(ver, 0x1f25, 12); for (i = 0; i < 18; i++) { var bit = (vi >> i) & 1; set(Math.floor(i / 3), size - 11 + (i % 3), bit); set(size - 11 + (i % 3), Math.floor(i / 3), bit); } }

    var seq = []; out.forEach(function (b) { for (var k = 7; k >= 0; k--) seq.push((b >> k) & 1); });
    var masks = [function (r, c) { return (r + c) % 2 === 0; }, function (r) { return r % 2 === 0; }, function (r, c) { return c % 3 === 0; }, function (r, c) { return (r + c) % 3 === 0; },
      function (r, c) { return (Math.floor(r / 2) + Math.floor(c / 3)) % 2 === 0; }, function (r, c) { return (r * c) % 2 + (r * c) % 3 === 0; },
      function (r, c) { return ((r * c) % 2 + (r * c) % 3) % 2 === 0; }, function (r, c) { return ((r + c) % 2 + (r * c) % 3) % 2 === 0; }];
    function build(mask) {
      var g = m.map(function (row) { return row.slice(); }), idx = 0, up = true;
      for (var col = size - 1; col > 0; col -= 2) {
        if (col === 6) col--;
        for (var n = 0; n < size; n++) { var r = up ? size - 1 - n : n;
          for (var d = 0; d < 2; d++) { var c = col - d; if (fn[r][c]) continue; var bitv = idx < seq.length ? seq[idx] : 0; idx++; if (masks[mask](r, c)) bitv ^= 1; g[r][c] = bitv; } }
        up = !up;
      }
      var fmt = bch((0 << 3) | mask, 0x537, 10) ^ 0x5412; // уровень M = 00
      function f(r, c, b) { g[r][c] = b; }
      var bt = function (i) { return (fmt >> i) & 1; };
      for (var k = 0; k < 6; k++) f(k, 8, bt(k));
      f(7, 8, bt(6)); f(8, 8, bt(7)); f(8, 7, bt(8));
      for (k = 9; k < 15; k++) f(8, 14 - k, bt(k));
      for (k = 0; k < 8; k++) f(8, size - 1 - k, bt(k));
      for (k = 8; k < 15; k++) f(size - 15 + k, 8, bt(k));
      f(size - 8, 8, 1);
      return g;
    }
    function penalty(g) {
      var p = 0, r, c, run;
      for (r = 0; r < size; r++) { run = 1; for (c = 1; c < size; c++) { if (g[r][c] === g[r][c - 1]) { run++; if (run === 5) p += 3; else if (run > 5) p++; } else run = 1; } }
      for (c = 0; c < size; c++) { run = 1; for (r = 1; r < size; r++) { if (g[r][c] === g[r - 1][c]) { run++; if (run === 5) p += 3; else if (run > 5) p++; } else run = 1; } }
      for (r = 0; r < size - 1; r++) for (c = 0; c < size - 1; c++) if (g[r][c] === g[r][c + 1] && g[r][c] === g[r + 1][c] && g[r][c] === g[r + 1][c + 1]) p += 3;
      var dark = 0; g.forEach(function (row) { row.forEach(function (v) { dark += v; }); });
      p += Math.floor(Math.abs(dark * 20 - size * size * 10) / (size * size)) * 10;
      return p;
    }
    var best = null, bp = 1e9;
    for (var mk = 0; mk < 8; mk++) { var g = build(mk), pn = penalty(g); if (pn < bp) { bp = pn; best = g; } }
    return best;
  }

  function svg(text, px) {
    var g = encode(text); if (!g) return '';
    var n = g.length, q = 4, s = n + q * 2, d = '';
    for (var r = 0; r < n; r++) for (var c = 0; c < n; c++) if (g[r][c]) d += 'M' + (c + q) + ' ' + (r + q) + 'h1v1h-1z';
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + s + ' ' + s + '" width="' + (px || 240) + '" height="' + (px || 240) + '" shape-rendering="crispEdges"><rect width="100%" height="100%" fill="#fff"/><path d="' + d + '" fill="#000"/></svg>';
  }
  window.DVQR = { svg: svg, encode: encode };
  if (typeof module !== 'undefined') module.exports = { svg: svg, encode: encode };
})();
