// Shared world model (no rendering): noise, terrain heights, the endless road and its queries.
// Imported by the main thread (physics, camera, map) and by the generation worker (geometry),
// so both build the exact same world from the same seed.

export function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
export function makeNoise2D(rand) {
  const p = new Uint8Array(256);
  for (let i = 0; i < 256; i++) p[i] = i;
  for (let i = 255; i > 0; i--) { const j = (rand() * (i + 1)) | 0; const t = p[i]; p[i] = p[j]; p[j] = t; }
  const perm = new Uint8Array(512);
  for (let i = 0; i < 512; i++) perm[i] = p[i & 255];
  const gx = [1, -1, 1, -1, 1, -1, 0, 0], gy = [1, 1, -1, -1, 0, 0, 1, -1];
  const F2 = 0.5 * (Math.sqrt(3) - 1), G2 = (3 - Math.sqrt(3)) / 6;
  return function (xin, yin) {
    const s = (xin + yin) * F2;
    const i = Math.floor(xin + s), j = Math.floor(yin + s);
    const t = (i + j) * G2;
    const x0 = xin - (i - t), y0 = yin - (j - t);
    const i1 = x0 > y0 ? 1 : 0, j1 = x0 > y0 ? 0 : 1;
    const x1 = x0 - i1 + G2, y1 = y0 - j1 + G2, x2 = x0 - 1 + 2 * G2, y2 = y0 - 1 + 2 * G2;
    const ii = i & 255, jj = j & 255;
    let n = 0, tt;
    tt = 0.5 - x0 * x0 - y0 * y0;
    if (tt > 0) { const g = perm[ii + perm[jj]] & 7; tt *= tt; n += tt * tt * (gx[g] * x0 + gy[g] * y0); }
    tt = 0.5 - x1 * x1 - y1 * y1;
    if (tt > 0) { const g = perm[ii + i1 + perm[jj + j1]] & 7; tt *= tt; n += tt * tt * (gx[g] * x1 + gy[g] * y1); }
    tt = 0.5 - x2 * x2 - y2 * y2;
    if (tt > 0) { const g = perm[ii + 1 + perm[jj + 1]] & 7; tt *= tt; n += tt * tt * (gx[g] * x2 + gy[g] * y2); }
    return 70 * n;
  };
}
export const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
export const lerp = (a, b, t) => a + (b - a) * t;
export const smooth = (t) => { t = clamp(t, 0, 1); return t * t * (3 - 2 * t); };
export const sstep = (a, b, x) => smooth((x - a) / (b - a));
export const wrapAngle = (a) => { while (a > Math.PI) a -= 2 * Math.PI; while (a < -Math.PI) a += 2 * Math.PI; return a; };

export const K = {
  ROAD_HALF: 3.6, ROAD_EDGE: 4.9, FLAT: 6.5, BLEND: 32, STEP: 2, SMOOTH_K: 50, WATER: 0,
  CHUNK: 64, RES: 32, CELL: 42, SEG: 64, SIDEWALK: 3.4, BLOCK: 150, LANE: 1.8,
};
K.SETBACK = K.ROAD_EDGE + K.SIDEWALK + 0.6; // where corridor buildings start
K.WALL = K.ROAD_EDGE + K.SIDEWALK - 1.0;    // how far the car may drift onto the sidewalk

