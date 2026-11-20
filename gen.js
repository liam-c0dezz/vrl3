// Geometry generation for terrain chunks and road segments (plants, props, the whole city).
// Runs in a Web Worker (gen-worker.js) so building the world never stalls the frame; it only
// produces typed arrays, which the main thread turns into meshes.
import { createWorld, mulberry32, clamp, lerp, sstep, smooth, K } from './world.js';

// Season shader categories, stored per vertex in aSea.x (aSea.y = a random 0..1).
export const S = { NONE: 0, DECID: 1, GROUND: 2, PALM: 3, EVER: 4, FLOWER: 5 };

// Facade textures tile 8 window bays × 8 floors; these are a bay's width and a floor's height.
export const FACADE = { deco: [3.0, 3.4], condo: [3.6, 3.2], tower: [1.6, 3.8], house: [3.0, 3.0] };
export const SIGN_WORDS = ['HOTEL', 'CAFE', 'MOTEL', 'BAR', 'SURF', 'TACOS', 'DELI', 'GELATO', 'BOOKS', 'RECORDS', 'LIQUOR', 'PHARMACY', 'DINER', 'SALON', 'BAKERY', 'SUSHI'];

export function createGen(THREE, seed, region) {
  const W = createWorld(seed, region);
  const { CA, SF, noise, road } = W;
  const { ROAD_HALF, ROAD_EDGE, FLAT, STEP, WATER, CHUNK, RES, SEG, BLOCK, SIDEWALK, SETBACK } = K;
  const M4 = new THREE.Matrix4();
  const col = (hex) => { const c = new THREE.Color(hex); return [c.r, c.g, c.b]; };
  const mix3 = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
  const mul3 = (a, f) => [a[0] * f, a[1] * f, a[2] * f];
  const pickOf = (r, arr) => arr[(r() * arr.length) | 0];

  // ---------------------------------------------------------------------------
  // Accumulators: one per material group, non-indexed triangles
  // ---------------------------------------------------------------------------
  class Acc {
    constructor() { this.p = []; this.n = []; this.u = []; this.c = []; this.s = []; }
    v(x, y, z, nx, ny, nz, u, v, c, st, sr) { this.p.push(x, y, z); this.n.push(nx, ny, nz); this.u.push(u, v); this.c.push(c[0], c[1], c[2]); this.s.push(st, sr); }
    out() { return { position: new Float32Array(this.p), normal: new Float32Array(this.n), uv: new Float32Array(this.u), color: new Float32Array(this.c), aSea: new Float32Array(this.s) }; }
  }
  class Groups {
    constructor(ox, oz) { this.ox = ox; this.oz = oz; this.m = {}; }
    g(name) { return this.m[name] || (this.m[name] = new Acc()); }
    out() {
      const groups = {}, transfer = [];
      for (const k in this.m) {
        if (!this.m[k].p.length) continue;
        const o = this.m[k].out(); groups[k] = o;
        for (const kk in o) transfer.push(o[kk].buffer);
      }
      return { groups, transfer };
    }
  }
  // A world-space quad (a,b,c,d) with an outward normal; the winding is fixed up automatically.
  function quad(G, name, a, b, c, d, n, uvs, color, sea = [0, 0], ao = null) {
    const A = G.g(name), ox = G.ox, oz = G.oz;
    let P = [a, b, c, d], U = uvs || [[0, 0], [0, 0], [0, 0], [0, 0]], AO = ao || [1, 1, 1, 1];
    const e1 = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], e2 = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
    const cx = e1[1] * e2[2] - e1[2] * e2[1], cy = e1[2] * e2[0] - e1[0] * e2[2], cz = e1[0] * e2[1] - e1[1] * e2[0];
    if (cx * n[0] + cy * n[1] + cz * n[2] < 0) { P = [a, d, c, b]; U = [U[0], U[3], U[2], U[1]]; AO = [AO[0], AO[3], AO[2], AO[1]]; }
    for (const i of [0, 1, 2, 0, 2, 3]) {
      const p = P[i], f = AO[i];
      A.v(p[0] - ox, p[1], p[2] - oz, n[0], n[1], n[2], U[i][0], U[i][1], f === 1 ? color : mul3(color, f), sea[0], sea[1]);
    }
  }
  // An oriented box. (cx,cy,cz) is the object's origin on the ground, rot its yaw;
  // (lx, ly, lz) the box's bottom-centre in object space, (sx, sy, sz) its size.
  // uv = [uPerMetre, vPerMetre, uOffset, vOffset] maps facade textures onto the sides.
  function box(G, name, cx, cy, cz, rot, lx, ly, lz, sx, sy, sz, color, uv = null, opts = {}) {
    const cs = Math.cos(rot), sn = Math.sin(rot);
    const W2 = (px, py, pz) => [cx + px * cs + pz * sn, cy + py, cz - px * sn + pz * cs];
    const N2 = (nx, nz) => [nx * cs + nz * sn, 0, -nx * sn + nz * cs];
    const x0 = lx - sx / 2, x1 = lx + sx / 2, z0 = lz - sz / 2, z1 = lz + sz / 2, y0 = ly, y1 = ly + sy;
    const sea = opts.sea || [0, 0];
    const topName = opts.top || name;
    const aoOn = opts.ao !== false && y0 < 0.6;
    // split tall walls so ambient occlusion only darkens the bottom couple of metres
    const ySplits = aoOn && y1 - y0 > 3.5 ? [y0, y0 + 2.5, y1] : [y0, y1];
    const aoAt = (y) => (aoOn ? 0.55 + 0.45 * sstep(0, 2.5, y) : 1);
    const sides = [
      { n: [1, 0], a: [x1, z0], b: [x1, z1], len: sz },
      { n: [-1, 0], a: [x0, z1], b: [x0, z0], len: sz },
      { n: [0, 1], a: [x1, z1], b: [x0, z1], len: sx },
      { n: [0, -1], a: [x0, z0], b: [x1, z0], len: sx },
    ];
    for (const f of sides) {
      if (opts.skip && opts.skip(f.n)) continue;
      const nn = N2(f.n[0], f.n[1]);
      for (let k = 0; k < ySplits.length - 1; k++) {
        const ya = ySplits[k], yb = ySplits[k + 1];
        const uvs = uv ? [[uv[2], ya * uv[1] + uv[3]], [f.len * uv[0] + uv[2], ya * uv[1] + uv[3]], [f.len * uv[0] + uv[2], yb * uv[1] + uv[3]], [uv[2], yb * uv[1] + uv[3]]] : null;
        quad(G, name, W2(f.a[0], ya, f.a[1]), W2(f.b[0], ya, f.b[1]), W2(f.b[0], yb, f.b[1]), W2(f.a[0], yb, f.a[1]), nn, uvs, color, sea,
          [aoAt(ya), aoAt(ya), aoAt(yb), aoAt(yb)]);
      }
    }
    if (!opts.noTop) quad(G, topName, W2(x0, y1, z0), W2(x1, y1, z0), W2(x1, y1, z1), W2(x0, y1, z1), [0, 1, 0], null, opts.topColor || color, sea);
  }

  // ---------------------------------------------------------------------------
  // Templates: THREE geometries baked into flat arrays
  // ---------------------------------------------------------------------------
  // parts: [geometry, colourSlot, seasonType, flatShaded?]
  function bake(parts) {
    const pos = [], nrm = [], uv = [], kind = [], sea = [];
    for (const [geo, k, st, flat] of parts) {
      const g = geo.index ? geo.toNonIndexed() : geo;
      if (flat || !g.attributes.normal) g.computeVertexNormals();
      pos.push(...g.attributes.position.array); nrm.push(...g.attributes.normal.array);
      const n = g.attributes.position.count;
      if (g.attributes.uv) uv.push(...g.attributes.uv.array); else for (let i = 0; i < n; i++) uv.push(0, 0);
      for (let i = 0; i < n; i++) { kind.push(k); sea.push(st || 0); }
    }
    return { pos: new Float32Array(pos), nrm: new Float32Array(nrm), uv: new Float32Array(uv), kind: new Uint8Array(kind), sea: new Uint8Array(sea), count: kind.length };
  }
  function tpl(G, name, t, x, y, z, rot, sx, sy, colors, rnd = 0.5, sz = sx) {
    const A = G.g(name), c = Math.cos(rot), s = Math.sin(rot), ox = G.ox, oz = G.oz;
    for (let v = 0; v < t.count; v++) {
      const px = t.pos[v * 3] * sx, py = t.pos[v * 3 + 1] * sy, pz = t.pos[v * 3 + 2] * sz;
      let nx = t.nrm[v * 3] / sx, ny = t.nrm[v * 3 + 1] / sy, nz = t.nrm[v * 3 + 2] / sz;
      const nl = Math.hypot(nx, ny, nz) || 1; nx /= nl; ny /= nl; nz /= nl;
      A.v(x + px * c + pz * s - ox, y + py, z - px * s + pz * c - oz, nx * c + nz * s, ny, -nx * s + nz * c,
        t.uv[v * 2], t.uv[v * 2 + 1], colors[t.kind[v]], t.sea[v], rnd);
    }
  }
  const ball = (r, sx = 1, sy = 1, sz = 1, x = 0, y = 0, z = 0, seg = 9) => new THREE.SphereGeometry(r, seg, Math.max(5, (seg * 0.6) | 0)).scale(sx, sy, sz).translate(x, y, z);
  const stick = (r0, r1, h, x = 0, y = 0, z = 0, seg = 8) => new THREE.CylinderGeometry(r1, r0, h, seg).translate(x, y + h / 2, z);
  // A palm frond: a V-folded blade that arches and droops along its length.
  function frondGeo(len, width, yaw, tilt, droop, ox, oy, oz) {
    const N = 5, pos = [];
    const dx = Math.sin(yaw) * Math.cos(tilt), dy = Math.sin(tilt), dz = Math.cos(yaw) * Math.cos(tilt);
    const px = Math.cos(yaw), pz = -Math.sin(yaw);
    const pts = [];
    for (let i = 0; i <= N; i++) {
      const t = i / N, w = width * Math.pow(Math.sin(Math.PI * Math.min(1, 0.12 + t * 0.95)), 0.8);
      const c = [ox + dx * len * t, oy + dy * len * t - droop * len * t * t, oz + dz * len * t];
      pts.push({ L: [c[0] + px * w, c[1] - w * 0.18, c[2] + pz * w], C: [c[0], c[1] + w * 0.12, c[2]], R: [c[0] - px * w, c[1] - w * 0.18, c[2] - pz * w] });
    }
    const tri = (a, b, c) => pos.push(...a, ...b, ...c);
    for (let i = 0; i < N; i++) {
      const p = pts[i], q = pts[i + 1];
      tri(p.L, p.C, q.C); tri(p.L, q.C, q.L); tri(p.C, p.R, q.R); tri(p.C, q.R, q.C);
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    return g;
  }
  function palm(height, n, len, width, lean, tiltMin, tiltMax, droop, opts = {}) {
    const parts = [];
    const segs = 6;
    const off = (t) => lean * t * t * height * 0.12;
    for (let i = 0; i < segs; i++) {
      const y0 = (i / segs) * height, h = height / segs;
      const r0 = lerp(opts.r0 || 0.3, opts.r1 || 0.18, i / segs), r1 = lerp(opts.r0 || 0.3, opts.r1 || 0.18, (i + 1) / segs);
      const g = new THREE.CylinderGeometry(r1, r0, h * 1.02, 10).translate(0, h / 2, 0);
      const a = Math.atan2(off((i + 1) / segs) - off(i / segs), h);
      g.applyMatrix4(M4.makeRotationZ(-a)).translate(off(i / segs), y0, 0);
      parts.push([g, 0, S.PALM]);
    }
    const tx = off(1);
    if (opts.shaft) parts.push([stick(0.27, 0.25, opts.shaft, tx, height), 2, S.EVER]);
    const top = height + (opts.shaft || 0);
    for (let k = 0; k < n; k++) {
      const yaw = (k / n) * Math.PI * 2 + (k % 2) * 0.25;
      const tilt = lerp(tiltMin, tiltMax, ((k * 0.618) % 1));
      parts.push([frondGeo(len * (0.85 + ((k * 0.37) % 0.3)), width, yaw, tilt, droop, tx, top, 0), 1, S.EVER, true]);
    }
    if (opts.nuts) for (let k = 0; k < 4; k++) parts.push([ball(0.16, 1, 1, 1, tx + Math.cos(k * 1.6) * 0.3, top - 0.25, Math.sin(k * 1.6) * 0.3, 8), 2, S.NONE]);
    if (opts.head) parts.push([ball(opts.head, 1, 1.2, 1, tx, top, 0, 10), 2, S.EVER]);
    return bake(parts);
  }

  const T = {};
  T.cyl = bake([[new THREE.CylinderGeometry(1, 1, 1, 18).translate(0, 0.5, 0), 0, S.NONE]]);
  T.cyl8 = bake([[new THREE.CylinderGeometry(1, 1, 1, 8).translate(0, 0.5, 0), 0, S.NONE]]);
  T.hipRoof = bake([[new THREE.ConeGeometry(0.7072, 1, 4, 1).rotateY(Math.PI / 4).translate(0, 0.5, 0), 0, S.NONE, true]]);
  T.post = bake([[new THREE.BoxGeometry(0.14, 1.0, 0.14).translate(0, 0.5, 0), 2, 0, true], [new THREE.BoxGeometry(0.15, 0.14, 0.15).translate(0, 0.86, 0), 1, 0, true]]);
  T.rock = bake([[new THREE.DodecahedronGeometry(1, 1).scale(1.3, 0.8, 1.1).translate(0, 0.25, 0), 2, S.NONE, true]]);
  T.shrub = bake([[ball(0.95, 1.3, 0.7, 1.3, 0, 0.3), 1, S.EVER], [ball(0.6, 1.2, 0.7, 1.2, 0.6, 0.55, 0.3), 1, S.EVER]]);
  {
    T.fanPalm = palm(13, 12, 3.0, 0.45, 1, 0.15, 0.6, 0.18, { head: 0.55, r0: 0.28, r1: 0.18 });
    T.datePalm = palm(6.5, 18, 4.2, 0.55, 0.4, -0.25, 0.55, 0.22, { head: 0.65, r0: 0.4, r1: 0.32 });
    T.oak = bake([[stick(0.34, 0.2, 2.4), 0, 0], [ball(2.4, 1.25, 0.8, 1.2, 0, 3.4), 1, S.DECID], [ball(1.7, 1.2, 0.85, 1, 1.8, 3.0, 0.6), 1, S.DECID], [ball(1.6, 1.2, 0.85, 1, -1.7, 2.9, -0.6), 1, S.DECID], [ball(1.3, 1.1, 0.8, 1.1, 0.2, 4.3, 1.1), 1, S.DECID]]);
    T.cypress = bake([
      [new THREE.CylinderGeometry(0.2, 0.35, 3.8, 7).applyMatrix4(M4.makeRotationZ(-0.28)).translate(0.5, 1.8, 0), 0, 0],
      [ball(2.9, 1, 0.3, 1, 1.4, 3.9, 0), 1, S.EVER], [ball(2.2, 1.1, 0.32, 0.9, 2.5, 4.7, 0.4), 1, S.EVER], [ball(1.9, 1, 0.34, 1, 0.1, 3.3, -0.6), 1, S.EVER],
    ]);
    T.euc = bake([[stick(0.3, 0.16, 11), 2, 0], [ball(1.7, 0.9, 1.7, 0.9, 0.3, 10.6), 1, S.EVER], [ball(1.4, 0.9, 1.5, 0.9, -0.9, 8.6, 0.5), 1, S.EVER], [ball(1.2, 0.9, 1.3, 0.9, 0.9, 7.4, -0.6), 1, S.EVER]]);
    T.yucca = bake((() => { const p = []; for (let k = 0; k < 11; k++) p.push([frondGeo(1.4, 0.12, k * 0.62, 0.9 - (k % 3) * 0.25, 0.1, 0, 0.1, 0), 1, S.EVER, true]); return p; })());
    T.sycamore = bake([[stick(0.35, 0.22, 4), 2, 0], [ball(2.6, 1.1, 1.0, 1.1, 0, 5.4), 1, S.DECID], [ball(1.9, 1.1, 0.9, 1.1, 1.6, 4.6, 0.8), 1, S.DECID], [ball(1.8, 1, 0.9, 1, -1.5, 4.8, -0.6), 1, S.DECID]]);
  }
  {
    T.royal = palm(14, 13, 4.2, 0.55, 0.15, 0.55, -0.25, 0.28, { shaft: 2.0, r0: 0.34, r1: 0.26 });
    T.coconut = palm(9, 15, 3.8, 0.5, 2.4, 0.35, -0.55, 0.38, { nuts: true, r0: 0.25, r1: 0.18 });
    T.banyan = bake([
      [stick(0.9, 0.6, 3.5), 0, 0],
      ...[0, 1, 2, 3, 4, 5].map((k) => [stick(0.08, 0.08, 4.2, Math.cos(k) * 3.5, 0, Math.sin(k) * 3.5, 5), 0, 0]),
      [ball(4.5, 1.5, 0.55, 1.5, 0, 5.6), 1, S.EVER], [ball(3.2, 1.4, 0.6, 1.4, 3.8, 5.0, 1.0), 1, S.EVER], [ball(3.0, 1.4, 0.6, 1.4, -3.6, 5.1, -1.2), 1, S.EVER], [ball(2.6, 1.3, 0.6, 1.3, 0.5, 6.8, 0.4), 1, S.EVER],
    ]);
    T.seagrape = bake([[ball(1.2, 1.4, 0.75, 1.3, 0, 0.6), 1, S.EVER], [ball(0.9, 1.3, 0.8, 1.2, 1.0, 0.8, 0.4), 1, S.EVER], [ball(0.8, 1.2, 0.8, 1.2, -0.8, 0.7, -0.5), 1, S.EVER]]);
    T.mangrove = bake([
      ...[0, 1, 2, 3, 4, 5, 6].map((k) => [new THREE.CylinderGeometry(0.05, 0.07, 1.6, 4).applyMatrix4(M4.makeRotationZ(0.45)).translate(0.4, 0.6, 0).applyMatrix4(M4.makeRotationY(k * 0.9)), 0, 0, true]),
      [stick(0.18, 0.14, 1.6, 0, 1.0), 0, 0], [ball(1.6, 1.4, 0.7, 1.4, 0, 2.6), 1, S.EVER], [ball(1.1, 1.3, 0.7, 1.3, 1.2, 2.3, 0.5), 1, S.EVER],
    ]);
    T.bougainvillea = bake([[ball(1.0, 1.4, 0.85, 1.2, 0, 0.75), 1, S.FLOWER], [ball(0.8, 1.2, 0.9, 1.1, 0.9, 0.7, 0.3), 1, S.FLOWER], [ball(0.7, 1.1, 0.9, 1.1, -0.8, 0.65, -0.3), 1, S.FLOWER]]);
    T.umbrella = bake([[stick(0.04, 0.04, 2.3), 0, 0], [new THREE.ConeGeometry(1.5, 0.55, 12, 1, true).translate(0, 2.35, 0), 1, 0, true], [new THREE.BoxGeometry(0.7, 0.12, 1.9).translate(0.9, 0.3, 0.2), 2, 0, true]]);
    T.hut = bake([
      ...[[-1, -1], [1, -1], [-1, 1], [1, 1]].map(([a, b]) => [new THREE.BoxGeometry(0.16, 1.8, 0.16).translate(a * 1.1, 0.9, b * 0.9), 0, 0, true]),
      [new THREE.BoxGeometry(2.6, 0.12, 2.2).translate(0, 1.85, 0), 0, 0, true],
      [new THREE.BoxGeometry(2.2, 1.9, 1.8).translate(0, 2.85, 0), 1, 0, true],
      [new THREE.BoxGeometry(2.8, 0.14, 2.4).applyMatrix4(M4.makeRotationX(0.15)).translate(0, 3.9, 0), 2, 0, true],
      [new THREE.BoxGeometry(0.9, 0.08, 3.0).applyMatrix4(M4.makeRotationX(-0.6)).translate(0, 1.0, -2.2), 0, 0, true],
      [new THREE.BoxGeometry(1.4, 1.0, 0.04).translate(0, 3.0, 0.92), 2, 0, true],
      [stick(0.03, 0.03, 2.2, 1.0, 3.9, 0.8), 0, 0], [new THREE.BoxGeometry(0.02, 0.5, 0.7).translate(1.0, 5.8, 1.15), 2, 0, true],
    ]);
  }

  // ---------------------------------------------------------------------------
  // Palettes (linear colours)
  // ---------------------------------------------------------------------------
  const DECO = ['#f6c6cf', '#bfe6dc', '#cdbfe8', '#ffd9b0', '#fff0c8', '#a8dcef', '#f7b2a0', '#f9e1e8'].map(col);
  const CONDO = ['#f4f0e6', '#e9e4da', '#fbe7d4', '#dfe8ea', '#f0e0e8', '#e8eef0'].map(col);
  const TOWER = ['#bcd2de', '#a8c0cc', '#c8d4dc', '#b4ccc0', '#d0d6e0', '#c8c0b4'].map(col);
  const HOUSE = ['#fff6ea', '#f8e6d0', '#e6f0e8', '#f8dcd4', '#e4e8f4', '#fdf0c8'].map(col);
  const ACCENT = ['#ff8fab', '#5ec8c0', '#ffb057', '#8f7ad8', '#4aa3d8', '#f25f5c', '#2a9d8f'].map(col);
  const NEON = ['#ff3d9a', '#2ff3ff', '#b45cff', '#ff6a3d', '#3dff9a', '#ffe14d'].map(col);
  const WHITE = col('#f4f0e8'), CONCRETE = col('#b9b3a8'), DARK = col('#26282c'), TERRA = col('#c45f3c'), METAL = col('#8a9096');
  const LAMP = col('#ffd9a0'), RED = col('#ff2a20'), GREEN = col('#2aff6a'), AMBER = col('#ffb020'), OFF = col('#1a1a1a');
  const SAND = col('#ecdcb0'), WETSAND = col('#cbb68c'), LAWN = col('#6f9a45'), LAWN2 = col('#5d8a3a'), PLAZA = col('#cfc8bb'), ASPHALT = col('#3a3c41'), WALK = col('#bdb6aa'), UNDER = col('#2f4a48'), MUD = col('#6a6448');
  const facadeUV = (style, r) => { const [cw, fh] = FACADE[style]; return [1 / (8 * cw), 1 / (8 * fh), r(), ((r() * 8) | 0) / 8]; };

  // ---------------------------------------------------------------------------
  // Buildings
  // ---------------------------------------------------------------------------
  // (x,y,z) ground origin, rot yaw, w = width along local z, d = depth along local x,
  // front = +1/-1: which local-x face looks onto the street.
  function sign(G, x, y, z, rot, lx, y0, lz, width, height, front, word) {
    const cs = Math.cos(rot), sn = Math.sin(rot);
    const P = (px, py, pz) => [x + px * cs + pz * sn, y + py, z - px * sn + pz * cs];
    const c = word % 4, rr = (word / 4) | 0, u0 = c / 4, u1 = (c + 1) / 4, v0 = 1 - (rr + 1) / 4, v1 = 1 - rr / 4;
    const n = [front * cs, 0, -front * sn];
    const zA = lz + front * width / 2, zB = lz - front * width / 2; // keep the text reading left-to-right
    quad(G, 'sign', P(lx, y0, zA), P(lx, y0, zB), P(lx, y0 + height, zB), P(lx, y0 + height, zA), n, [[u0, v0], [u1, v0], [u1, v1], [u0, v1]], WHITE);
  }
  function building(G, r, x, y, z, rot, w, d, kind, front, hMul = 1, hero = true) {
    const B = (name, lx, ly, lz, sx, sy, sz, color, uv, opts) => box(G, name, x, y, z, rot, lx, ly, lz, sx, sy, sz, color, uv, opts);
    const f = front;
    B('trim', 0, -2, 0, d + 0.4, 2.05, w + 0.4, CONCRETE, null, { ao: false }); // plinth below grade
    if (kind === 'deco') {
      const nf = 2 + ((r() * 3) | 0), FH = 3.4, H = nf * FH;
      const c = pickOf(r, DECO), acc = pickOf(r, ACCENT), neon = pickOf(r, NEON);
      B('facade_deco', 0, 0, 0, d, H, w, c, facadeUV('deco', r));
      if (!hero) { B('trim', 0, H, 0, d + 0.3, 0.8, w + 0.3, WHITE); return; }
      B('glass', f * (d / 2 + 0.03), 0.25, 0, 0.06, 2.7, w - 1.6, WHITE);
      B('trim', f * (d / 2 + 1.0), 3.0, 0, 2.0, 0.16, w - 0.4, acc);
      for (let k = 1; k < nf; k++) B('trim', f * (d / 2 + 0.32), k * FH + 2.65, 0, 0.64, 0.12, w * 0.94, WHITE);
      B('trim', 0, H, 0, d + 0.3, 0.8, w + 0.3, WHITE);
      if (r() < 0.75) { // the central fin with neon edges
        B('trim', f * (d / 2 + 0.25), 0, 0, 0.6, H + 3.4, 1.4, acc);
        B('neon', f * (d / 2 + 0.57), 0.8, -0.72, 0.05, H + 2.5, 0.06, neon);
        B('neon', f * (d / 2 + 0.57), 0.8, 0.72, 0.05, H + 2.5, 0.06, neon);
        B('trim', f * (d / 2 - 0.8), H + 0.8, 0, 2.4, 1.3, Math.min(5, w * 0.4), c);
        B('trim', f * (d / 2 - 0.8), H + 2.1, 0, 1.6, 0.9, Math.min(3, w * 0.25), WHITE);
      }
      B('neon', f * (d / 2 + 0.17), H + 0.82, 0, 0.05, 0.07, w + 0.3, neon);
      if (r() < 0.45) for (const zz of [-1, 1]) { // rounded corners
        const cs = Math.cos(rot), sn = Math.sin(rot), lx = f * (d / 2 - 1.6), lz = zz * (w / 2 - 1.6);
        tpl(G, 'trim', T.cyl, x + lx * cs + lz * sn, y, z - lx * sn + lz * cs, 0, 1.7, H + 0.8, [c, c, c]);
        tpl(G, 'neon', T.cyl, x + lx * cs + lz * sn, y + H + 0.6, z - lx * sn + lz * cs, 0, 1.75, 0.08, [neon, neon, neon]);
      }
      sign(G, x, y, z, rot, f * (d / 2 + 2.03), 3.25, 0, Math.min(w - 2.5, 6.5), 1.3, f, (r() * 16) | 0);
      for (let k = 0; k < 2; k++) B('trim', (r() - 0.5) * d * 0.5, H + 0.8, (r() - 0.5) * w * 0.5, 1.4, 0.9, 1.1, METAL);
    } else if (kind === 'condo') {
      const nf = Math.round((5 + ((r() * 10) | 0)) * hMul), FH = 3.2, H = nf * FH;
      const c = pickOf(r, CONDO), acc = pickOf(r, ACCENT);
      B('facade_condo', 0, 0, 0, d, H, w, c, facadeUV('condo', r));
      B('trim', 0, H, 0, d + 0.3, 1.0, w + 0.3, WHITE);
      if (hero) {
        B('glass', f * (d / 2 + 0.03), 0.2, 0, 0.06, 2.9, w - 2, WHITE);
        B('trim', f * (d / 2 + 1.3), 3.1, 0, 2.6, 0.2, Math.min(w - 2, 9), WHITE);
        for (let k = 1; k < nf; k++) {
          B('trim', f * (d / 2 + 0.75), k * FH - 0.12, 0, 1.5, 0.16, w - 1.2, WHITE, null, { ao: false });
          B('rail', f * (d / 2 + 1.47), k * FH + 0.04, 0, 0.05, 1.0, w - 1.2, WHITE, null, { ao: false });
        }
        if (r() < 0.6) B('trim', 0, 0, (r() < 0.5 ? -1 : 1) * (w / 2 + 0.06), d * 0.3, H + 0.8, 0.14, acc);
      }
      B('trim', (r() - 0.5) * d * 0.4, H + 1, (r() - 0.5) * w * 0.4, 3, 2.8, 3.5, WHITE);
      const cs = Math.cos(rot), sn = Math.sin(rot), tx = -f * d * 0.25, tz = w * 0.25;
      tpl(G, 'trim', T.cyl8, x + tx * cs + tz * sn, y + H + 1, z - tx * sn + tz * cs, 0, 1.1, 2.4, [METAL, METAL, METAL]);
    } else if (kind === 'tower') {
      const nf = Math.round((14 + ((r() * 34) | 0)) * hMul), FH = 3.8, H = nf * FH, P = 9;
      const tint = pickOf(r, TOWER), neon = pickOf(r, NEON), uv = facadeUV('tower', r);
      B('facade_condo', 0, 0, 0, d + 5, P, w + 5, CONCRETE, facadeUV('condo', r));
      if (hero) {
        B('glass', f * ((d + 5) / 2 + 0.03), 0.2, 0, 0.06, 4.0, w + 3, WHITE);
        B('trim', f * ((d + 5) / 2 + 1.6), 4.4, 0, 3.2, 0.25, w * 0.6, WHITE);
      }
      B('trim', 0, P, 0, d + 5.3, 0.6, w + 5.3, WHITE);
      const H1 = H * (0.62 + r() * 0.2), H2 = H - H1;
      B('facade_tower', 0, P, 0, d, H1, w, tint, uv, { ao: false });
      const s2 = 0.72 + r() * 0.12;
      B('trim', 0, P + H1, 0, d + 0.4, 0.5, w + 0.4, WHITE, null, { ao: false });
      B('facade_tower', 0, P + H1, 0, d * s2, H2, w * s2, tint, uv, { ao: false });
      if (hero) {
        const n = Math.max(2, Math.floor(w / 6));
        for (let i = 0; i <= n; i++) B('trim', f * (d / 2 + 0.15), P, -w / 2 + (i * w) / n, 0.3, H1, 0.35, WHITE, null, { ao: false });
      }
      const top = P + H, dd = d * s2, ww = w * s2;
      B('trim', 0, top, 0, dd + 0.4, 2.6, ww + 0.4, WHITE, null, { ao: false });
      B('neon', dd / 2 + 0.22, top + 2.5, 0, 0.06, 0.08, ww + 0.4, neon, null, { ao: false });
      B('neon', -dd / 2 - 0.22, top + 2.5, 0, 0.06, 0.08, ww + 0.4, neon, null, { ao: false });
      B('neon', 0, top + 2.5, ww / 2 + 0.22, dd + 0.4, 0.08, 0.06, neon, null, { ao: false });
      B('neon', 0, top + 2.5, -ww / 2 - 0.22, dd + 0.4, 0.08, 0.06, neon, null, { ao: false });
      if (r() < 0.6) { B('trim', 0, top + 2.6, 0, 0.35, 10 + r() * 14, 0.35, WHITE, null, { ao: false }); }
      B('neon', 0, top + 2.6 + (r() < 0.6 ? 18 : 0.3), 0, 0.5, 0.5, 0.5, RED, null, { ao: false });
    } else if (kind === 'house') {
      const nf = r() < 0.6 ? 1 : 2, FH = 3.0, H = nf * FH, c = pickOf(r, HOUSE), acc = pickOf(r, ACCENT);
      B('facade_house', 0, 0, 0, d, H, w, c, facadeUV('house', r));
      tpl(G, 'trim', T.hipRoof, x, y + H, z, rot, d * 1.15, 2.4, [TERRA, TERRA, TERRA], 0.5, w * 1.15);
      B('trim', f * (d / 2 + 0.03), 0, w * 0.22, 0.06, 2.4, 3.0, WHITE, null, { ao: false });
      B('trim', f * (d / 2 + 0.03), 0, -w * 0.22, 0.06, 2.2, 1.0, acc, null, { ao: false });
      B('trim', f * (d / 2 + 1.6), 0, w * 0.22, 3.2, 0.06, 3.0, PLAZA, null, { ao: false });
      if (r() < 0.65) {
        B('trim', -f * (d / 2 + 3.4), 0, 0, 4.6, 0.12, Math.min(9, w - 1), WHITE, null, { ao: false, noTop: true });
        B('pool', -f * (d / 2 + 3.4), 0.12, 0, 4.0, 0.02, Math.min(8.4, w - 1.6), WHITE, null, { ao: false });
      }
    } else if (kind === 'shop') {
      const H = 4.8, c = pickOf(r, DECO);
      B('facade_deco', 0, 0, 0, d, H, w, c, [0, 0, 0.02, 0.98]);
      B('trim', 0, H, 0, d + 0.3, 1.1, w + 0.3, WHITE);
      const units = Math.max(1, Math.round(w / 8)), uw = w / units;
      for (let i = 0; i < units; i++) {
        const uz = -w / 2 + uw * (i + 0.5);
        B('glass', f * (d / 2 + 0.03), 0.2, uz, 0.06, 2.9, uw - 0.8, WHITE);
        B('trim', f * (d / 2 + 0.9), 3.05, uz, 1.8, 0.12, uw - 0.6, pickOf(r, ACCENT));
        sign(G, x, y, z, rot, f * (d / 2 + 0.05), 3.6, uz, Math.min(uw - 1.2, 5.5), 1.05, f, (r() * 16) | 0);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Terrain chunks
  // ---------------------------------------------------------------------------
  const N1 = RES + 1, NB = RES + 3;
  const hBuf = new Float32Array(NB * NB), dBuf = new Float32Array(NB * NB);
  const _cq = W.Q(), _q2 = W.Q();
  const CAG = {
    goldA: col(0xe9b45c), goldB: col(0xd99c4a), chap: col(0x7d8248), chapB: col(0x66763f), green: col(0x9fb35a),
    rock: col(0xb98a6c), rockB: col(0x9c7460), sand: col(0xf0dcb0), wetSand: col(0xcdb48a), dirt: col(0xd8ae7c),
  };
  const crisp = (v, at, w = 0.04) => sstep(at - w, at + w, v);

  function caGround(x, z, h, ny, d) {
    const v = 0.5 + 0.5 * noise(x / 40, z / 40), v2 = 0.5 + 0.5 * noise(x / 9, z / 9);
    let g = mix3(CAG.goldA, CAG.goldB, clamp(v * 0.8 + v2 * 0.3, 0, 1));
    const chap = crisp(noise(x / 230 + 7, z / 230 - 3) + 0.3 * noise(x / 55, z / 55), 0.15, 0.08);
    g = mix3(g, mix3(CAG.chap, CAG.chapB, v2), chap);
    g = mix3(g, CAG.green, crisp(noise(x / 900 - 20, z / 900), 0.45, 0.1) * 0.5);
    let c = mix3(g, mix3(CAG.rock, CAG.rockB, v2), sstep(0.8, 0.68, ny));
    if (h < 3.2) c = mix3(c, h < 0.7 ? CAG.wetSand : CAG.sand, sstep(3.2, 2.4, h));
    if (d < FLAT + 3) c = mix3(c, CAG.dirt, sstep(FLAT + 3, FLAT + 1.5, d));
    return [c, h > 2.4 && ny > 0.68 ? S.GROUND : S.NONE];
  }
  function sfGround(x, z, h, d, lx, lz, city) {
    const v = 0.5 + 0.5 * noise(x / 30, z / 30);
    const u = (x - W.roadXAtZ(z)) * W.OCEAN_SIDE, c0 = W.coastDist(z);
    if (h < WATER - 0.2) return [mix3(UNDER, MUD, clamp(h + 3, 0, 1) * 0.5), S.NONE];
    if (h < 0.7) return [WETSAND, S.NONE];
    if (u > c0 - 70 && h < 1.9) return [mix3(SAND, WETSAND, sstep(1.2, 0.8, h) * 0.6), S.NONE];
    let c = mix3(LAWN, LAWN2, v), st = S.GROUND;
    if (city > 0) {
      const e = Math.min(lx, CHUNK - lx, lz, CHUNK - lz);
      const dist = W.districtAt(z);
      let k = null;
      if (e < 3.5) k = ASPHALT; else if (e < 6) k = WALK;
      else if (dist === 'downtown') k = mix3(PLAZA, WALK, v * 0.4);
      if (k) { c = mix3(c, k, city); if (city > 0.5) st = S.NONE; }
    }
    if (d < FLAT + 3) c = mix3(c, PLAZA, sstep(FLAT + 3, FLAT + 1.5, d));
    return [c, st];
  }

  function chunk(cx, cz) {
    const ox = cx * CHUNK, oz = cz * CHUNK, st = CHUNK / RES;
    W.ensureRoadZ(oz + CHUNK + K.CELL * 3);
    for (let j = 0; j < NB; j++) for (let i = 0; i < NB; i++) {
      hBuf[j * NB + i] = W.heightAt(ox + (i - 1) * st, oz + (j - 1) * st, _cq);
      dBuf[j * NB + i] = _cq.d;
    }
    const pos = new Float32Array(N1 * N1 * 3), nrm = new Float32Array(N1 * N1 * 3), cols = new Float32Array(N1 * N1 * 3), sea = new Float32Array(N1 * N1 * 2);
    const cityAt = (d) => sstep(44, 52, d);
    for (let j = 0; j < N1; j++) for (let i = 0; i < N1; i++) {
      const b = (j + 1) * NB + (i + 1), v = j * N1 + i, h = hBuf[b];
      pos[v * 3] = i * st; pos[v * 3 + 1] = h; pos[v * 3 + 2] = j * st;
      let nx = hBuf[b - 1] - hBuf[b + 1], ny = 2 * st, nz = hBuf[b - NB] - hBuf[b + NB];
      const nl = Math.hypot(nx, ny, nz); nx /= nl; ny /= nl; nz /= nl;
      nrm[v * 3] = nx; nrm[v * 3 + 1] = ny; nrm[v * 3 + 2] = nz;
      const x = ox + i * st, z = oz + j * st;
      const dz = W.districtAt(z), isCity = dz !== 'coast' && dz !== 'causeway';
      const [c, s] = CA && !isCity ? caGround(x, z, h, ny, dBuf[b]) : sfGround(x, z, h, dBuf[b], i * st, j * st, isCity ? cityAt(dBuf[b]) : 0);
      cols[v * 3] = c[0]; cols[v * 3 + 1] = c[1]; cols[v * 3 + 2] = c[2];
      sea[v * 2] = s; sea[v * 2 + 1] = 0.5 + 0.5 * noise(x / 13, z / 13);
    }
    const idx = new Uint32Array(RES * RES * 6);
    let k = 0;
    for (let j = 0; j < RES; j++) for (let i = 0; i < RES; i++) {
      const a = j * N1 + i, b = a + 1, cc = a + N1, dd = cc + 1;
      idx[k++] = a; idx[k++] = cc; idx[k++] = b; idx[k++] = b; idx[k++] = cc; idx[k++] = dd;
    }
    const G = new Groups(ox, oz);
    const rr = mulberry32((cx * 73856093) ^ (cz * 19349663) ^ seed);
    const sample = (lx, lz) => { const gi = clamp(Math.round(lx / st), 0, RES), gj = clamp(Math.round(lz / st), 0, RES); return (gj + 1) * NB + (gi + 1); };
    if (CA && W.districtAt(oz + CHUNK / 2) === 'coast') caPlants(G, rr, ox, oz, st, sample);
    else sfChunk(G, rr, cx, cz, ox, oz, st, sample);
    const { groups, transfer } = G.out();
    const terrain = { position: pos, normal: nrm, color: cols, aSea: sea, index: idx };
    transfer.push(pos.buffer, nrm.buffer, cols.buffer, sea.buffer, idx.buffer);
    return { msg: { type: 'chunk', cx, cz, ox, oz, terrain, groups }, transfer };
  }

  function caPlants(G, rr, ox, oz, st, sample) {
    for (let t = 0; t < 110; t++) {
      const lx = rr() * CHUNK, lz = rr() * CHUNK, x = ox + lx, z = oz + lz, b = sample(lx, lz);
      if (dBuf[b] < ROAD_EDGE + 4.5) continue;
      if (Math.abs(hBuf[b - 1] - hBuf[b + 1]) + Math.abs(hBuf[b - NB] - hBuf[b + NB]) > 2.4 * st) continue;
      const h = W.heightAt(x, z, _q2), d = dBuf[b], s = 0.75 + rr() * 0.6, rot = rr() * 6.283, rn = rr();
      const u = (x - W.roadXAtZ(z)) * W.OCEAN_SIDE;
      if (h < 3.4) continue;
      const chap = crisp(noise(x / 230 + 7, z / 230 - 3) + 0.3 * noise(x / 55, z / 55), 0.15);
      const euc = sstep(0.35, 0.6, noise(x / 420 - 30, z / 420 + 12));
      const coastal = sstep(W.coastDist(z) - 110, W.coastDist(z) - 30, u);
      const k = rr();
      const C = (a, b) => mix3(col(a), col(b), rr());
      if (coastal > 0.4 && k < 0.3) { tpl(G, 'props', T.cypress, x, h - 0.2, z, rot, s * 1.1, s, [col(0x5a4038), C(0x2f5f55, 0x3c6e5c), C0], rn); continue; }
      if (euc > 0.3 && k < 0.6) { tpl(G, 'props', T.euc, x, h - 0.2, z, rot, s, s * (0.9 + rr() * 0.4), [C0, C(0x7fa090, 0x94b098), col(0xe8dccb)], rn); continue; }
      if (d < 70 && rr() < 0.012) { tpl(G, 'props', rr() < 0.6 ? T.fanPalm : T.datePalm, x, h - 0.2, z, rot, s, s, [col(0x7a5444), C(0x3f7a4a, 0x4f8a50), col(0x5a3f30)], rn); continue; }
      if (rr() > 0.08 + chap * 0.6) continue;
      if (k < 0.55) tpl(G, 'props', T.shrub, x, h, z, rot, s * 1.2, s, [C0, C(0x5f7a3f, 0x7a8a48), C0], rn);
      else if (k < 0.72) tpl(G, 'props', T.yucca, x, h, z, rot, s * 1.2, s * 1.2, [C0, C(0x7fa07a, 0x9ab48a), C0], rn);
      else if (k < 0.86) tpl(G, 'props', T.oak, x, h - 0.2, z, rot, s, s, [col(0x4a352c), C(0x3f6a40, 0x2f5f48), C0], rn);
      else if (k < 0.95) tpl(G, 'props', T.sycamore, x, h - 0.2, z, rot, s, s, [C0, C(0x6f9a48, 0x88a850), col(0xe0d8c8)], rn);
      else tpl(G, 'props', T.rock, x, h, z, rot, s * 1.3, s, [C0, C0, col(0xb98a6c)], rn);
    }
  }
  const C0 = [0, 0, 0];

  // South Florida: beach, mangroves, parks, and city blocks on a street grid away from the corridor.
  function sfChunk(G, rr, cx, cz, ox, oz, st, sample) {
    const zc = oz + CHUNK / 2, dist = W.districtAt(zc);
    const C = (a, b) => mix3(col(a), col(b), rr());
    const palmC = () => CA ? [col(0x7a5444), C(0x3f7a4a, 0x4f8a50), col(0x5a3f30)] : [col(0x9a8f84), C(0x3f8a4a, 0x55a058), col(0x6a8a3a)];
    const cocoC = () => [col(0x8a6a50), C(0x4a8a3a, 0x63a048), col(0x6a4a2a)];
    const STREET_PALM = CA ? T.fanPalm : T.royal, BEACH_PALM = CA ? T.fanPalm : T.coconut;
    // shoreline & beach dressing
    for (let t = 0; t < 70; t++) {
      const lx = rr() * CHUNK, lz = rr() * CHUNK, x = ox + lx, z = oz + lz, b = sample(lx, lz);
      const h = hBuf[b], d = dBuf[b];
      if (d < ROAD_EDGE + 6) continue;
      const u = (x - W.roadXAtZ(z)) * W.OCEAN_SIDE, c0 = W.coastDist(z);
      if (SF && h > -0.6 && h < 0.7 && rr() < 0.5) { tpl(G, 'props', T.mangrove, x, h, z, rr() * 6, 0.8 + rr() * 0.5, 0.8 + rr() * 0.4, [col(0x5a4a3a), C(0x2f5a3a, 0x3f6a40), C0], rr()); continue; }
      if (u > c0 - 70 && h > 0.7 && h < 1.9) { // the beach
        const k = rr();
        if (k < 0.08) tpl(G, 'props', BEACH_PALM, x, h - 0.1, z, rr() * 6, 0.9 + rr() * 0.3, 0.9 + rr() * 0.3, CA ? palmC() : cocoC(), rr());
        else if (k < 0.16 && u < c0 - 15) tpl(G, 'props', T.seagrape, x, h, z, rr() * 6, 1 + rr() * 0.4, 1, [C0, C(0x4a7a3a, 0x5f8a40), C0], rr());
        else if (k < 0.3 && u > c0 - 50) tpl(G, 'trim', T.umbrella, x, h, z, rr() * 6, 1, 1, [WHITE, pickOf(rr, ACCENT), pickOf(rr, DECO)], 0);
      }
    }
    if (rr() < 0.3) { // a lifeguard hut
      const lx = 10 + rr() * 44, lz = 10 + rr() * 44, x = ox + lx, z = oz + lz, b = sample(lx, lz), h = hBuf[b];
      const u = (x - W.roadXAtZ(z)) * W.OCEAN_SIDE, c0 = W.coastDist(z);
      if (u > c0 - 45 && u < c0 - 8 && h > 0.6 && h < 1.9 && dBuf[b] > 15) {
        tpl(G, 'trim', T.hut, x, h, z, W.OCEAN_SIDE > 0 ? -Math.PI / 2 : Math.PI / 2, 1, 1, [WHITE, pickOf(rr, DECO), pickOf(rr, ACCENT)], 0);
      }
    }
    if (dist === 'causeway' || dist === 'coast') return;
    // city blocks: the chunk is a block; streets run along its edges
    const okAt = (lx, lz) => {
      const b = sample(lx, lz), h = hBuf[b], d = dBuf[b], x = ox + lx, z = oz + lz;
      const u = (x - W.roadXAtZ(z)) * W.OCEAN_SIDE;
      return h > 1.0 && d > 48 && u < W.coastDist(z) - 72;
    };
    // street trees and lamps along this block's sidewalks
    for (let e = 0; e < 4; e++) for (let t = 8; t < CHUNK - 4; t += 16) {
      const lx = e === 0 ? 4.6 : e === 1 ? CHUNK - 4.6 : t, lz = e === 2 ? 4.6 : e === 3 ? CHUNK - 4.6 : t;
      if (!okAt(lx, lz)) continue;
      const b = sample(lx, lz);
      if ((t / 16 + e) % 2 === 0) tpl(G, 'props', STREET_PALM, ox + lx, hBuf[b] - 0.1, oz + lz, rr() * 6, 0.85 + rr() * 0.2, 0.75 + rr() * 0.25, palmC(), rr());
      else if (rr() < 0.5) {
        box(G, 'trim', ox + lx, hBuf[b], oz + lz, 0, 0, 0, 0, 0.16, 6.5, 0.16, METAL, null, { ao: false });
        box(G, 'neon', ox + lx, hBuf[b], oz + lz, 0, 0, 6.5, 0, 0.5, 0.25, 0.5, LAMP, null, { ao: false });
      }
    }
    const beachy = dist === 'deco' || dist === 'beach';
    const park = noise(cx * 0.37 + 9.1, cz * 0.41 - 3.3) > 0.42 || beachy && noise(cx * 0.5, cz * 0.5) > 0.3;
    if (park) {
      for (let t = 0; t < 14; t++) {
        const lx = 8 + rr() * 48, lz = 8 + rr() * 48;
        if (!okAt(lx, lz)) continue;
        const b = sample(lx, lz), x = ox + lx, z = oz + lz, k = rr();
        if (k < 0.2) tpl(G, 'props', T.banyan, x, hBuf[b] - 0.2, z, rr() * 6, 0.8 + rr() * 0.3, 0.8 + rr() * 0.3, [col(0x6a5a4a), C(0x3a6a3a, 0x4a7a40), C0], rr());
        else if (k < 0.6) tpl(G, 'props', CA ? (rr() < 0.6 ? T.fanPalm : T.datePalm) : rr() < 0.5 ? T.royal : T.coconut, x, hBuf[b] - 0.1, z, rr() * 6, 0.9, 0.85 + rr() * 0.3, palmC(), rr());
        else tpl(G, 'props', T.bougainvillea, x, hBuf[b], z, rr() * 6, 1, 1, [C0, C(0x3f6a35, 0x4f7a3a), C0], rr());
      }
      return;
    }
    const lots = [];
    if (dist === 'downtown') {
      if (rr() < 0.5) lots.push([32, 32, 36, 36, 'tower']);
      else { lots.push([19, 32, 22, 40, 'tower']); lots.push([45, 32, 22, 40, rr() < 0.5 ? 'tower' : 'condo']); }
    } else if (beachy) {
      for (const [a, b] of [[19, 19], [45, 19], [19, 45], [45, 45]]) lots.push([a, b, 18, 18, rr() < 0.6 ? 'deco' : 'condo']);
    } else {
      for (const [a, b] of [[19, 19], [45, 19], [19, 45], [45, 45]]) lots.push([a, b, 13, 12, rr() < 0.82 ? 'house' : 'condo']);
    }
    for (const [lx, lz, w, d, kind] of lots) {
      if (!(okAt(lx - d / 2, lz - w / 2) && okAt(lx + d / 2, lz - w / 2) && okAt(lx - d / 2, lz + w / 2) && okAt(lx + d / 2, lz + w / 2))) continue;
      const b = sample(lx, lz), y = hBuf[b];
      const front = lx < CHUNK / 2 ? -1 : 1;
      const hm = kind === 'tower' ? 0.6 + 0.9 * sstep(-0.1, 0.6, noise(cx * 0.21 + 4, cz * 0.19)) : kind === 'condo' ? 0.6 : 1;
      building(G, rr, ox + lx, y, oz + lz, 0, w, d, kind, front, hm, kind !== 'tower' && kind !== 'condo');
      if (kind === 'house') {
        tpl(G, 'props', CA ? T.fanPalm : rr() < 0.5 ? T.coconut : T.royal, ox + lx + front * (d / 2 + 2), y, oz + lz + w * 0.45, rr() * 6, 0.8, 0.7 + rr() * 0.3, palmC(), rr());
        tpl(G, 'props', T.bougainvillea, ox + lx + front * (d / 2 + 1.2), y, oz + lz - w * 0.45, rr() * 6, 0.9, 0.9, [C0, C(0x3f6a35, 0x4f7a3a), C0], rr());
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Road segments: the road, sidewalks, the corridor's buildings and street furniture
  // ---------------------------------------------------------------------------
  function lotsForBlock(m, side) {
    W.ensureRoadIndex(Math.ceil(((m + 1) * BLOCK) / STEP) + 4); // layouts must not depend on how much road exists yet
    const r = mulberry32((Math.imul(m, 2654435761) ^ (side > 0 ? 0x9e37 : 0x7f4a) ^ seed) >>> 0);
    const out = [];
    let s = m * BLOCK + 9;
    const end = (m + 1) * BLOCK - 9;
    while (s < end - 7) {
      const p = W.roadPoint(s);
      const dist = W.districtAt(p.z);
      let kind, w, d, gap = 0.6;
      if (dist === 'downtown') { kind = r() < 0.55 ? 'tower' : 'condo'; w = kind === 'tower' ? 26 + r() * 10 : 18 + r() * 10; d = kind === 'tower' ? 22 + r() * 8 : 16 + r() * 6; }
      else if (dist === 'deco' || dist === 'beach') { kind = r() < (CA ? 0.55 : 0.8) ? 'deco' : 'shop'; w = kind === 'deco' ? 14 + r() * 8 : 24 + r() * 14; d = 14 + r() * 6; gap = 0.3; }
      else { const k = r(); kind = k < 0.55 ? 'house' : k < 0.8 ? 'shop' : 'condo'; w = kind === 'house' ? 12 + r() * 3 : kind === 'shop' ? 22 + r() * 16 : 18 + r() * 8; d = kind === 'house' ? 11 + r() * 2 : 15 + r() * 4; gap = kind === 'house' ? 5 + r() * 3 : 1.5; }
      w = Math.min(w, end - s);
      if (w < 7) break;
      out.push({ s: s + w / 2, w, d, kind, seed: (r() * 1e9) | 0 });
      s += w + gap;
    }
    return out;
  }

  function segment(k) {
    W.ensureRoadIndex((k + 1) * SEG + 60);
    const i0 = k * SEG, i1 = i0 + SEG, ox = road.xs[i0], oz = road.zs[i0];
    const G = new Groups(ox, oz);
    const lights = [];
    const s0 = i0 * STEP, s1 = i1 * STEP;
    // ---- the road surface
    {
      const A = G.g('road');
      const lats = [-ROAD_EDGE, -ROAD_HALF, ROAD_HALF, ROAD_EDGE];
      const us = [0, (ROAD_EDGE - ROAD_HALF) / (2 * ROAD_EDGE), 1 - (ROAD_EDGE - ROAD_HALF) / (2 * ROAD_EDGE), 1];
      const rows = [];
      for (let i = i0; i <= i1; i++) {
        const a = Math.max(i - 1, 0), b = Math.min(i + 1, road.nFinal - 1);
        let dx = road.xs[b] - road.xs[a], dz = road.zs[b] - road.zs[a];
        const l = Math.hypot(dx, dz); dx /= l; dz /= l;
        const city = [W.citySide(road.zs[i], -1), W.citySide(road.zs[i], 1)];
        rows.push(lats.map((lt, c) => {
          const flat = c === 1 || c === 2 || (c === 0 ? city[0] : city[1]);
          const dy = flat ? 0.03 : -0.13;
          return [road.xs[i] - dz * lt, road.ys[i] + dy, road.zs[i] + dx * lt, us[c], (i * STEP) / 16];
        }));
      }
      for (let i = 0; i < SEG; i++) for (let c = 0; c < 3; c++) {
        const p = [rows[i][c], rows[i][c + 1], rows[i + 1][c + 1], rows[i + 1][c]];
        for (const j of [0, 1, 3, 1, 2, 3]) A.v(p[j][0] - ox, p[j][1], p[j][2] - oz, 0, 1, 0, p[j][3], p[j][4], WHITE, 0, 0);
      }
    }
    if (CA) caSegmentProps(G, i0, i1);
    sfSegment(G, k, i0, i1, s0, s1, lights); // city furniture & buildings wherever a district is urban
    const { groups, transfer } = G.out();
    return { msg: { type: 'segment', k, ox, oz, groups, lights }, transfer };
  }

  function caSegmentProps(G, i0, i1) {
    for (let i = i0; i < i1; i++) {
      const s = i * STEP;
      if (W.citySide(road.zs[i], 1)) continue; // LA stretches get the full city treatment instead
      const town = sstep(0.25, 0.45, noise(s / 1600 + 31, 4.4));
      if (town > 0.5 && i % 15 === 0) {
        for (const side of [-1, 1]) {
          const p = W.roadPoint(s, side * (ROAD_EDGE + 3.2)), gy = W.heightAt(p.x, p.z);
          if (gy < 2 || Math.abs(gy - p.y) > 3) continue;
          const r = mulberry32(i * 31 + side)();
          tpl(G, 'props', T.fanPalm, p.x, gy - 0.2, p.z, r * 6, 0.9 + r * 0.25, 0.9 + r * 0.35, [col(0x7a5444), col(0x3f7a4a), col(0x5a3f30)], r);
        }
      } else if (i % 25 === 0) {
        const side = (i / 25) % 2 ? 1 : -1;
        const p = W.roadPoint(s, side * (ROAD_EDGE + 0.6));
        if (Math.abs(W.baseH(p.x, p.z) - p.y) > 2.5) continue;
        tpl(G, 'trim', T.post, p.x, p.y - 0.15, p.z, p.h, 1, 1, [C0, side > 0 ? col(0xe0533a) : WHITE, WHITE]);
      }
    }
  }

  function sfSegment(G, k, i0, i1, s0, s1, lights) {
    const RP = (s, lat) => W.roadPoint(s, lat);
    // ---- sidewalks (curb + slab), with gaps at cross streets
    for (const side of [-1, 1]) {
      for (let i = i0; i < i1; i++) {
        const sa = i * STEP, sb = sa + STEP;
        if (!W.citySide(road.zs[i], side)) continue;
        if (W.intersectionDist(sa + 1) < 5.5) continue;
        const a0 = RP(sa, side * ROAD_EDGE), b0 = RP(sb, side * ROAD_EDGE);
        const a1 = RP(sa, side * (ROAD_EDGE + SIDEWALK)), b1 = RP(sb, side * (ROAD_EDGE + SIDEWALK));
        const ya = a0.y + 0.17, yb = b0.y + 0.17;
        const uvA = sa / 1.5, uvB = sb / 1.5;
        quad(G, 'sidewalk', [a0.x, ya, a0.z], [b0.x, yb, b0.z], [b1.x, yb, b1.z], [a1.x, ya, a1.z], [0, 1, 0], [[0, uvA], [0, uvB], [SIDEWALK / 1.5, uvB], [SIDEWALK / 1.5, uvA]], WHITE);
        const nx = -(b0.z - a0.z), nz = b0.x - a0.x, nl = Math.hypot(nx, nz);
        quad(G, 'trim', [a0.x, a0.y + 0.02, a0.z], [b0.x, b0.y + 0.02, b0.z], [b0.x, yb, b0.z], [a0.x, ya, a0.z], [-side * nx / nl, 0, -side * nz / nl], null, CONCRETE);
        quad(G, 'trim', [a1.x, ya - 1.5, a1.z], [b1.x, yb - 1.5, b1.z], [b1.x, yb, b1.z], [a1.x, ya, a1.z], [side * nx / nl, 0, side * nz / nl], null, CONCRETE);
      }
    }
    // ---- intersections: cross streets, crosswalks, signals
    for (let m = Math.ceil(s0 / BLOCK); m * BLOCK < s1; m++) {
      const sb = m * BLOCK, pc = RP(sb, 0);
      const anyCity = W.citySide(pc.z, -1) || W.citySide(pc.z, 1);
      if (!anyCity) continue;
      for (const sc of [sb - 6.5, sb + 6.5]) { // zebra crosswalks
        for (let lt = -3.2; lt <= 3.2; lt += 0.9) {
          const a = RP(sc - 1.5, lt - 0.22), b = RP(sc + 1.5, lt - 0.22), c = RP(sc + 1.5, lt + 0.22), d = RP(sc - 1.5, lt + 0.22);
          quad(G, 'paint', [a.x, a.y + 0.045, a.z], [b.x, b.y + 0.045, b.z], [c.x, c.y + 0.045, c.z], [d.x, d.y + 0.045, d.z], [0, 1, 0], null, WHITE);
        }
      }
      { // stop lines
        for (const [sc, lo, hi] of [[sb - 8.6, 0.2, 3.5], [sb + 8.6, -3.5, -0.2]]) {
          const a = RP(sc - 0.25, lo), b = RP(sc + 0.25, lo), c = RP(sc + 0.25, hi), d = RP(sc - 0.25, hi);
          quad(G, 'paint', [a.x, a.y + 0.045, a.z], [b.x, b.y + 0.045, b.z], [c.x, c.y + 0.045, c.z], [d.x, d.y + 0.045, d.z], [0, 1, 0], null, WHITE);
        }
      }
      for (const side of [-1, 1]) {
        if (!W.citySide(pc.z, side)) continue;
        const a = RP(sb - 5.2, side * ROAD_EDGE), b = RP(sb + 5.2, side * ROAD_EDGE), c = RP(sb + 5.2, side * 60), d = RP(sb - 5.2, side * 60);
        quad(G, 'road2', [a.x, a.y + 0.02, a.z], [b.x, b.y + 0.02, b.z], [c.x, c.y - 0.1, c.z], [d.x, d.y - 0.1, d.z], [0, 1, 0], null, WHITE);
        // signal pole on the near-side corner, arm reaching over the lanes
        const sg = RP(sb - side * 7.4, side * (ROAD_EDGE + 0.8));
        box(G, 'trim', sg.x, sg.y + 0.17, sg.z, sg.h, 0, 0, 0, 0.22, 6.2, 0.22, DARK, null, { ao: false });
        box(G, 'trim', sg.x, sg.y + 0.17, sg.z, sg.h, side * 2.9, 5.9, 0, 5.8, 0.14, 0.14, DARK, null, { ao: false });
        const hd = RP(sb - side * 7.4, side * 1.8);
        box(G, 'trim', hd.x, hd.y + 0.17, hd.z, hd.h, 0, 4.6, 0, 0.4, 1.3, 0.4, col('#2c3a2c'), null, { ao: false });
        const lamp = (dy, c) => box(G, 'neon', hd.x, hd.y + 0.17, hd.z, hd.h, 0, 4.7 + dy, -side * 0.21, 0.24, 0.24, 0.04, c, null, { ao: false });
        lamp(0.82, OFF); lamp(0.42, OFF); lamp(0.02, GREEN);
      }
    }
    // ---- street furniture along the corridor
    for (let i = i0; i < i1; i++) {
      const s = i * STEP, zc = road.zs[i];
      const dist = W.districtAt(zc);
      for (const side of [-1, 1]) {
        const city = W.citySide(zc, side);
        if (city && W.intersectionDist(s) > 9) {
          if (i % 7 === 0) { // palms down both sidewalks
            const p = RP(s, side * (ROAD_EDGE + 2.5));
            const r = mulberry32(i * 131 + side * 7)();
            const isBeach = (dist === 'deco' || dist === 'beach') && side === W.OCEAN_LAT;
            const tp = CA ? T.fanPalm : isBeach ? T.coconut : T.royal;
            tpl(G, 'props', tp, p.x, p.y + 0.17, p.z, r * 6, 0.9 + r * 0.2, (CA ? 1.0 : 0.85) + r * 0.3,
              CA ? [col(0x7a5444), col(0x3f7a4a), col(0x5a3f30)] : isBeach ? [col(0x8a6a50), col(0x4f923f), col(0x6a4a2a)] : [col(0x9a8f84), col(0x4a9050), col(0x6a8a3a)], r);
            box(G, 'trim', p.x, p.y + 0.17, p.z, p.h, 0, -0.02, 0, 1.4, 0.06, 1.4, col('#5a4a3a'), null, { ao: false });
          }
          if ((i + (side > 0 ? 8 : 0)) % 16 === 0) { // streetlights, alternating sides
            const p = RP(s, side * (ROAD_EDGE + 0.7));
            box(G, 'trim', p.x, p.y + 0.17, p.z, p.h, 0, 0, 0, 0.18, 8.2, 0.18, METAL, null, { ao: false });
            box(G, 'trim', p.x, p.y + 0.17, p.z, p.h, side * 1.0, 7.95, 0, 2.1, 0.12, 0.14, METAL, null, { ao: false });
            const hp = RP(s, side * (ROAD_EDGE - 1.4));
            box(G, 'neon', hp.x, hp.y + 0.17, hp.z, hp.h, 0, 7.75, 0, 0.6, 0.18, 0.32, LAMP, null, { ao: false });
            lights.push(hp.x, hp.y + 7.6, hp.z);
          }
          if ((dist === 'deco' || dist === 'beach') && side === W.OCEAN_LAT && i % 2 === 0) { // low coral-stone seawall on the promenade
            const a = RP(s, side * (ROAD_EDGE + SIDEWALK + 0.25)), b = RP(s + 2 * STEP, side * (ROAD_EDGE + SIDEWALK + 0.25));
            const len = Math.hypot(b.x - a.x, b.z - a.z);
            box(G, 'trim', (a.x + b.x) / 2, a.y + 0.1, (a.z + b.z) / 2, a.h, 0, 0, 0, 0.5, 0.75, len + 0.02, col('#e8d8c0'), null, { ao: false });
          }
        }
        if (dist === 'causeway') {
          if (i % 2 === 0) { // jersey barriers
            const a = RP(s, side * (ROAD_EDGE + 0.25)), b = RP(s + 2 * STEP, side * (ROAD_EDGE + 0.25));
            const len = Math.hypot(b.x - a.x, b.z - a.z);
            box(G, 'trim', (a.x + b.x) / 2, a.y - 0.1, (a.z + b.z) / 2, a.h, 0, 0, 0, 0.55, 0.95, len + 0.02, CONCRETE, null, { ao: false });
          }
          if ((i + (side > 0 ? 10 : 0)) % 20 === 0) {
            const p = RP(s, side * (ROAD_EDGE + 0.25));
            box(G, 'trim', p.x, p.y + 0.85, p.z, p.h, 0, 0, 0, 0.16, 7.4, 0.16, METAL, null, { ao: false });
            const hp = RP(s, side * (ROAD_EDGE - 1.2));
            box(G, 'trim', p.x, p.y + 0.85, p.z, p.h, -side * 0.75, 7.2, 0, 1.6, 0.1, 0.12, METAL, null, { ao: false });
            box(G, 'neon', hp.x, hp.y + 0.85, hp.z, hp.h, 0, 7.0, 0, 0.55, 0.16, 0.3, LAMP, null, { ao: false });
            lights.push(hp.x, hp.y + 7.6, hp.z);
          }
          if (i % 15 === 0 && side > 0) { // bridge piers
            const y = road.ys[i];
            for (const lt of [-3, 3]) { const p = RP(s, lt); box(G, 'trim', p.x, -6, p.z, p.h, 0, 0, 0, 1.0, y + 5.7, 2.2, CONCRETE, null, { ao: false }); }
          }
        }
      }
    }
    // ---- corridor buildings, block by block
    for (let m = Math.floor((s0 - BLOCK) / BLOCK); m * BLOCK < s1 + BLOCK; m++) {
      if (m < 0) continue;
      for (const side of [-1, 1]) {
        for (const lot of lotsForBlock(m, side)) {
          if (lot.s < s0 || lot.s >= s1) continue;
          const pz = W.roadPoint(lot.s).z;
          if (!W.buildingSide(pz, side)) continue;
          const p = W.roadPoint(lot.s, side * (SETBACK + lot.d / 2));
          const u = (p.x - W.roadXAtZ(p.z)) * W.OCEAN_SIDE;
          if (u > W.coastDist(p.z) - 28 - lot.d / 2) continue;
          if (W.baseH(p.x, p.z) < 0.9) continue;
          const r = mulberry32(lot.seed);
          building(G, r, p.x, p.y + 0.17, p.z, p.h, lot.w, lot.d, lot.kind, side, 1, true);
          if (lot.kind === 'house') {
            const q = W.roadPoint(lot.s + lot.w / 2 + 2.5, side * (SETBACK + 3));
            tpl(G, 'props', CA ? T.fanPalm : r() < 0.5 ? T.coconut : T.royal, q.x, q.y, q.z, r() * 6, 0.85, 0.75 + r() * 0.3, CA ? [col(0x7a5444), col(0x3f7a4a), col(0x5a3f30)] : [col(0x9a8f84), col(0x4a9050), col(0x6a8a3a)], r());
            const q2 = W.roadPoint(lot.s - lot.w / 2 - 1.5, side * (SETBACK + 1.5));
            tpl(G, 'props', T.bougainvillea, q2.x, q2.y, q2.z, r() * 6, 1, 1, [C0, col(0x46703a), C0], r());
          }
        }
      }
    }
  }

  return { world: W, chunk, segment };
}
