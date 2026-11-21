// Hand-modelled landmarks for the four regions. Each one is a recognisable approximation built from
// boxes, beams, prisms and lathed shapes at roughly real-world size (metres), placed by world.js.
// Everything goes through the generator's own helpers, so it lands in the shared material groups.

export function createLandmarks(ctx) {
  const { THREE, W, box, tpl, quad, bake, col, FACADE } = ctx;
  const C = (h) => col(h);
  const WHITE = C('#f4f0e8'), STONE = C('#d8cdb6'), LIME = C('#cfc4ae'), GRANITE = C('#9a8c84'), DARKG = C('#20252c');
  const STEEL = C('#8a9096'), COPPER = C('#6fae98'), GOLD = C('#ffcf5a'), RED = C('#ff2a20'), BLACK = C('#16181c');
  const uvOf = (style, off = 0) => { const [cw, fh] = FACADE[style]; return [1 / (8 * cw), 1 / (8 * fh), off, 0]; };

  // ---- primitives -----------------------------------------------------------------
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
  const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
  const nrm = (a) => { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0] / l, a[1] / l, a[2] / l]; };
  const add3 = (a, b, k = 1) => [a[0] + b[0] * k, a[1] + b[1] * k, a[2] + b[2] * k];
  // a square-section bar from world point a to b
  function beam(G, name, a, b, w, h, c) {
    const d = sub(b, a), len = Math.hypot(d[0], d[1], d[2]);
    if (len < 1e-4) return;
    const dn = [d[0] / len, d[1] / len, d[2] / len];
    let s = cross(dn, [0, 1, 0]);
    s = Math.hypot(s[0], s[1], s[2]) < 1e-3 ? [1, 0, 0] : nrm(s);
    const u = cross(s, dn);
    const P = (e, i, j) => add3(add3(e, s, (i * w) / 2), u, (j * h) / 2);
    const A = [P(a, -1, -1), P(a, 1, -1), P(a, 1, 1), P(a, -1, 1)], B = [P(b, -1, -1), P(b, 1, -1), P(b, 1, 1), P(b, -1, 1)];
    const ns = [[-u[0], -u[1], -u[2]], s, u, [-s[0], -s[1], -s[2]]]; // outward normal of each long face
    for (let k = 0; k < 4; k++) { const k2 = (k + 1) % 4; quad(G, name, A[k], B[k], B[k2], A[k2], ns[k], null, c); }
    quad(G, name, A[0], A[1], A[2], A[3], [-dn[0], -dn[1], -dn[2]], null, c);
    quad(G, name, B[0], B[1], B[2], B[3], dn, null, c);
  }
  // a frame at the landmark: local +x looks at the road when f = +1 (see world.js landmark sides)
  function frame(L, gy, rot = L.h) {
    const cs = Math.cos(rot), sn = Math.sin(rot);
    const P = (lx, ly, lz) => [L.x + lx * cs + lz * sn, gy + ly, L.z - lx * sn + lz * cs];
    return { x: L.x, y: gy, z: L.z, rot, f: L.side, P, cs, sn };
  }
  // vertical prism over a local polygon (counter-clockwise), facade-mapped walls, flat top
  function prism(G, F, name, pts, y0, y1, c, uv = null, top = true, topName = 'trim', topC = c) {
    const n = pts.length;
    let u = 0, area = 0;
    for (let i = 0; i < n; i++) { const [ax, az] = pts[i], [bx, bz] = pts[(i + 1) % n]; area += ax * bz - bx * az; }
    const sg = area >= 0 ? 1 : -1; // outward normals whichever way the polygon winds
    for (let i = 0; i < n; i++) {
      const [ax, az] = pts[i], [bx, bz] = pts[(i + 1) % n], len = Math.hypot(bx - ax, bz - az);
      const nx = sg * (bz - az), nz = -sg * (bx - ax), l = Math.hypot(nx, nz) || 1;
      const wn = [(nx / l) * F.cs + (nz / l) * F.sn, 0, -(nx / l) * F.sn + (nz / l) * F.cs];
      const uvs = uv ? [[u * uv[0], y0 * uv[1]], [(u + len) * uv[0], y0 * uv[1]], [(u + len) * uv[0], y1 * uv[1]], [u * uv[0], y1 * uv[1]]] : null;
      quad(G, name, F.P(ax, y0, az), F.P(bx, y0, bz), F.P(bx, y1, bz), F.P(ax, y1, az), wn, uvs, c);
      u += len;
    }
    if (top) for (let i = 1; i < n - 1; i++) quad(G, topName, F.P(pts[0][0], y1, pts[0][1]), F.P(pts[i][0], y1, pts[i][1]), F.P(pts[i + 1][0], y1, pts[i + 1][1]), F.P(pts[i + 1][0], y1, pts[i + 1][1]), [0, 1, 0], null, topC);
  }
  // a tapered tube between two polygons with the same vertex count
  function loft(G, F, name, bot, top, y0, y1, c, uv = null) {
    const n = bot.length;
    for (let i = 0; i < n; i++) {
      const j = (i + 1) % n;
      const a = F.P(bot[i][0], y0, bot[i][1]), b = F.P(bot[j][0], y0, bot[j][1]), cc = F.P(top[j][0], y1, top[j][1]), d = F.P(top[i][0], y1, top[i][1]);
      let nn = nrm(cross(sub(b, a), sub(d, a)));
      const mid = [(a[0] + cc[0]) / 2, (a[1] + cc[1]) / 2, (a[2] + cc[2]) / 2], ax = F.P(0, mid[1] - F.y, 0);
      if (nn[0] * (mid[0] - ax[0]) + nn[2] * (mid[2] - ax[2]) < 0) nn = [-nn[0], -nn[1], -nn[2]];
      const len = Math.hypot(bot[j][0] - bot[i][0], bot[j][1] - bot[i][1]);
      const uvs = uv ? [[0, y0 * uv[1]], [len * uv[0], y0 * uv[1]], [len * uv[0], y1 * uv[1]], [0, y1 * uv[1]]] : null;
      quad(G, name, a, b, cc, d, nn, uvs, c);
    }
  }
  const circle = (r, n, a0 = 0) => Array.from({ length: n }, (_, i) => [Math.cos(a0 + (i / n) * Math.PI * 2) * r, Math.sin(a0 + (i / n) * Math.PI * 2) * r]).reverse();
  const rect = (cx, cz, hx, hz) => [[cx - hx, cz - hz], [cx - hx, cz + hz], [cx + hx, cz + hz], [cx + hx, cz - hz]];
  const offset = (pts, dx, dz) => pts.map(([x, z]) => [x + dx, z + dz]);
  // cylinders/discs/domes as baked templates
  const TT = {
    cyl: bake([[new THREE.CylinderGeometry(1, 1, 1, 28).translate(0, 0.5, 0), 0, 0]]),
    cone: bake([[new THREE.ConeGeometry(1, 1, 24).translate(0, 0.5, 0), 0, 0]]),
    dome: bake([[new THREE.SphereGeometry(1, 28, 12, 0, Math.PI * 2, 0, Math.PI / 2), 0, 0]]),
    ball: bake([[new THREE.SphereGeometry(1, 28, 18), 0, 0]]),
    torus: bake([[new THREE.TorusGeometry(1, 0.035, 6, 64), 0, 0]]), // in the xy plane
  };
  const T3 = (c) => [c, c, c];
  const cyl = (G, F, name, lx, ly, lz, r, h, c, t = TT.cyl) => { const p = F.P(lx, ly, lz); tpl(G, name, t, p[0], p[1], p[2], F.rot, r, h, T3(c)); };
  const solid = (G, F, lx, lz, hx, hz) => { const p = F.P(lx, 0, lz); G.foot.push(p[0], p[2], F.rot, hx, hz); };

  // ---- a stroke font for signs (letters on a 4 × 6 grid) --------------------------------
  const FONT = {
    H: [[0, 0, 0, 6], [4, 0, 4, 6], [0, 3, 4, 3]], O: [[0, 0, 4, 0], [4, 0, 4, 6], [4, 6, 0, 6], [0, 6, 0, 0]],
    L: [[0, 0, 0, 6], [0, 0, 4, 0]], Y: [[0, 6, 2, 3], [4, 6, 2, 3], [2, 3, 2, 0]], W: [[0, 6, 1, 0], [1, 0, 2, 3.4], [2, 3.4, 3, 0], [3, 0, 4, 6]],
    D: [[0, 0, 0, 6], [0, 6, 2.6, 6], [2.6, 6, 4, 4.6], [4, 4.6, 4, 1.4], [4, 1.4, 2.6, 0], [2.6, 0, 0, 0]],
    C: [[4, 6, 0, 6], [0, 6, 0, 0], [0, 0, 4, 0]], N: [[0, 0, 0, 6], [0, 6, 4, 0], [4, 0, 4, 6]],
  };
  // letters standing in the local (z, y) plane at local x = lx, reading correctly from the road
  function word(G, F, name, text, lx, y0, lz0, size, gap, thick, depth, c, groundFn = null) {
    const k = size / 6, adv = -F.f; // see world.js: the road is towards local +f·x
    let z = lz0 - adv * ((text.length * (4 * k + gap) - gap) / 2);
    for (const ch of text) {
      const strokes = FONT[ch] || [];
      const yb = groundFn ? groundFn(lx, z + adv * 2 * k) : y0;
      for (const [u0, v0, u1, v1] of strokes) {
        const a = F.P(lx, yb + v0 * k, z + adv * u0 * k), b = F.P(lx, yb + v1 * k, z + adv * u1 * k);
        beam(G, name, a, b, depth, thick, c);
      }
      if (groundFn) for (const uu of [0.6, 3.4]) { // support legs behind each letter
        const a = F.P(lx - F.f * 1.5, yb - 4, z + adv * uu * k), b = F.P(lx - F.f * 0.6, yb + 4 * k, z + adv * uu * k);
        beam(G, 'trim', a, b, 0.3, 0.3, STEEL);
      }
      z += adv * (4 * k + gap);
    }
  }
  // a ferris wheel standing in the local (z, y) plane, hub at (lx, hubY, lz)
  function wheel(G, F, lx, hubY, lz, R, spokes, rimC, lit) {
    const ring = (r, c, name) => {
      const n = 48;
      for (let i = 0; i < n; i++) {
        const a0 = (i / n) * Math.PI * 2, a1 = ((i + 1) / n) * Math.PI * 2;
        beam(G, name, F.P(lx, hubY + Math.sin(a0) * r, lz + Math.cos(a0) * r), F.P(lx, hubY + Math.sin(a1) * r, lz + Math.cos(a1) * r), 0.5, 0.5, c);
      }
    };
    ring(R, rimC, 'trim'); ring(R - 1.2, rimC, 'trim'); ring(R + 0.35, lit, 'neon');
    for (let i = 0; i < spokes; i++) {
      const a = (i / spokes) * Math.PI * 2, e = F.P(lx, hubY + Math.sin(a) * R, lz + Math.cos(a) * R);
      beam(G, 'trim', F.P(lx, hubY, lz), e, 0.25, 0.25, rimC);
      const g = F.P(lx, hubY + Math.sin(a) * R - 2.2, lz + Math.cos(a) * R);
      box(G, 'trim', g[0], g[1], g[2], F.rot, 0, 0, 0, 2.2, 2.0, 2.2, [C('#e0533a'), C('#f2c45a'), C('#3a8fd8'), C('#5ec8c0')][i % 4], null, { ao: false });
    }
    for (const s of [-1, 1]) beam(G, 'trim', F.P(lx, hubY - R - 6, lz + s * R * 0.55), F.P(lx, hubY, lz), 1.2, 1.2, rimC); // A-frame legs
    cyl(G, F, 'trim', lx, hubY - 1.2, lz, 1.4, 2.4, STEEL);
  }
  // a pier deck running away from the road into the water, with pilings
  function pier(G, F, x0, x1, width, deckY) {
    const dir = Math.sign(x1 - x0);
    for (let x = x0; dir * (x1 - x) > 0; x += dir * 12) {
      const a = Math.min(x, x + dir * 12), b = Math.max(x, x + dir * 12);
      prism(G, F, 'trim', rect((a + b) / 2, 0, (b - a) / 2 + 0.02, width / 2), deckY - 0.8, deckY, C('#8a7058'), null, true, 'trim', C('#a88a68'));
      for (const z of [-width / 2 + 1, width / 2 - 1]) cyl(G, F, 'trim', x, -6, z, 0.45, deckY + 5.2, C('#5a4a3a'));
    }
    for (let x = x0; dir * (x1 - x) > 0; x += dir * 4) for (const z of [-width / 2, width / 2]) {
      const p = F.P(x, deckY, z); box(G, 'trim', p[0], p[1], p[2], F.rot, 0, 0, 0, 0.12, 1.1, 0.12, WHITE, null, { ao: false });
    }
  }
  const gyAt = (F, lx, lz) => { const p = F.P(lx, 0, lz); return W.heightAt(p[0], p[2]); };

  // ---- the landmarks -------------------------------------------------------------------
  const B = {};
  // Los Angeles
  B.usbank = (G, F) => { // 310 m cylinder with stepped setbacks and a lit glass crown
    const fac = uvOf('tower');
    prism(G, F, 'facade_condo', circle(30, 32), -2, 9, C('#b8ac9c'), uvOf('condo'));
    prism(G, F, 'facade_tower', circle(23, 40), 9, 290, C('#c8bca8'), fac);
    for (const [a, h] of [[0, 230], [Math.PI / 2, 255], [Math.PI, 205], [Math.PI * 1.5, 270]]) {
      const cx = Math.cos(a) * 21, cz = Math.sin(a) * 21;
      prism(G, F, 'facade_tower', rect(cx, cz, 6, 6), 9, h, C('#b4a894'), fac);
    }
    prism(G, F, 'glass', circle(21.5, 40), 290, 306, WHITE);
    cyl(G, F, 'neon', 0, 300, 0, 22.4, 0.6, C('#fff2d8'));
    cyl(G, F, 'trim', 0, 306, 0, 17, 1.2, STEEL);
    cyl(G, F, 'neon', 0, 307.2, 0, 6, 0.1, RED);
    solid(G, F, 0, 0, 30, 30);
  };
  B.disney = (G, F) => { // stainless-steel sails over a stone base
    prism(G, F, 'facade_condo', rect(0, 0, 28, 38), -2, 9, C('#c8b8a0'), uvOf('condo'));
    const chrome = C('#e4e8ec');
    const sails = [[0, 12, 0.3, 22, 26, 1.6], [-10, -14, -0.5, 18, 30, 1.3], [8, 18, 1.2, 16, 22, 1.4], [-6, 24, 2.4, 14, 18, 1.2], [12, -20, -1.3, 15, 24, 1.5], [-14, 2, 3.4, 13, 20, 1.1], [4, -2, 4.6, 12, 34, 1.0]];
    for (const [lx, lz, yaw, r, h, arc] of sails) {
      const g = new THREE.CylinderGeometry(r, r * 0.82, h, 24, 6, true, 0, arc);
      const pa = g.attributes.position; // lean the sail outward as it rises, like a wind-filled sheet
      for (let i = 0; i < pa.count; i++) { const y = pa.getY(i) / h + 0.5; pa.setX(i, pa.getX(i) * (1 + 0.18 * y * y)); pa.setZ(i, pa.getZ(i) * (1 + 0.1 * y)); }
      g.translate(0, h / 2, 0);
      const t = bake([[g, 0, 0]]);
      const p = F.P(lx, 8, lz);
      tpl(G, 'chrome', t, p[0], p[1], p[2], F.rot + yaw, 1, 1, T3(chrome));
    }
    solid(G, F, 0, 0, 28, 38);
  };
  B.capitol = (G, F) => { // the stack of records: 13 round floors with sunshade fins and a needle on top
    prism(G, F, 'trim', rect(0, 0, 14, 14), -2, 4, C('#e8e4dc'));
    for (let k = 0; k < 13; k++) {
      const y = 4 + k * 3.2, r = 13.5 - Math.max(0, k - 9) * 1.2;
      cyl(G, F, 'glass', 0, y, 0, r - 1.4, 2.7, WHITE);
      cyl(G, F, 'trim', 0, y + 2.7, 0, r, 0.5, C('#f4f0e8'));
      for (let i = 0; i < 24; i++) { const a = (i / 24) * Math.PI * 2; beam(G, 'trim', F.P(Math.cos(a) * r, y + 0.1, Math.sin(a) * r), F.P(Math.cos(a) * r, y + 2.7, Math.sin(a) * r), 0.16, 0.5, C('#f4f0e8')); }
    }
    beam(G, 'trim', F.P(0, 46, 0), F.P(0, 76, 0), 0.6, 0.6, WHITE);
    cyl(G, F, 'neon', 0, 76, 0, 0.7, 1.4, RED);
    solid(G, F, 0, 0, 14, 14);
  };
  B.griffith = (G, F) => { // white observatory with three domes, on its hill
    const gy = gyAt(F, 0, 0);
    const G2 = { ...F, P: (lx, ly, lz) => F.P(lx, ly + gy - F.y, lz) };
    prism(G, G2, 'facade_house', rect(0, 0, 9, 46), -6, 12, C('#f6f2ea'), uvOf('house'));
    prism(G, G2, 'facade_house', rect(0, 0, 16, 12), -6, 16, C('#f6f2ea'), uvOf('house'));
    cyl(G, G2, 'trim', 0, 16, 0, 11, 4, C('#f6f2ea'));
    cyl(G, G2, 'metal', 0, 20, 0, 11.2, 11.2, C('#2c3a36'), TT.dome);
    for (const z of [-40, 40]) { cyl(G, G2, 'trim', 0, 12, z, 6, 3, C('#f6f2ea')); cyl(G, G2, 'metal', 0, 15, z, 6.2, 6.2, C('#2c3a36'), TT.dome); }
    prism(G, G2, 'trim', rect(F.f * 22, 0, 10, 50), -6, 0.4, C('#d8d0c0'));
    beam(G, 'trim', G2.P(F.f * 24, 0, 0), G2.P(F.f * 24, 11, 0), 1.2, 1.2, C('#e8e4dc')); // the astronomers' monument
  };
  B.hollywood = (G, F) => { // the nine white letters on the hillside, facing the city
    const lx = F.f * 150; // down the slope towards the road
    const ground = (x, z) => { const p = F.P(x, 0, z); return W.heightAt(p[0], p[2]) - F.y + 1; };
    word(G, F, 'trim', 'HOLLYWOOD', lx, 0, 0, 13.7, 3.2, 2.4, 0.8, C('#fbfaf6'), ground);
  };
  B.theme = (G, F) => { // two crossing parabolic arches holding a flying saucer
    const arch = (yaw, span, h) => {
      const cs = Math.cos(yaw), sn = Math.sin(yaw), n = 18, pts = [];
      for (let i = 0; i <= n; i++) { const t = -1 + (2 * i) / n; pts.push(F.P(cs * t * span, h * (1 - t * t), sn * t * span)); }
      for (let i = 0; i < n; i++) beam(G, 'trim', pts[i], pts[i + 1], 1.6, 1.6, WHITE);
    };
    arch(Math.PI / 4, 40, 41); arch(-Math.PI / 4, 40, 41);
    cyl(G, F, 'trim', 0, 0, 0, 3.4, 20, WHITE);
    cyl(G, F, 'glass', 0, 19, 0, 14, 3, WHITE);
    cyl(G, F, 'trim', 0, 22, 0, 16, 0.8, WHITE);
    cyl(G, F, 'neon', 0, 18.6, 0, 14.4, 0.25, C('#c060ff'));
    solid(G, F, 0, 0, 5, 5);
  };
  B.pier = (G, F) => { // a pier out over the Pacific with its ferris wheel
    const toSea = -F.f;
    pier(G, F, F.f * 70, toSea * 230, 18, 5.5);
    wheel(G, F, toSea * 110, 5.5 + 30, 0, 26, 20, WHITE, C('#ff5ab0'));
    for (const x of [30, 160]) prism(G, F, 'facade_deco', rect(toSea * x, 9 * (x > 100 ? 1 : -1), 9, 6), 5.5, 11, C('#f6c6cf'), uvOf('deco'));
    beam(G, 'trim', F.P(F.f * 60, 5.5, -9), F.P(F.f * 60, 13, -9), 0.5, 0.5, WHITE); beam(G, 'trim', F.P(F.f * 60, 5.5, 9), F.P(F.f * 60, 13, 9), 0.5, 0.5, WHITE);
    beam(G, 'neon', F.P(F.f * 60, 13, -9), F.P(F.f * 60, 13, 9), 0.6, 1.4, C('#ffe14d'));
  };
  // Miami
  B.freedom = (G, F) => { // Mediterranean-revival tower with a lantern cupola
    prism(G, F, 'facade_deco', rect(0, 0, 16, 22), -2, 22, C('#f2e6cc'), uvOf('deco'));
    tpl(G, 'trim', ctx.T.hipRoof, ...F.P(0, 22, 0), F.rot, 34, 5, T3(C('#c45f3c')), 0.5, 46);
    prism(G, F, 'facade_deco', rect(0, 0, 8, 8), 22, 72, C('#f6ecd6'), uvOf('deco'));
    for (const y of [36, 52, 72]) prism(G, F, 'trim', rect(0, 0, 9, 9), y, y + 1.4, C('#e8dcc0'));
    cyl(G, F, 'trim', 0, 73.4, 0, 6.2, 8, C('#f6ecd6'));
    cyl(G, F, 'metal', 0, 81.4, 0, 6.2, 5, C('#c8a050'), TT.dome);
    cyl(G, F, 'trim', 0, 86, 0, 1.6, 5, C('#f6ecd6'));
    cyl(G, F, 'metal', 0, 91, 0, 1.8, 2, C('#c8a050'), TT.dome);
    solid(G, F, 0, 0, 16, 22);
  };
  B.atlantis = (G, F) => { // the blue glass slab with a square hole, a palm and a red spiral stair
    const blue = C('#5a8ac8'), fac = uvOf('tower'), d = 8, w = 36, H = 62, h0 = 34, h1 = 46, hw = 6;
    prism(G, F, 'facade_tower', rect(0, 0, d, w), -2, h0, blue, fac);
    prism(G, F, 'facade_tower', rect(0, 0, d, w), h1, H, blue, fac);
    prism(G, F, 'facade_tower', rect(0, -(w + hw) / 2, d, (w - hw) / 2), h0, h1, blue, fac);
    prism(G, F, 'facade_tower', rect(0, (w + hw) / 2, d, (w - hw) / 2), h0, h1, blue, fac);
    prism(G, F, 'trim', rect(0, 0, d, hw), h0 - 0.4, h0, C('#f4f0e8'));
    const p = F.P(0, h0, 0);
    tpl(G, 'props', ctx.T.royal, p[0], p[1], p[2], 0, 0.7, 0.72, [C('#9a8f84'), C('#4a9050'), C('#6a8a3a')], 0.4);
    for (let k = 0; k < 40; k++) { const a = k * 0.5, y = 2 + k * 1.4; const q = F.P(F.f * (d + 2.2) + Math.cos(a) * 1.8, y, -w + 5 + Math.sin(a) * 1.8); box(G, 'trim', q[0], q[1], q[2], F.rot + a, 0, 0, 0, 2.4, 0.2, 0.7, C('#d8382a'), null, { ao: false }); }
    beam(G, 'trim', F.P(F.f * (d + 2.2), 0, -w + 5), F.P(F.f * (d + 2.2), 58, -w + 5), 0.5, 0.5, C('#d8382a'));
    const yel = C('#ffd23a'); // the yellow triangle on the roof
    beam(G, 'trim', F.P(0, H, -10), F.P(0, H + 10, 0), 0.8, 1.2, yel); beam(G, 'trim', F.P(0, H + 10, 0), F.P(0, H, 10), 0.8, 1.2, yel); beam(G, 'trim', F.P(0, H, -10), F.P(0, H, 10), 0.8, 1.2, yel);
    solid(G, F, 0, 0, d, w);
  };
  B.panorama = (G, F) => { // a slim 265 m glass tower
    const pts = [[-14, -24], [-14, 20], [-10, 24], [14, 24], [14, -20], [10, -24]];
    prism(G, F, 'facade_condo', offset(pts, 0, 0).map(([x, z]) => [x * 1.2, z * 1.1]), -2, 12, C('#e8eef0'), uvOf('condo'));
    prism(G, F, 'facade_tower', pts, 12, 262, C('#9ec4dc'), uvOf('tower'));
    prism(G, F, 'trim', pts.map(([x, z]) => [x * 0.9, z * 0.9]), 262, 268, WHITE);
    beam(G, 'neon', F.P(F.f * 14.2, 262, -20), F.P(F.f * 14.2, 262, 20), 0.2, 0.3, C('#2ff3ff'));
    solid(G, F, 0, 0, 17, 27);
  };
  B.miamitower = (G, F) => { // the stepped half-moon crown that glows a new colour every night
    prism(G, F, 'facade_tower', rect(0, 0, 17, 26), -2, 150, C('#e4e8ee'), uvOf('tower'));
    const cols = [C('#2ff3ff'), C('#ff3d9a'), C('#b45cff')];
    [[17, 150, 162], [13, 162, 174], [9, 174, 186]].forEach(([r, y0, y1], i) => {
      // a half-moon tier whose flat side faces away from the road
      const pts = Array.from({ length: 17 }, (_, k) => { const a = (k / 16) * Math.PI; return [-F.f * 17 + F.f * Math.sin(a) * r * 1.6, -Math.cos(a) * r]; });
      prism(G, F, 'facade_tower', pts, y0, y1, C('#eef0f4'), uvOf('tower'));
      prism(G, F, 'neon', pts.map(([x, z]) => [x + F.f * 0.25, z * 1.015]), y1 - 1.0, y1 - 0.2, cols[i], null, false);
    });
    solid(G, F, 0, 0, 17, 26);
  };
  B.colony = (G, F) => { // a three-storey deco hotel with its blue neon name
    const d = 9, w = 18;
    prism(G, F, 'facade_deco', rect(0, 0, d, w), -2, 11, C('#f8f4ec'), uvOf('deco'));
    prism(G, F, 'trim', rect(F.f * (d + 1.2), 0, 1.2, w - 2), 3.0, 3.3, C('#f4f0e8'));
    prism(G, F, 'trim', rect(F.f * (d + 0.3), 0, 0.3, 1.6), 0, 16, C('#f8f4ec'));
    word(G, F, 'neon', 'COLONY', F.f * (d + 2.5), 3.6, 0, 1.9, 0.5, 0.22, 0.22, C('#3aa8ff'));
    beam(G, 'neon', F.P(F.f * (d + 0.7), 4, -0.6), F.P(F.f * (d + 0.7), 15, -0.6), 0.12, 0.12, C('#3aa8ff'));
    beam(G, 'neon', F.P(F.f * (d + 0.7), 4, 0.6), F.P(F.f * (d + 0.7), 15, 0.6), 0.12, 0.12, C('#3aa8ff'));
    solid(G, F, 0, 0, d, w);
  };
  B.lifeguard = (G, F) => { // a row of rainbow lifeguard towers on the sand
    const sets = [[C('#ff5a8a'), C('#ffd23a'), C('#3ac8e8')], [C('#5ec8c0'), C('#ff8fab'), C('#ffe14d')], [C('#b45cff'), C('#ffb057'), C('#5ae08a')]];
    for (let i = 0; i < 3; i++) { const p = F.P(0, 0, (i - 1) * 40); tpl(G, 'trim', ctx.T.hut, p[0], W.heightAt(p[0], p[2]), p[2], F.rot + (F.f > 0 ? Math.PI / 2 : -Math.PI / 2), 1.5, 1.5, sets[i], 0); }
  };
  // Chicago
  B.willis = (G, F) => { // nine bundled black tubes of different heights, two white antennas
    const fl = 3.9, t = 11.5, hts = [[66, 108, 90], [50, 108, 90], [50, 90, 66]], fac = uvOf('tower'), dark = C('#2a2e34');
    prism(G, F, 'trim', rect(0, 0, 38, 38), -2, 0.4, C('#7a7c80'));
    for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) {
      const cx = (i - 1) * 2 * t, cz = (j - 1) * 2 * t, H = hts[i][j] * fl;
      prism(G, F, 'facade_tower', rect(cx, cz, t, t), 0, H, dark, fac, true, 'trim', C('#3a3e44'));
      for (const y of [29 * fl, 66 * fl, 88 * fl, 104 * fl]) if (y < H - 2) prism(G, F, 'trim', rect(cx, cz, t + 0.15, t + 0.15), y, y + 2 * fl, C('#1a1c20'), null, false);
    }
    for (const z of [-5, 5]) { beam(G, 'trim', F.P(0, 108 * fl, z), F.P(0, 108 * fl + 90, z), 1.6, 1.6, WHITE); cyl(G, F, 'neon', 0, 108 * fl + 90, z, 0.9, 1.2, RED); }
    solid(G, F, 0, 0, 35, 35);
  };
  B.bean = (G, F) => { // a mirror-polished bean over a granite plaza
    prism(G, F, 'trim', rect(0, 0, 40, 40), -1, 0.3, C('#cfc8bb'));
    const g = new THREE.SphereGeometry(1, 64, 32), pa = g.attributes.position;
    for (let i = 0; i < pa.count; i++) {
      let x = pa.getX(i), y = pa.getY(i), z = pa.getZ(i);
      x *= 10; z *= 6.5; y = y * 5 + 5;
      const u = Math.min(1, (x * x) / 64 + (z * z) / 30); // the arch you can walk under
      if (y < 3.6) y = Math.max(0, y) + (1 - u) * 3.2 * (1 - y / 3.6);
      pa.setXYZ(i, x, y, z);
    }
    g.computeVertexNormals();
    const t = bake([[g, 0, 0]]), p = F.P(0, 0.3, 0);
    tpl(G, 'chrome', t, p[0], p[1], p[2], F.rot + Math.PI / 2, 1, 1, T3(C('#f2f4f6')));
    solid(G, F, 0, 0, 7, 10);
  };
  B.buckingham = (G, F) => { // tiered pink-granite fountain in Grant Park
    const pink = C('#d8b4a4');
    cyl(G, F, 'trim', 0, -0.5, 0, 46, 1.2, pink); cyl(G, F, 'pool', 0, 0.55, 0, 44.5, 0.1, WHITE);
    for (const [r, y, h] of [[20, 0.6, 3.5], [13, 4.1, 3.2], [7.5, 7.3, 3.0]]) { cyl(G, F, 'trim', 0, y, 0, r, h, pink); cyl(G, F, 'pool', 0, y + h, 0, r - 1, 0.08, WHITE); }
    cyl(G, F, 'trim', 0, 10.3, 0, 2.2, 3, pink);
    cyl(G, F, 'rail', 0, 13, 0, 1.6, 24, WHITE, TT.cone); // the centre jet
    for (let i = 0; i < 4; i++) { const a = i * Math.PI / 2 + Math.PI / 4; cyl(G, F, 'metal', Math.cos(a) * 30, 0.6, Math.sin(a) * 30, 2.2, 2.6, C('#4a6a5a'), TT.ball); }
  };
  B.hancock = (G, F) => { // tapering black tower with X-bracing and twin antennas
    const H = 344, bot = rect(0, 0, 25, 40), top = rect(0, 0, 15, 24), fac = uvOf('tower'), dark = C('#24282e');
    loft(G, F, 'facade_tower', bot, top, 0, H, dark, fac);
    prism(G, F, 'trim', top, H, H + 4, C('#1a1c20'));
    const lerpP = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
    for (let side = 0; side < 4; side++) {
      const b0 = bot[side], b1 = bot[(side + 1) % 4], t0 = top[side], t1 = top[(side + 1) % 4];
      const n = 5;
      for (let k = 0; k < n; k++) {
        const ya = (k / n) * H, yb = ((k + 1) / n) * H, ta = k / n, tb = (k + 1) / n;
        const A0 = lerpP(b0, t0, ta), A1 = lerpP(b1, t1, ta), B0 = lerpP(b0, t0, tb), B1 = lerpP(b1, t1, tb);
        const out = (p, y) => F.P(p[0] * 1.012, y, p[1] * 1.012);
        beam(G, 'trim', out(A0, ya), out(B1, yb), 1.4, 1.0, C('#14161a'));
        beam(G, 'trim', out(A1, ya), out(B0, yb), 1.4, 1.0, C('#14161a'));
        beam(G, 'trim', out(B0, yb), out(B1, yb), 1.2, 1.4, C('#14161a'));
      }
    }
    for (const z of [-7, 7]) { beam(G, 'trim', F.P(0, H + 4, z), F.P(0, H + 100, z), 1.2, 1.2, WHITE); cyl(G, F, 'neon', 0, H + 100, z, 0.7, 1, RED); }
    solid(G, F, 0, 0, 25, 40);
  };
  B.marina = (G, F) => { // the twin corn-cob towers: spiral parking below, scalloped balconies above
    const petal = (() => {
      const s = new THREE.Shape(), n = 16, R = 16;
      for (let i = 0; i <= n * 6; i++) { const a = (i / (n * 6)) * Math.PI * 2, rr = R - 2.4 * Math.pow(Math.abs(Math.cos((a * n) / 2)), 0.6); const x = Math.cos(a) * rr, y = Math.sin(a) * rr; i ? s.lineTo(x, y) : s.moveTo(x, y); }
      const g = new THREE.ExtrudeGeometry(s, { depth: 0.35, bevelEnabled: false, curveSegments: 2 }); g.rotateX(-Math.PI / 2);
      return bake([[g, 0, 0]]);
    })();
    for (const z of [-22, 22]) {
      cyl(G, F, 'trim', 0, -1, z, 9, 180, C('#d8d4cc'));
      for (let k = 0; k < 19; k++) cyl(G, F, 'trim', 0, k * 2.9, z, 14.5, 0.4, C('#cfc8bb'));
      for (let k = 0; k < 40; k++) {
        const y = 56 + k * 3.0, p = F.P(0, y, z);
        tpl(G, 'trim', petal, p[0], p[1], p[2], F.rot, 1, 1, T3(C('#ece8e0')));
        cyl(G, F, 'glass', 0, y + 0.35, z, 12.8, 2.6, WHITE);
      }
      cyl(G, F, 'trim', 0, 176, z, 16, 1.2, C('#ece8e0'));
    }
    solid(G, F, 0, -22, 16, 16); solid(G, F, 0, 22, 16, 16);
  };
  B.wrigley = (G, F) => { // white terra-cotta block with its clock tower
    const wc = C('#f6f4ee'), fac = uvOf('condo');
    prism(G, F, 'facade_condo', rect(0, 0, 18, 26), -2, 58, wc, fac);
    prism(G, F, 'facade_condo', rect(F.f * 6, -8, 9, 9), 58, 92, wc, fac);
    for (const [y, s] of [[92, 8], [100, 6.6], [108, 5]]) prism(G, F, 'trim', rect(F.f * 6, -8, s, s), y, y + 8, wc);
    cyl(G, F, 'trim', F.f * 6, 116, -8, 3.4, 6, wc); cyl(G, F, 'metal', F.f * 6, 122, -8, 3.6, 4, C('#c8b070'), TT.dome);
    const ck = F.P(F.f * 15.2, 96, -8); // clock faces
    box(G, 'neon', ck[0], ck[1], ck[2], F.rot, 0, 0, 0, 0.1, 5.5, 5.5, C('#fff4d8'), null, { ao: false });
    beam(G, 'trim', F.P(F.f * 15.4, 98.75, -8), F.P(F.f * 15.4, 100.8, -8), 0.2, 0.3, BLACK); beam(G, 'trim', F.P(F.f * 15.4, 98.75, -8), F.P(F.f * 15.4, 98.75, -9.6), 0.2, 0.3, BLACK);
    solid(G, F, 0, 0, 18, 26);
  };
  B.navypier = (G, F) => { // a long pier into Lake Michigan with the big wheel and the ballroom dome
    const toSea = -F.f;
    pier(G, F, F.f * 40, toSea * 360, 40, 3.2);
    wheel(G, F, toSea * 80, 3.2 + 36, 0, 30, 24, C('#f4f0e8'), C('#ff5a5a'));
    prism(G, F, 'facade_deco', rect(toSea * 180, 0, 60, 16), 3.2, 14, C('#e6d6b8'), uvOf('deco'));
    cyl(G, F, 'trim', toSea * 330, 3.2, 0, 22, 12, C('#e6d6b8'));
    cyl(G, F, 'metal', toSea * 330, 15.2, 0, 22, 10, C('#4a7a6a'), TT.dome);
  };
  // New York
  B.esb = (G, F) => { // limestone setbacks, the mooring mast and the lit top
    const fac = uvOf('condo'), ls = LIME;
    prism(G, F, 'facade_condo', rect(0, 0, 28, 46), -2, 25, ls, fac);
    prism(G, F, 'facade_condo', rect(0, 0, 22, 34), 25, 80, ls, fac);
    prism(G, F, 'facade_condo', rect(0, 0, 18, 26), 80, 270, ls, fac);
    for (let k = -3; k <= 3; k++) beam(G, 'trim', F.P(F.f * 18.3, 80, k * 3.6), F.P(F.f * 18.3, 270, k * 3.6), 0.6, 0.6, C('#e0d8c8')); // vertical piers
    for (const [s1, s2, y0, y1] of [[14, 20, 270, 290], [11, 15, 290, 310], [8, 10, 310, 320]]) prism(G, F, 'facade_condo', rect(0, 0, s1, s2), y0, y1, ls, fac);
    prism(G, F, 'neon', rect(0, 0, 8.3, 10.3), 316, 318.5, C('#f4f0ff'), null, false);
    cyl(G, F, 'trim', 0, 320, 0, 6, 22, C('#d8d0c0'));
    cyl(G, F, 'neon', 0, 334, 0, 6.3, 2, C('#7fb8ff'));
    cyl(G, F, 'metal', 0, 342, 0, 4, 18, STEEL, TT.cone);
    beam(G, 'trim', F.P(0, 358, 0), F.P(0, 443, 0), 0.8, 0.8, C('#b8bcc4'));
    cyl(G, F, 'neon', 0, 443, 0, 0.7, 1.2, RED);
    solid(G, F, 0, 0, 28, 46);
  };
  B.chrysler = (G, F) => { // white-brick shaft under seven stainless sunburst arches and a needle spire
    const fac = uvOf('condo'), wc = C('#e8e6e0'), chrome = C('#eef0f2');
    prism(G, F, 'facade_condo', rect(0, 0, 26, 30), -2, 60, wc, fac);
    prism(G, F, 'facade_condo', rect(0, 0, 21, 21), 60, 230, wc, fac);
    for (let k = 0; k < 7; k++) {
      const s = 19 - k * 2.6, y0 = 230 + k * 7, r = s * 0.92;
      prism(G, F, 'chrome', rect(0, 0, s, s), y0, y0 + 2.2, chrome);
      for (let face = 0; face < 4; face++) { // an arch on each face, with triangular windows
        const a = face * Math.PI / 2, nx = Math.cos(a), nz = Math.sin(a);
        let prev = null;
        for (let i = 0; i <= 12; i++) {
          const t = Math.PI * (i / 12), u = Math.cos(t) * r, v = Math.sin(t) * 6.4;
          const p = F.P(nx * s - nz * u, y0 + 2.2 + v, nz * s + nx * u);
          if (prev) beam(G, 'chrome', prev, p, 0.9, 0.9, chrome);
          if (prev && i % 2 === 0) { const q = F.P(nx * (s + 0.05) - nz * u * 0.8, y0 + 2.2 + v * 0.55, nz * (s + 0.05) + nx * u * 0.8); beam(G, 'neon', q, [q[0], q[1] + 1.6, q[2]], 0.4, 0.4, C('#fff2c8')); }
          prev = p;
        }
      }
    }
    cyl(G, F, 'chrome', 0, 279, 0, 4, 40, chrome, TT.cone);
    solid(G, F, 0, 0, 26, 30);
  };
  B.wtc = (G, F) => { // the square base twisting into a rotated square: eight glass triangles
    prism(G, F, 'trim', rect(0, 0, 30.5, 30.5), -2, 56, C('#b8bcc0'));
    const H = 417, y0 = 56, b = 30.5, t = 20.5;
    const Bc = [[-b, -b], [-b, b], [b, b], [b, -b]], Tm = [[-t * 1.414, 0], [0, t * 1.414], [t * 1.414, 0], [0, -t * 1.414]];
    for (let i = 0; i < 4; i++) {
      const j = (i + 1) % 4;
      const a = F.P(Bc[i][0], y0, Bc[i][1]), bb = F.P(Bc[j][0], y0, Bc[j][1]), tm = F.P(Tm[i][0], H, Tm[i][1]), tn = F.P(Tm[j][0], H, Tm[j][1]);
      const out = (n, p) => { const ax = F.P(0, p[1] - F.y, 0); return n[0] * (p[0] - ax[0]) + n[2] * (p[2] - ax[2]) < 0 ? [-n[0], -n[1], -n[2]] : n; };
      const c1 = [(a[0] + bb[0] + tm[0]) / 3, (a[1] + bb[1] + tm[1]) / 3, (a[2] + bb[2] + tm[2]) / 3], c2 = [(bb[0] + tn[0] + tm[0]) / 3, (bb[1] + tn[1] + tm[1]) / 3, (bb[2] + tn[2] + tm[2]) / 3];
      quad(G, 'glass', a, bb, tm, tm, out(nrm(cross(sub(bb, a), sub(tm, a))), c1), null, WHITE);
      quad(G, 'glass', bb, tn, tm, tm, out(nrm(cross(sub(tn, bb), sub(tm, bb))), c2), null, WHITE);
      beam(G, 'trim', a, tm, 0.6, 0.6, C('#d8dce0')); beam(G, 'trim', bb, tm, 0.6, 0.6, C('#d8dce0'));
    }
    prism(G, F, 'trim', Tm, H, H + 3, C('#c8ccd0'));
    for (const y of [H + 3, H + 40, H + 80]) cyl(G, F, 'trim', 0, y, 0, 3.4, 1.2, STEEL);
    beam(G, 'trim', F.P(0, H + 3, 0), F.P(0, 541, 0), 2, 2, C('#e4e8ec'));
    cyl(G, F, 'neon', 0, 541, 0, 1.2, 2, C('#ffffff'));
    solid(G, F, 0, 0, 30.5, 30.5);
  };
  B.flatiron = (G, F) => { // the triangular wedge pointing at the corner
    const tip = [F.f * 26, 0], pts = [[-F.f * 18, -30], [-F.f * 18, 30], tip].map(([x, z]) => [x, z]);
    const ccw = F.f > 0 ? [pts[0], pts[2], pts[1]] : pts;
    prism(G, F, 'facade_condo', ccw, -2, 14, C('#c8b494'), uvOf('condo'));
    prism(G, F, 'facade_condo', ccw, 14, 84, C('#d8ccb4'), uvOf('condo'));
    prism(G, F, 'trim', ccw.map(([x, z]) => [x * 1.04, z * 1.04]), 84, 87, C('#c8bca0'));
    solid(G, F, -F.f * 2, 0, 18, 26);
  };
  const tsq = (G, F) => { // Times Square: towers wrapped in giant screens
    const fac = uvOf('tower');
    prism(G, F, 'facade_tower', rect(0, -10, 14, 14), -2, 120, C('#5a6470'), fac);
    prism(G, F, 'facade_condo', rect(-F.f * 4, 16, 10, 12), -2, 70, C('#8a7a6a'), uvOf('condo'));
    const scr = (lx, y, lz, w, h, cell) => { ctx.atlasQuad(G, 'billboard', F.x, F.y, F.z, F.rot, lx, y, lz, w, h, F.f, cell, 2); };
    for (const [y, h, cell] of [[8, 22, 0], [32, 16, 1], [50, 26, 2], [80, 18, 3]]) scr(F.f * 14.4, y, -10, 27, h, cell);
    for (const [y, h, cell] of [[6, 14, 3], [22, 20, 1], [44, 18, 0]]) scr(F.f * 6.2, y, 16, 23, h, cell);
    for (const y of [4, 30, 48, 76, 100]) beam(G, 'neon', F.P(F.f * 14.6, y, -24), F.P(F.f * 14.6, y, 4), 0.25, 0.4, [C('#ff3d9a'), C('#2ff3ff'), C('#ffe14d'), C('#3dff9a'), C('#b45cff')][(y / 4) % 5 | 0]);
    solid(G, F, 0, -10, 14, 14); solid(G, F, -F.f * 4, 16, 10, 12);
  };
  B.timessq = tsq; B.timessq2 = tsq;
  B.liberty = (G, F) => { // on her island: star fort, granite pedestal, copper figure, gold torch
    const green = C('#7ab8a0');
    cyl(G, F, 'trim', 0, -4, 0, 120, 5.5, C('#6f9a45'));
    prism(G, F, 'trim', circle(52, 11).map(([x, z], i) => i % 2 ? [x * 0.62, z * 0.62] : [x, z]), -4, 8, C('#b8ac98'));
    prism(G, F, 'trim', rect(0, 0, 20, 20), 8, 14, GRANITE);
    prism(G, F, 'trim', rect(0, 0, 14, 14), 14, 44, C('#b4a898'));
    prism(G, F, 'trim', rect(0, 0, 16, 16), 44, 47, C('#a89c8c'));
    prism(G, F, 'trim', rect(0, 0, 11, 11), 47, 55, C('#b4a898'));
    const p = F.P(0, 55, 0);
    tpl(G, 'trim', TT.cone, p[0], p[1], p[2], F.rot, 7, 30, T3(green));       // robe
    cyl(G, F, 'trim', 0, 72, 0, 3.6, 12, green);                               // torso
    const head = F.P(F.f * 0.6, 86, 0); tpl(G, 'trim', TT.ball, head[0], head[1], head[2], F.rot, 2.6, 3, T3(green));
    for (let k = 0; k < 7; k++) { const a = -1.2 + k * 0.4; beam(G, 'trim', F.P(0, 88, 0), F.P(Math.cos(a) * 5.5 * F.f, 88 + 1.2, Math.sin(a) * 5.5), 0.5, 0.5, green); }
    const sh = F.P(0, 82, -3.6), hand = F.P(F.f * 1, 100, -5.2);
    beam(G, 'trim', sh, hand, 1.6, 1.6, green);
    tpl(G, 'trim', TT.cone, hand[0], hand[1] - 4, hand[2], F.rot, 1.4, 4, T3(green));
    tpl(G, 'neon', TT.cone, hand[0], hand[1] + 0.2, hand[2], F.rot, 1.3, 3.4, T3(GOLD));
    const tab = F.P(F.f * 2, 70, 4.2); box(G, 'trim', tab[0], tab[1], tab[2], F.rot, 0, 0, 0, 1.2, 7, 4, green, null, { ao: false });
  };

  function build(G, L) {
    const fn = B[L.id];
    if (!fn) return;
    const far = L.id === 'hollywood' || L.id === 'griffith' || L.id === 'liberty' || L.id === 'pier' || L.id === 'navypier' || L.id === 'lifeguard';
    const onWater = L.id === 'liberty' || L.id === 'pier' || L.id === 'navypier'; // stand on the water line, not the seabed
    const gy = onWater ? 0 : far ? W.heightAt(L.x, L.z) : W.heightAt(L.x, L.z) + 0.05;
    fn(G, frame(L, gy));
  }
  return { build, beam };
}