export function createWorld(seed, region) {
  const CA = region === 'ca', SF = !CA;
  const { ROAD_HALF, ROAD_EDGE, FLAT, BLEND, STEP, SMOOTH_K, WATER, CELL, BLOCK, SIDEWALK } = K;
  const rng = mulberry32(seed ^ (SF ? 0x5f10 : 0));
  const noise = makeNoise2D(rng);
  const fbm = (x, z, oct) => {
    let a = 1, f = 1, s = 0, n = 0;
    for (let o = 0; o < oct; o++) { s += a * noise(x * f + o * 17.3, z * f - o * 9.1); n += a; a *= 0.5; f *= 2.03; }
    return s / n;
  };
  const OCEAN_SIDE = CA ? 1 : -1; // ocean towards +x (CA, Pacific) / -x (SF, Atlantic)
  const OCEAN_LAT = CA ? -1 : 1;  // ...the driver's left (CA) / right (SF), heading "north"

  const road = { xs: [], zs: [], ys: [], raw: [], hd: [], n: 0, nFinal: 0 };
  function roadXAtZ(z) {
    const zs = road.zs, n = road.n;
    if (n === 0) return 0;
    if (z <= zs[0]) return road.xs[0];
    if (z >= zs[n - 1]) return road.xs[n - 1];
    let lo = 0, hi = n - 1;
    while (hi - lo > 1) { const m = (lo + hi) >> 1; if (zs[m] <= z) lo = m; else hi = m; }
    return road.xs[lo] + (road.xs[hi] - road.xs[lo]) * ((z - zs[lo]) / (zs[hi] - zs[lo]));
  }

  // ---- terrain ----
  function mountainFactor(x, z) { const m = 0.5 + 0.5 * noise(x / 1400 - 40.2, z / 1400 + 20.6); return m * m; }
  function coastDist(z) {
    return CA ? 55 + 110 * (0.5 + 0.5 * noise(z / 1100 + 5.1, 3.3)) + 25 * noise(z / 280, 8.8)
              : 75 + 120 * (0.5 + 0.5 * noise(z / 1500 + 5.1, 3.3)) + 20 * noise(z / 300, 8.8);
  }
  function cliffiness(z) { return 0.5 + 0.5 * noise(z / 520, 1.7); }
  function caLand(x, z) {
    const m = mountainFactor(x, z);
    let h = 16 + 14 * noise(x / 900, z / 900) + fbm(x / 260, z / 260, 5) * (8 + 34 * m);
    const r = 1 - Math.abs(noise(x / 480 + 9.4, z / 480 - 9.8));
    h += (r * r - 0.3) * (6 + 20 * m);
    return h + noise(x / 45, z / 45) * 0.9;
  }
  function caHeight(x, z) {
    const u = (x - roadXAtZ(z)) * OCEAN_SIDE;
    const m = mountainFactor(x, z);
    let h = Math.max(caLand(x, z) + sstep(20, 420, -u) * (45 + 85 * m), 3.5);
    const c = coastDist(z), la = laK(z);
    if (la > 0) h = lerp(h, 9 + 2.5 * noise(x / 400, z / 400) + sstep(700, 1600, -u) * 60 * m, la); // the flat LA basin
    if (u > 0) h = lerp(h, 9 + 5 * noise(x / 160, z / 160), sstep(0, c * 0.6, u));
    if (u > c - 140) {
      const width = lerp(lerp(120, 16, cliffiness(z)), 95, la); // wide sandy beaches in LA
      const shore = 1.6 - (u - c) * (u > c ? 0.16 : 0.02) + noise(x / 30, z / 30) * 0.4;
      h = lerp(h, shore, sstep(c - width, c, u));
    }
    return Math.max(h, -26);
  }
  // South Florida: flat city on a barrier coast; long causeways cross the bay.
  function causewayK(z) { return SF ? sstep(0.34, 0.46, noise(z / 1900 + 3.1, 7.7)) : 0; }
  // California: Los Angeles stretches (the drive always starts in LA) alternate with open coast.
  function laK(z) { return CA ? Math.max(sstep(0.02, 0.22, noise(z / 2600 + 41.3, 5.5)), sstep(3600, 2600, z)) : 0; }
  function districtAt(z) {
    if (CA) {
      if (laK(z) < 0.5) return 'coast';
      const d = noise(z / 1100 - 8.1, 3.3) + 0.12 * noise(z / 380, 1.9);
      return d > 0.22 ? 'downtown' : d < -0.15 ? 'beach' : 'resid';
    }
    if (causewayK(z) > 0.5) return 'causeway';
    const d = noise(z / 1300 - 5.2, 2.2) + 0.15 * noise(z / 400, 9.9);
    return d > 0.18 ? 'downtown' : d < -0.22 ? 'deco' : 'resid';
  }
  function sfHeight(x, z) {
    const rx = roadXAtZ(z), u = (x - rx) * OCEAN_SIDE;
    let h = 1.8 + 0.3 * noise(x / 300, z / 300) + 0.08 * noise(x / 40, z / 40);
    const c = coastDist(z);
    if (u > c - 60) h = lerp(h, 1.2 - (u - c) * (u > c ? 0.12 : 0.012), sstep(c - 60, c, u));
    const cw = causewayK(z);
    if (cw > 0) h = lerp(h, -4 + noise(x / 90, z / 90), cw * sstep(12, 70, Math.abs(x - rx)));
    return Math.max(h, -12);
  }
  const baseH = CA ? caHeight : sfHeight;
  function roadRawHeight(x, z, s) {
    if (CA) return lerp(clamp(8 + 0.3 * (caLand(x, z) - 16) + 3 * Math.sin(s / 140), 6, 30), 9.2, laK(z));
    return 2.4 + 0.25 * noise(z / 600, 1.1);
  }

  // ---- the road ----
  const ph = Array.from({ length: 6 }, () => rng() * Math.PI * 2);
  const AMP = CA ? 1 : 0.42, LEN = CA ? 1 : 2.3;
  const roadAmp = [0.6 + rng() * 0.15, 0.32 + rng() * 0.1, 0.2 + rng() * 0.06, 0.1].map((a) => a * AMP);
  function headingAt(s) { // bounded sum of sines: winds, but always progresses along +z
    return roadAmp[0] * Math.sin(s / (640 * LEN) + ph[0]) + roadAmp[1] * Math.sin(s / (250 * LEN) + ph[1]) +
           roadAmp[2] * Math.sin(s / (105 * LEN) + ph[2]) + roadAmp[3] * Math.sin(s / (44 * LEN) + ph[3]);
  }
  const gaussW = [];
  {
    let sum = 0;
    for (let k = -SMOOTH_K; k <= SMOOTH_K; k++) { const w = Math.exp(-(k * k) / (2 * (SMOOTH_K / 2.4) ** 2)); gaussW.push(w); sum += w; }
    for (let k = 0; k < gaussW.length; k++) gaussW[k] /= sum;
  }
  const hash = new Map();
  const hkey = (cx, cz) => cx * 1048576 + cz;
  function addRoadSample() {
    const i = road.n, s = i * STEP;
    let x = 0, z = 0;
    if (i > 0) { const hm = headingAt(s - STEP / 2); x = road.xs[i - 1] + Math.sin(hm) * STEP; z = road.zs[i - 1] + Math.cos(hm) * STEP; }
    road.xs.push(x); road.zs.push(z); road.hd.push(headingAt(s));
    road.raw.push(roadRawHeight(x, z, s)); road.ys.push(undefined); road.n++;
    const key = hkey(Math.floor(x / CELL), Math.floor(z / CELL));
    let arr = hash.get(key); if (!arr) hash.set(key, (arr = [])); arr.push(i);
    const f = road.n - 1 - SMOOTH_K;
    if (f >= 0) {
      let y = 0;
      for (let k = -SMOOTH_K; k <= SMOOTH_K; k++) y += gaussW[k + SMOOTH_K] * road.raw[clamp(f + k, 0, road.n - 1)];
      road.ys[f] = Math.max(y, WATER + (SF ? 1.6 : 1.2));
      road.nFinal = f + 1;
    }
  }
  const ensureRoadIndex = (i) => { while (road.nFinal <= i) addRoadSample(); };
  const ensureRoadZ = (z) => { while (road.n < SMOOTH_K + 4 || road.zs[road.nFinal - 1] < z) addRoadSample(); };

  const Q = () => ({ d: Infinity, y: 0, s: 0, lat: 0, i: 0, t: 0, dx: 0, dz: 1 });
  function roadQuery(x, z, out) {
    const cx = Math.floor(x / CELL), cz = Math.floor(z / CELL);
    let best = Infinity, bi = -1;
    for (let a = -1; a <= 1; a++) for (let b = -1; b <= 1; b++) {
      const arr = hash.get(hkey(cx + a, cz + b));
      if (!arr) continue;
      for (let k = 0; k < arr.length; k++) {
        const i = arr[k], ddx = road.xs[i] - x, ddz = road.zs[i] - z, d2 = ddx * ddx + ddz * ddz;
        if (d2 < best) { best = d2; bi = i; }
      }
    }
    out.d = Infinity;
    if (bi < 0) return out;
    let bd = Infinity;
    for (let a = bi - 1; a <= bi; a++) {
      const b = a + 1;
      if (a < 0 || b >= road.n) continue;
      const ax = road.xs[a], az = road.zs[a], sx = road.xs[b] - ax, sz = road.zs[b] - az, len2 = sx * sx + sz * sz;
      const t = clamp(((x - ax) * sx + (z - az) * sz) / len2, 0, 1);
      const px = ax + sx * t - x, pz = az + sz * t - z, d2 = px * px + pz * pz;
      if (d2 < bd) {
        bd = d2;
        const len = Math.sqrt(len2), dx = sx / len, dz = sz / len;
        const ya = road.ys[a] ?? road.raw[a], yb = road.ys[b] ?? road.raw[b];
        out.y = ya + (yb - ya) * t; out.s = (a + t) * STEP; out.i = a; out.t = t; out.dx = dx; out.dz = dz;
        out.lat = (x - ax) * -dz + (z - az) * dx; // + = right of travel direction
      }
    }
    out.d = Math.sqrt(bd);
    return out;
  }
  const _q = Q();
  function heightAt(x, z, q = _q) {
    const H = baseH(x, z);
    roadQuery(x, z, q);
    if (q.d >= FLAT + BLEND) return H;
    const ry = q.y - 0.22;
    if (q.d <= FLAT) return ry;
    return lerp(ry, H, smooth((q.d - FLAT) / BLEND));
  }
  const intersectionDist = (s) => Math.abs(s - Math.round(s / BLOCK) * BLOCK);
  // Is there a sidewalk + buildings on this side (+1 right / -1 left) of the road here?
  function citySide(z, side) {
    const d = districtAt(z);
    return d !== 'causeway' && d !== 'coast';
  }
  function buildingSide(z, side) {
    if (!citySide(z, side)) return false;
    const d = districtAt(z);
    return !((d === 'deco' || d === 'beach') && side === OCEAN_LAT); // beachfront districts have a promenade on the ocean side
  }
  const _gq = Q();
  function groundAt(x, z) { // the drivable surface
    const h = heightAt(x, z, _gq);
    const d = _gq.d;
    if (d < ROAD_HALF) return _gq.y + 0.03;
    if (d < ROAD_EDGE + SIDEWALK && citySide(z, Math.sign(_gq.lat)) && intersectionDist(_gq.s) > 5.5) {
      return d < ROAD_EDGE ? _gq.y + 0.03 : _gq.y + 0.17;
    }
    if (d < ROAD_EDGE) return lerp(_gq.y + 0.03, _gq.y - 0.12, (d - ROAD_HALF) / (ROAD_EDGE - ROAD_HALF));
    return Math.max(h, WATER - 0.6);
  }
  function roadPoint(s, lat = 0) {
    const f = clamp(s / STEP, 0, road.nFinal - 2), i = Math.floor(f), t = f - i;
    const x = lerp(road.xs[i], road.xs[i + 1], t), z = lerp(road.zs[i], road.zs[i + 1], t);
    const dx = road.xs[i + 1] - road.xs[i], dz = road.zs[i + 1] - road.zs[i], l = Math.hypot(dx, dz) || 1;
    return { x: x + (-dz / l) * lat, z: z + (dx / l) * lat, y: lerp(road.ys[i], road.ys[i + 1], t), h: Math.atan2(dx, dz) };
  }

  return {
    CA, SF, region, seed, noise, fbm, road, OCEAN_SIDE, OCEAN_LAT,
    roadXAtZ, coastDist, cliffiness, mountainFactor, caLand, causewayK, laK, districtAt, baseH, headingAt,
    addRoadSample, ensureRoadIndex, ensureRoadZ, Q, roadQuery, heightAt, groundAt, roadPoint,
    intersectionDist, citySide, buildingSide,
  };
}
