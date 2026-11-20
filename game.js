// Two Lanes — an endless, procedurally generated drive.
// Two regions (the California coast, North Florida backroads), drawn in a flat, graphic poster style.
import * as THREE from 'three';

// ---------------------------------------------------------------------------
// Params, seed, RNG, noise
// ---------------------------------------------------------------------------
const params = new URLSearchParams(location.search);
// Region/seed come from ?region=fl&seed=123 or, where query strings can't be used, from #fl-123.
const HASH = (location.hash || '').slice(1).match(/^(ca|fl)(?:-(\d+))?$/);
const SEED = (parseInt(params.get('seed'), 10) || (HASH && parseInt(HASH[2], 10)) || ((Math.random() * 1e9) | 0)) >>> 0;
const REGION_ID = (params.get('region') || (HASH && HASH[1])) === 'fl' ? 'fl' : 'ca';
const CA = REGION_ID === 'ca', FL = !CA;
let AUTOGO = params.get('go') === '1';
try { if (sessionStorage.getItem('twolanes.go') === '1') { AUTOGO = true; sessionStorage.removeItem('twolanes.go'); } } catch (e) { /* storage unavailable */ }
const DYNRES = params.get('dynres') !== '0';

function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function makeNoise2D(rand) {
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
    const x1 = x0 - i1 + G2, y1 = y0 - j1 + G2;
    const x2 = x0 - 1 + 2 * G2, y2 = y0 - 1 + 2 * G2;
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
const rng = mulberry32(SEED ^ (FL ? 0x5eed : 0));
const noise = makeNoise2D(rng);
const fbm = (x, z, oct) => {
  let a = 1, f = 1, s = 0, n = 0;
  for (let o = 0; o < oct; o++) { s += a * noise(x * f + o * 17.3, z * f - o * 9.1); n += a; a *= 0.5; f *= 2.03; }
  return s / n;
};
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const lerp = (a, b, t) => a + (b - a) * t;
const smooth = (t) => { t = clamp(t, 0, 1); return t * t * (3 - 2 * t); };
const sstep = (a, b, x) => smooth((x - a) / (b - a));
const wrapAngle = (a) => { while (a > Math.PI) a -= 2 * Math.PI; while (a < -Math.PI) a += 2 * Math.PI; return a; };
const col = (hex) => { const c = new THREE.Color(hex); return [c.r, c.g, c.b]; };
function mix3(out, a, b, t) { out[0] = a[0] + (b[0] - a[0]) * t; out[1] = a[1] + (b[1] - a[1]) * t; out[2] = a[2] + (b[2] - a[2]) * t; return out; }

// ---------------------------------------------------------------------------
// Art direction: palettes keyed by sun elevation (sRGB hex)
// ---------------------------------------------------------------------------
const SKY_KEYS = {
  ca: [
    { e: -0.35, top: 0x0f1033, mid: 0x231d5a, hor: 0x4a3170, sun: 0xf6ead2, glow: 0x3a2a6a, light: 0x8f95e0, lightI: 0.7, amb: 0x5254a6, ambG: 0x1d1638, ambI: 1.05, ink: 0x0b0a1e, shadow: 0x1b1746, hi: 0xe8dcff, cloud: 0x352f68, cloudS: 0x241f4c, water: 0x1c2058, ridge: 0x241c52 },
    { e: -0.08, top: 0x262a6c, mid: 0x6b4c96, hor: 0xe58aa2, sun: 0xffd9b8, glow: 0xb06a9e, light: 0xd9a2c6, lightI: 0.8, amb: 0x7064aa, ambG: 0x2a1f3c, ambI: 1.0, ink: 0x1a1232, shadow: 0x372866, hi: 0xffd8e6, cloud: 0x9a76b4, cloudS: 0x5e4a88, water: 0x3a3f86, ridge: 0x5a3f80 },
    { e: 0.03, top: 0x3d3b90, mid: 0xd8689c, hor: 0xffb56a, sun: 0xfff2c4, glow: 0xff8a6a, light: 0xffa06a, lightI: 1.8, amb: 0xa47cbc, ambG: 0x4c2c4a, ambI: 1.0, ink: 0x2a1438, shadow: 0x5a2f6c, hi: 0xffe2b4, cloud: 0xffa48c, cloudS: 0xb8689a, water: 0x4c5cae, ridge: 0x8c4a82 },
    { e: 0.18, top: 0x6f86de, mid: 0xf3a9b8, hor: 0xffd9a2, sun: 0xfff7de, glow: 0xffc49a, light: 0xffd49c, lightI: 2.0, amb: 0xbaa8da, ambG: 0x6c4c56, ambI: 1.05, ink: 0x3a2238, shadow: 0x6a3f7c, hi: 0xfff0d2, cloud: 0xfff1e8, cloudS: 0xe6a6bc, water: 0x5079c6, ridge: 0xb8728e },
    { e: 0.55, top: 0x3b78e2, mid: 0x8cc2f2, hor: 0xe9f2f0, sun: 0xfffdf4, glow: 0xd8ecff, light: 0xfff3e0, lightI: 2.1, amb: 0xb8d2ff, ambG: 0x7c6a52, ambI: 1.1, ink: 0x22304c, shadow: 0x3c4a8c, hi: 0xfff8ea, cloud: 0xffffff, cloudS: 0xc6d6f2, water: 0x2f80c6, ridge: 0x7d95cc },
  ],
  fl: [
    { e: -0.35, top: 0x0b1b26, mid: 0x183640, hor: 0x37564f, sun: 0xe9f2e2, glow: 0x1e3a3c, light: 0x8fb6bc, lightI: 0.7, amb: 0x34586a, ambG: 0x0e1a16, ambI: 1.05, ink: 0x06100e, shadow: 0x0f2e38, hi: 0xd8f0e8, cloud: 0x223c42, cloudS: 0x16292f, water: 0x0f2a2a, ridge: 0x0e2626 },
    { e: -0.08, top: 0x1d3a5c, mid: 0x4c6c80, hor: 0xcaa79e, sun: 0xffe2c2, glow: 0x8a7a80, light: 0xc4aaa2, lightI: 0.8, amb: 0x52707e, ambG: 0x1a2622, ambI: 1.0, ink: 0x0e1a1a, shadow: 0x1f3f4a, hi: 0xf2e2d2, cloud: 0x6e8288, cloudS: 0x4a5c66, water: 0x2a4848, ridge: 0x2a4450 },
    { e: 0.03, top: 0x2d5878, mid: 0xe4a27a, hor: 0xffd28a, sun: 0xfff3ca, glow: 0xffb27a, light: 0xffb272, lightI: 1.8, amb: 0x8eaaa2, ambG: 0x3a3a28, ambI: 1.0, ink: 0x1e1a12, shadow: 0x2e4a52, hi: 0xffe8c2, cloud: 0xf8ba92, cloudS: 0xa47a7c, water: 0x3f6a6a, ridge: 0x4a5a52 },
    { e: 0.18, top: 0x58a0ba, mid: 0xbfe2d2, hor: 0xf6eec8, sun: 0xfffbe8, glow: 0xfff0c0, light: 0xffe8b4, lightI: 2.0, amb: 0xbadec8, ambG: 0x4c5c3a, ambI: 1.05, ink: 0x1c2a22, shadow: 0x2e5a5a, hi: 0xfff6de, cloud: 0xffffff, cloudS: 0xcad8d0, water: 0x3a6a60, ridge: 0x3f6a5a },
    { e: 0.55, top: 0x3898c4, mid: 0xa8dae2, hor: 0xf0f5e2, sun: 0xffffff, glow: 0xe8f6f0, light: 0xfff8ea, lightI: 2.1, amb: 0xcaeae2, ambG: 0x52623c, ambI: 1.1, ink: 0x1a2a28, shadow: 0x2a5a68, hi: 0xfffbea, cloud: 0xffffff, cloudS: 0xc2dada, water: 0x2f6a68, ridge: 0x4f7f78 },
  ],
}[REGION_ID];
const NUM_FIELDS = ['lightI', 'ambI'];
const COLOR_FIELDS = Object.keys(SKY_KEYS[0]).filter((k) => k !== 'e' && !NUM_FIELDS.includes(k));
for (const k of SKY_KEYS) for (const f of COLOR_FIELDS) k[f] = new THREE.Color(k[f]);
const PAL_NOW = {};
for (const f of COLOR_FIELDS) PAL_NOW[f] = new THREE.Color();
function samplePalette(e) {
  let a = SKY_KEYS[0], b = SKY_KEYS[SKY_KEYS.length - 1], t = 0;
  if (e <= a.e) b = a;
  else if (e >= b.e) a = b;
  else for (let i = 0; i < SKY_KEYS.length - 1; i++) if (e >= SKY_KEYS[i].e && e <= SKY_KEYS[i + 1].e) { a = SKY_KEYS[i]; b = SKY_KEYS[i + 1]; t = (e - a.e) / (b.e - a.e); break; }
  t = smooth(t);
  for (const f of COLOR_FIELDS) PAL_NOW[f].copy(a[f]).lerp(b[f], t);
  for (const f of NUM_FIELDS) PAL_NOW[f] = lerp(a[f], b[f], t);
}

// Ground & plant colours: flat, bold, limited
const G = CA ? {
  goldA: col(0xf0b552), goldB: col(0xe39c43), chap: col(0x8c8a48), chapB: col(0x6b7a46), green: col(0xa8b85a),
  rock: col(0xd48a6a), rockB: col(0xb56f5c), sand: col(0xf6dcb0), wetSand: col(0xd9b98e), dirt: col(0xeab27c),
} : {
  grassA: col(0x8fc25a), grassB: col(0x6ea64a), straw: col(0xc9a35c), sand: col(0xefe0b0), mud: col(0x5a5a32),
  under: col(0x344a3a), dirt: col(0xe6d4a0), rock: col(0x9a9480),
};

// ---------------------------------------------------------------------------
// World constants
// ---------------------------------------------------------------------------
const ROAD_HALF = 3.6, ROAD_EDGE = 4.9, FLAT = 6.5, BLEND = 32, STEP = 2, SMOOTH_K = 50;
const WATER = 0;
const CHUNK = 64, RES = 32;
const VIEW_CHUNKS = clamp(parseInt(params.get('view'), 10) || 8, 3, 10);
const CELL = 42;
const OCEAN_SIDE = 1; // CA: Pacific on the +x side (driver's left heading "north")

// ---------------------------------------------------------------------------
// Road & terrain
// ---------------------------------------------------------------------------
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
function mountainFactor(x, z) { const m = 0.5 + 0.5 * noise(x / 1400 - 40.2, z / 1400 + 20.6); return m * m; }
function coastDist(z) { return 55 + 110 * (0.5 + 0.5 * noise(z / 1100 + 5.1, 3.3)) + 25 * noise(z / 280, 8.8); }
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
  const c = coastDist(z);
  if (u > 0) h = lerp(h, 9 + 5 * noise(x / 160, z / 160), sstep(0, c * 0.6, u));
  if (u > c - 140) {
    const width = lerp(120, 16, cliffiness(z));
    const shore = 1.6 - (u - c) * (u > c ? 0.16 : 0.02) + noise(x / 30, z / 30) * 0.4;
    h = lerp(h, shore, sstep(c - width, c, u));
  }
  return Math.max(h, -26);
}
function swampiness(x, z) { return sstep(0.12, 0.5, noise(x / 650 + 3.3, z / 650 - 8.1)); }
function flHeight(x, z) {
  return 3.2 + 2.0 * noise(x / 700, z / 700) + 1.3 * fbm(x / 170, z / 170, 3) + 0.22 * noise(x / 16, z / 16) - swampiness(x, z) * 4.6;
}
const baseH = CA ? caHeight : flHeight;
function roadRawHeight(x, z, s) {
  if (CA) return clamp(8 + 0.3 * (caLand(x, z) - 16) + 3 * Math.sin(s / 140), 6, 30);
  return Math.max(2.2 + 0.6 * noise(x / 500, z / 500), 1.3);
}

const ph = Array.from({ length: 6 }, () => rng() * Math.PI * 2);
const AMP_SCALE = CA ? 1 : 0.5, LEN_SCALE = CA ? 1 : 1.9;
const roadAmp = [0.6 + rng() * 0.15, 0.32 + rng() * 0.1, 0.2 + rng() * 0.06, 0.1].map((a) => a * AMP_SCALE);
function headingAt(s) { // bounded sum of sines: winds, but always progresses along +z
  const L = LEN_SCALE;
  return roadAmp[0] * Math.sin(s / (640 * L) + ph[0]) + roadAmp[1] * Math.sin(s / (250 * L) + ph[1]) +
         roadAmp[2] * Math.sin(s / (105 * L) + ph[2]) + roadAmp[3] * Math.sin(s / (44 * L) + ph[3]);
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
    road.ys[f] = Math.max(y, WATER + 1.2);
    road.nFinal = f + 1;
  }
}
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
      out.lat = (x - ax) * -dz + (z - az) * dx;
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
const _gq = Q();
function groundAt(x, z) {
  const h = heightAt(x, z, _gq);
  if (_gq.d < ROAD_HALF) return _gq.y + 0.03;
  if (_gq.d < ROAD_EDGE) return lerp(_gq.y + 0.03, _gq.y - 0.12, (_gq.d - ROAD_HALF) / (ROAD_EDGE - ROAD_HALF));
  return Math.max(h, WATER - 0.6);
}
function roadPoint(s, lat = 0) {
  const f = clamp(s / STEP, 0, road.nFinal - 2), i = Math.floor(f), t = f - i;
  const x = lerp(road.xs[i], road.xs[i + 1], t), z = lerp(road.zs[i], road.zs[i + 1], t);
  const dx = road.xs[i + 1] - road.xs[i], dz = road.zs[i + 1] - road.zs[i], l = Math.hypot(dx, dz) || 1;
  return { x: x + (-dz / l) * lat, z: z + (dx / l) * lat, y: lerp(road.ys[i], road.ys[i + 1], t), h: Math.atan2(dx, dz) };
}

// ---------------------------------------------------------------------------
// Renderer, scene, toon shading
// ---------------------------------------------------------------------------
const canvas = document.getElementById('game');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: 'high-performance' });
renderer.toneMapping = THREE.NoToneMapping; // flat graphic colours: what's in the palette is what you see
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
const BASE_PR = Math.min(devicePixelRatio || 1, 1.75);
let prScale = 1;

const scene = new THREE.Scene();
const FOG = CA ? [110, VIEW_CHUNKS * 64 + 40] : [55, VIEW_CHUNKS * 64 - 80];
scene.fog = new THREE.Fog(0xffffff, FOG[0], FOG[1]);
const camera = new THREE.PerspectiveCamera(60, innerWidth / innerHeight, 0.3, 9000);

function toonRamp(steps) {
  const data = new Uint8Array(steps.length * 4);
  steps.forEach((v, i) => { data[i * 4] = data[i * 4 + 1] = data[i * 4 + 2] = v; data[i * 4 + 3] = 255; });
  const t = new THREE.DataTexture(data, steps.length, 1, THREE.RGBAFormat);
  t.minFilter = t.magFilter = THREE.NearestFilter; t.generateMipmaps = false; t.needsUpdate = true;
  return t;
}
const RAMP = toonRamp([70, 165, 255]);
const toon = (opts) => new THREE.MeshToonMaterial({ gradientMap: RAMP, ...opts });

const hemi = new THREE.HemisphereLight(0xffffff, 0x444444, 1);
scene.add(hemi);
const sun = new THREE.DirectionalLight(0xffffff, 2);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
Object.assign(sun.shadow.camera, { left: -70, right: 70, top: 70, bottom: -70, near: 1, far: 700 });
sun.shadow.bias = -0.0005;
sun.shadow.normalBias = 0.5;
scene.add(sun, sun.target);

// ---------------------------------------------------------------------------
// Post-processing: ink outlines, split-tone grade, print looks, grain
// ---------------------------------------------------------------------------
const LOOKS = ['poster', 'riso', 'clean'];
const depthTex = new THREE.DepthTexture(1, 1);
depthTex.type = THREE.UnsignedIntType;
const rt = new THREE.WebGLRenderTarget(1, 1, { type: THREE.HalfFloatType, samples: 4, depthTexture: depthTex });
const postU = {
  tColor: { value: rt.texture }, tDepth: { value: depthTex }, res: { value: new THREE.Vector2(1, 1) },
  near: { value: camera.near }, far: { value: camera.far }, time: { value: 0 }, look: { value: 0 }, pr: { value: 1 },
  ink: { value: new THREE.Color() }, shadowTint: { value: new THREE.Color() }, hiTint: { value: new THREE.Color() },
  paper: { value: new THREE.Color(CA ? 0xfff4e4 : 0xf6f4e6) },
};
const postMat = new THREE.ShaderMaterial({
  uniforms: postU, depthTest: false, depthWrite: false, toneMapped: false,
  vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`,
  fragmentShader: `
    uniform sampler2D tColor, tDepth; uniform vec2 res; uniform float near, far, time, look, pr;
    uniform vec3 ink, shadowTint, hiTint, paper; varying vec2 vUv;
    float lin(vec2 uv){ float z = texture2D(tDepth, uv).x * 2.0 - 1.0; return 2.0 * near * far / (far + near - z * (far - near)); }
    float hash(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
    float bayer(vec2 p){
      vec2 q = mod(floor(p), 4.0); int i = int(q.x + q.y * 4.0);
      float m[16] = float[16](0.,8.,2.,10.,12.,4.,14.,6.,3.,11.,1.,9.,15.,7.,13.,5.);
      return (m[i] + 0.5) / 16.0;
    }
    vec3 toSRGB(vec3 c){ c = clamp(c, 0.0, 1.0); return mix(c * 12.92, 1.055 * pow(c, vec3(1.0/2.4)) - 0.055, step(0.0031308, c)); }
    void main(){
      vec2 px = 1.0 / res;
      vec3 c = texture2D(tColor, vUv).rgb;
      if (look > 0.5 && look < 1.5) c.r = texture2D(tColor, vUv + px * vec2(1.5, -1.0) * pr).r; // riso misregistration
      float d = lin(vUv);
      if (look < 1.5) { // ink outlines from depth discontinuities
        float o = max(1.0, pr * 0.8);
        float dl = lin(vUv - vec2(px.x * o, 0.0)), dr = lin(vUv + vec2(px.x * o, 0.0));
        float du = lin(vUv + vec2(0.0, px.y * o)), dd = lin(vUv - vec2(0.0, px.y * o));
        float lap = abs(dl + dr - 2.0 * d) + abs(du + dd - 2.0 * d);
        float edge = smoothstep(0.025, 0.08, lap / d) * (1.0 - smoothstep(70.0, 260.0, d));
        c = mix(c, ink, edge * 0.9);
      }
      c = toSRGB(c);
      float L = dot(c, vec3(0.299, 0.587, 0.114));
      if (look < 1.5) { // split tone: tinted shadows, warm highlights
        c = mix(c, shadowTint, (1.0 - smoothstep(0.0, 0.5, L)) * 0.3);
        c = mix(c, c * hiTint * 1.06, smoothstep(0.55, 1.0, L) * 0.35);
      }
      if (look > 0.5 && look < 1.5) { // riso print: few inks, ordered dither, halftone, paper
        float lv = 5.0;
        c = floor(c * lv + bayer(gl_FragCoord.xy / max(1.0, floor(pr)))) / lv;
        vec2 hp = mat2(0.7071, -0.7071, 0.7071, 0.7071) * gl_FragCoord.xy / (5.0 * pr);
        float dotd = length(fract(hp) - 0.5);
        float L2 = dot(c, vec3(0.299, 0.587, 0.114));
        float r = sqrt(clamp(1.0 - L2, 0.0, 1.0)) * 0.55;
        float m = 1.0 - smoothstep(r - 0.08, r + 0.08, dotd);
        c = mix(c, c * toSRGB(ink) * 1.4, m * 0.45 * (1.0 - smoothstep(0.25, 0.7, L2)));
        c *= paper;
      }
      float g = hash(gl_FragCoord.xy + fract(time) * 97.0) - 0.5;
      c += g * (look > 0.5 && look < 1.5 ? 0.10 : look > 1.5 ? 0.02 : 0.045);
      vec2 q = vUv - 0.5;
      c *= 1.0 - dot(q, q) * (look > 1.5 ? 0.25 : 0.6);
      gl_FragColor = vec4(c, 1.0);
    }`,
});
const postScene = new THREE.Scene();
const postCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
postScene.add(new THREE.Mesh(new THREE.PlaneGeometry(2, 2), postMat));

function resize() {
  const pr = BASE_PR * prScale;
  renderer.setPixelRatio(pr);
  renderer.setSize(innerWidth, innerHeight);
  const w = Math.max(1, Math.floor(innerWidth * pr)), h = Math.max(1, Math.floor(innerHeight * pr));
  rt.setSize(w, h);
  postU.res.value.set(w, h);
  postU.pr.value = pr;
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
}
resize();

// ---------------------------------------------------------------------------
// Sky: banded gradient, big graphic sun, moon, stars
// ---------------------------------------------------------------------------
const skyU = {
  top: { value: new THREE.Color() }, mid: { value: new THREE.Color() }, hor: { value: new THREE.Color() },
  sunDir: { value: new THREE.Vector3(0, 1, 0) }, moonDir: { value: new THREE.Vector3(0, 1, 0) },
  sunCol: { value: new THREE.Color() }, glow: { value: new THREE.Color() }, night: { value: 0 },
  stripes: { value: CA ? 1 : 0 }, bands: { value: 9 },
};
const sky = new THREE.Mesh(
  new THREE.SphereGeometry(6000, 48, 24),
  new THREE.ShaderMaterial({
    uniforms: skyU, side: THREE.BackSide, depthWrite: false, fog: false,
    vertexShader: `varying vec3 vDir; void main(){ vDir = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
    fragmentShader: `
      uniform vec3 top, mid, hor, sunDir, moonDir, sunCol, glow; uniform float night, stripes, bands; varying vec3 vDir;
      void main(){
        vec3 d = normalize(vDir); float h = d.y;
        float t = pow(clamp(h, 0.0, 1.0), 0.55);
        float tq = floor(t * bands + 0.5) / bands;            // poster bands
        vec3 c = tq < 0.5 ? mix(hor, mid, tq * 2.0) : mix(mid, top, tq * 2.0 - 1.0);
        // stepped halo rings around the sun
        float ang = acos(clamp(dot(d, sunDir), -1.0, 1.0));
        float ring = step(ang, 0.30) * 0.10 + step(ang, 0.20) * 0.14 + step(ang, 0.125) * 0.2;
        c = mix(c, glow, ring * (1.0 - night));
        // the sun: a hard disc, striped low in the sky (California)
        float R = 0.06;
        if (ang < R && sunDir.y > -0.12) {
          vec3 up = normalize(vec3(0.0, 1.0, 0.0) - sunDir * sunDir.y);
          float sy = dot(d - sunDir, up) / R;
          float show = 1.0;
          if (stripes > 0.5 && sy < -0.05) show = step(mix(0.12, 0.55, -sy), fract(sy * 6.0));
          c = mix(c, sunCol, show);
        }
        // crescent moon
        float ma = acos(clamp(dot(d, moonDir), -1.0, 1.0));
        float mb = acos(clamp(dot(d, normalize(moonDir + vec3(0.012, 0.01, 0.0))), -1.0, 1.0));
        if (ma < 0.028 && mb > 0.026) c = mix(c, vec3(0.98, 0.93, 0.8), night);
        if (h < 0.0) c = hor;
        gl_FragColor = vec4(c, 1.0);
      }`,
  })
);
sky.renderOrder = -10;
scene.add(sky);

const stars = (() => {
  const g = new THREE.BufferGeometry(), pos = [];
  const r = mulberry32(99);
  for (let i = 0; i < 1400; i++) {
    const u = r(), th = r() * Math.PI * 2, y = 0.05 + u * 0.95, rr = Math.sqrt(1 - y * y);
    pos.push(Math.cos(th) * rr * 5500, y * 5500, Math.sin(th) * rr * 5500);
  }
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  const m = new THREE.PointsMaterial({ color: 0xfff6e0, size: 2, sizeAttenuation: false, transparent: true, opacity: 0, fog: false, depthWrite: false });
  const p = new THREE.Points(g, m); p.renderOrder = -9; return p;
})();
scene.add(stars);

// Layered horizon silhouettes: mountains inland (CA) or pine treelines (FL)
const ridges = [];
{
  const layers = CA
    ? [{ R: 1700, k: 0.9 }, { R: 2500, k: 0.62 }, { R: 3500, k: 0.38 }]
    : [{ R: 900, k: 0.85 }, { R: 1500, k: 0.55 }];
  layers.forEach((L, li) => {
    const N = CA ? 512 : 2400, pos = [], idx = [];
    for (let i = 0; i <= N; i++) {
      const th = (i / N) * Math.PI * 2, cx = Math.cos(th), sz = Math.sin(th);
      let h;
      if (CA) {
        const inl = sstep(-0.15, 0.35, -cx); // inland is -x
        const n1 = 0.5 + 0.5 * noise(cx * (3 + li * 2) + li * 10, sz * (3 + li * 2));
        const n2 = 1 - Math.abs(noise(cx * 9 + li, sz * 9 - li));
        const H = [60 + 150 * n1 + 40 * n2, 110 + 280 * n1 + 60 * n2, 220 + 480 * n1 + 90 * n2][li];
        h = H * inl - 12 * (1 - inl);
      } else {
        const n1 = 0.5 + 0.5 * noise(cx * 6 + li * 7, sz * 6);
        const tooth = Math.abs(((th * L.R) / (7 + li * 3)) % 1 - 0.5) * 2; // triangular pine tops
        const tall = 0.5 + 0.5 * noise(cx * 80 + li, sz * 80);
        h = 14 + li * 6 + n1 * 10 + tooth * tooth * (7 + 8 * tall);
      }
      pos.push(cx * L.R, h, sz * L.R, cx * L.R, -80, sz * L.R);
      if (i < N) { const a = i * 2; idx.push(a, a + 1, a + 2, a + 1, a + 3, a + 2); }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setIndex(idx);
    const m = new THREE.Mesh(g, new THREE.MeshBasicMaterial({ color: 0xffffff, fog: false, side: THREE.DoubleSide }));
    m.renderOrder = -8 + li; m.frustumCulled = false;
    m.userData.k = L.k;
    ridges.push(m); scene.add(m);
  });
}

// Water: the Pacific (CA) or tea-dark swamp water (FL)
function makeRippleTexture() {
  const N = 256, cv = document.createElement('canvas'); cv.width = cv.height = N;
  const g = cv.getContext('2d'), img = g.createImageData(N, N);
  const nz = makeNoise2D(mulberry32(42));
  const P = (x, y) => { const a = x / N * Math.PI * 2, b = y / N * Math.PI * 2; return nz(Math.cos(a) * 3, Math.sin(a) * 3 + Math.cos(b) * 3) + 0.5 * nz(Math.sin(b) * 6 + 20, Math.cos(a) * 6); };
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    const dx = P(x + 1, y) - P(x - 1, y), dy = P(x, y + 1) - P(x, y - 1), i = (y * N + x) * 4;
    img.data[i] = 128 + dx * 160; img.data[i + 1] = 128 + dy * 160; img.data[i + 2] = 255; img.data[i + 3] = 255;
  }
  g.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(cv);
  t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(60, 60);
  return t;
}
const waterMat = new THREE.MeshPhongMaterial({
  color: 0x3060a0, shininess: 140, specular: 0xffffff, transparent: true, opacity: CA ? 0.94 : 0.96,
  normalMap: makeRippleTexture(), normalScale: new THREE.Vector2(0.25, 0.25),
});
const water = new THREE.Mesh(new THREE.PlaneGeometry(9000, 9000), waterMat);
water.rotation.x = -Math.PI / 2;
water.position.y = WATER;
water.receiveShadow = true;
scene.add(water);

// ---------------------------------------------------------------------------
// Ground colour: crisp patches rather than mushy noise
// ---------------------------------------------------------------------------
const _g = [0, 0, 0], _r = [0, 0, 0];
const crisp = (v, at, w = 0.04) => sstep(at - w, at + w, v);
function groundColor(x, z, h, ny, d, out) {
  const v = 0.5 + 0.5 * noise(x / 40, z / 40);
  if (CA) {
    mix3(_g, G.goldA, G.goldB, crisp(v, 0.5, 0.1));
    const chap = crisp(noise(x / 230 + 7, z / 230 - 3) + 0.3 * noise(x / 55, z / 55), 0.15);
    mix3(_r, G.chap, G.chapB, crisp(v, 0.55)); mix3(_g, _g, _r, chap);
    mix3(_g, _g, G.green, crisp(noise(x / 900 - 20, z / 900), 0.45) * 0.6);
    mix3(_r, G.rock, G.rockB, crisp(v, 0.5));
    mix3(out, _g, _r, sstep(0.8, 0.7, ny));
    if (h < 3.2) mix3(out, out, h < 0.7 ? G.wetSand : G.sand, sstep(3.2, 2.4, h));
  } else {
    mix3(_g, G.grassA, G.grassB, crisp(v, 0.5, 0.08));
    mix3(_g, _g, G.straw, crisp(noise(x / 380 + 50, z / 380 - 50), 0.2) * 0.55);
    mix3(_g, _g, G.sand, crisp(noise(x / 110 + 2, z / 110 - 6), 0.35) * 0.6);
    mix3(out, _g, G.mud, sstep(1.3, 0.6, h));
    if (h < WATER) mix3(out, out, G.under, 0.8);
  }
  if (d < FLAT + 3) mix3(out, out, G.dirt, sstep(FLAT + 3, FLAT + 1.5, d));
  return out;
}

// ---------------------------------------------------------------------------
// Plant / prop templates: simple, smooth, graphic shapes (toon-shaded)
// ---------------------------------------------------------------------------
const K0 = 0, K1 = 1, K2 = 2;
const M4 = new THREE.Matrix4();
function bake(parts) {
  const pos = [], nrm = [], kind = [];
  for (const [geo, k, flat] of parts) {
    const g = geo.index ? geo.toNonIndexed() : geo;
    if (flat || !g.attributes.normal) g.computeVertexNormals();
    pos.push(...g.attributes.position.array); nrm.push(...g.attributes.normal.array);
    for (let i = 0; i < g.attributes.position.count; i++) kind.push(k);
  }
  return { pos: new Float32Array(pos), nrm: new Float32Array(nrm), kind: new Uint8Array(kind), count: kind.length };
}
const ball = (r, sx = 1, sy = 1, sz = 1, x = 0, y = 0, z = 0, seg = 12) => new THREE.SphereGeometry(r, seg, Math.max(6, seg * 0.6 | 0)).scale(sx, sy, sz).translate(x, y, z);
const stick = (r0, r1, h, x = 0, y = 0, z = 0) => new THREE.CylinderGeometry(r1, r0, h, 7).translate(x, y + h / 2, z);
function frond(len, width, yaw, tilt, droop, y, x0 = 0) {
  const a = new THREE.BoxGeometry(width, 0.05, len * 0.5).translate(0, 0, len * 0.25);
  a.applyMatrix4(M4.makeRotationX(tilt));
  const b = new THREE.ConeGeometry(width * 0.5, len * 0.6, 4).rotateX(Math.PI / 2).scale(1, 0.12, 1).translate(0, 0, len * 0.3);
  b.applyMatrix4(M4.makeRotationX(tilt + droop));
  b.translate(0, -Math.sin(tilt) * len * 0.5, Math.cos(tilt) * len * 0.5);
  const parts = [a, b];
  for (const p of parts) { p.applyMatrix4(M4.makeRotationY(yaw)); p.translate(x0, y, 0); }
  return parts;
}
function palm(height, n, len, width, lean, tiltMin, tiltMax, head) {
  const parts = [];
  const segs = 5;
  for (let i = 0; i < segs; i++) {
    const y0 = (i / segs) * height, hgt = height / segs;
    const g = new THREE.CylinderGeometry(lerp(0.26, 0.15, (i + 1) / segs), lerp(0.26, 0.15, i / segs), hgt * 1.02, 7)
      .translate(lean * (i / segs) ** 2 * height * 0.1, y0 + hgt / 2, 0);
    parts.push([g, K0]);
  }
  const tx = lean * height * 0.1;
  for (let k = 0; k < n; k++) {
    const yaw = (k / n) * Math.PI * 2 + (k % 2) * 0.3;
    for (const g of frond(len, width, yaw, lerp(tiltMin, tiltMax, (k * 0.618) % 1), 0.55, height, tx)) parts.push([g, K1, true]);
  }
  if (head) parts.push([ball(head, 1, 1, 1, tx, height, 0, 8), K2]);
  return bake(parts);
}
const T = {};
T.post = bake([[new THREE.BoxGeometry(0.14, 1.0, 0.14).translate(0, 0.5, 0), K2, true], [new THREE.BoxGeometry(0.15, 0.14, 0.15).translate(0, 0.86, 0), K1, true]]);
T.rock = bake([[new THREE.DodecahedronGeometry(1, 0).scale(1.3, 0.8, 1.1).translate(0, 0.25, 0), K2, true]]);
T.shrub = bake([[ball(0.95, 1.3, 0.7, 1.3, 0, 0.3), K1]]);
if (CA) {
  T.fanPalm = palm(13, 10, 3.0, 0.4, 1, 0.12, 0.5, 0.5);
  T.datePalm = palm(6.5, 14, 4.2, 0.55, 0.4, -0.25, 0.45, 0.65);
  T.oak = bake([[stick(0.34, 0.2, 2.4), K0], [ball(2.4, 1.25, 0.8, 1.2, 0, 3.4), K1], [ball(1.7, 1.2, 0.85, 1, 1.8, 3.0, 0.6), K1], [ball(1.6, 1.2, 0.85, 1, -1.7, 2.9, -0.6), K1]]);
  T.cypress = bake([ // wind-swept, layered lenses
    [new THREE.CylinderGeometry(0.2, 0.35, 3.8, 6).applyMatrix4(M4.makeRotationZ(-0.28)).translate(0.5, 1.8, 0), K0],
    [ball(2.9, 1, 0.3, 1, 1.4, 3.9, 0), K1], [ball(2.2, 1.1, 0.32, 0.9, 2.5, 4.7, 0.4), K1], [ball(1.9, 1, 0.34, 1, 0.1, 3.3, -0.6), K1],
  ]);
  T.euc = bake([[stick(0.3, 0.16, 11), K2], [ball(1.7, 0.9, 1.7, 0.9, 0.3, 10.6), K1], [ball(1.4, 0.9, 1.5, 0.9, -0.9, 8.6, 0.5), K1], [ball(1.2, 0.9, 1.3, 0.9, 0.9, 7.4, -0.6), K1]]);
  T.yucca = bake((() => { const p = []; for (let k = 0; k < 9; k++) for (const g of frond(1.3, 0.22, k * 0.7, -1.1 + (k % 3) * 0.2, 0.05, 0.1)) p.push([g, K1, true]); return p; })());
} else {
  T.slash = bake([[stick(0.27, 0.14, 12), K0], [ball(1.8, 1.25, 0.75, 1.2, 0, 12.2), K1], [ball(1.3, 1.2, 0.7, 1.2, 1.2, 11.0, 0.3), K1]]);
  const oak = [
    [stick(0.6, 0.38, 2.6), K0],
    [new THREE.CylinderGeometry(0.18, 0.3, 4.5, 6).applyMatrix4(M4.makeRotationZ(1.1)).translate(1.9, 3.2, 0), K0],
    [new THREE.CylinderGeometry(0.18, 0.3, 4.5, 6).applyMatrix4(M4.makeRotationZ(-1.0)).translate(-1.8, 3.3, 0.4), K0],
    [ball(3.0, 1.45, 0.6, 1.3, 0, 4.7), K1], [ball(2.3, 1.4, 0.6, 1.2, 3.6, 4.2, 0.6), K1], [ball(2.2, 1.4, 0.6, 1.2, -3.4, 4.3, -0.4), K1],
  ];
  const mr = mulberry32(5);
  for (let k = 0; k < 16; k++) {
    const a = mr() * Math.PI * 2, r = 1 + mr() * 3.8, len = 1.0 + mr() * 1.4;
    oak.push([new THREE.ConeGeometry(0.1, len, 4).rotateX(Math.PI).translate(Math.cos(a) * r, 3.6 - len / 2, Math.sin(a) * r), K2, true]);
  }
  T.liveOak = bake(oak);
  T.sabal = palm(6, 16, 1.9, 0.75, 0.2, -0.9, 0.4, 0.8);
  T.palmetto = bake((() => { const p = []; for (let k = 0; k < 8; k++) for (const g of frond(1.5, 0.7, k * 0.8, -0.75 + (k % 3) * 0.25, 0.25, 0.1)) p.push([g, K1, true]); return p; })());
  T.cypress = bake([[new THREE.CylinderGeometry(0.25, 0.75, 1.6, 7).translate(0, 0.2, 0), K0], [stick(0.25, 0.13, 8, 0, 0.8), K0], [new THREE.ConeGeometry(1.8, 6.5, 12).translate(0, 9.0, 0), K1]]);
  T.pole = bake([
    [new THREE.CylinderGeometry(0.12, 0.16, 9, 6).translate(0, 4.5, 0), K0, true],
    [new THREE.BoxGeometry(2.4, 0.13, 0.13).translate(0, 8.4, 0), K0, true],
    [new THREE.CylinderGeometry(0.05, 0.05, 0.25, 5).translate(1.0, 8.6, 0), K2, true],
    [new THREE.CylinderGeometry(0.05, 0.05, 0.25, 5).translate(-1.0, 8.6, 0), K2, true],
    [new THREE.CylinderGeometry(0.05, 0.05, 0.25, 5).translate(0.0, 9.1, 0), K2, true],
  ]);
}
const propMat = toon({ vertexColors: true });

class Merger {
  constructor() { this.pos = []; this.nrm = []; this.col = []; }
  add(t, x, y, z, rotY, sx, sy, colors) {
    const c = Math.cos(rotY), s = Math.sin(rotY);
    for (let v = 0; v < t.count; v++) {
      const px = t.pos[v * 3] * sx, py = t.pos[v * 3 + 1] * sy, pz = t.pos[v * 3 + 2] * sx;
      this.pos.push(x + px * c + pz * s, y + py, z - px * s + pz * c);
      const nx = t.nrm[v * 3], ny = t.nrm[v * 3 + 1], nz = t.nrm[v * 3 + 2];
      this.nrm.push(nx * c + nz * s, ny, -nx * s + nz * c);
      const cc = colors[t.kind[v]];
      this.col.push(cc[0], cc[1], cc[2]);
    }
  }
  build(mat) {
    if (!this.pos.length) return null;
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(this.pos, 3));
    g.setAttribute('normal', new THREE.Float32BufferAttribute(this.nrm, 3));
    g.setAttribute('color', new THREE.Float32BufferAttribute(this.col, 3));
    const m = new THREE.Mesh(g, mat);
    m.castShadow = true; m.receiveShadow = true;
    return m;
  }
}
const pick = (rr, a, b) => mix3([0, 0, 0], col(a), col(b), rr());
const C0 = col(0);

function plant(m, rr, lx, lz, x, z, h, d) {
  const s = 0.75 + rr() * 0.6, rot = rr() * 6.283;
  if (CA) {
    const u = (x - roadXAtZ(z)) * OCEAN_SIDE;
    if (h < 3.4) return;
    const chap = crisp(noise(x / 230 + 7, z / 230 - 3) + 0.3 * noise(x / 55, z / 55), 0.15);
    const euc = sstep(0.35, 0.6, noise(x / 420 - 30, z / 420 + 12));
    const coastal = sstep(coastDist(z) - 110, coastDist(z) - 30, u);
    const k = rr();
    if (coastal > 0.4 && k < 0.3) { m.add(T.cypress, lx, h - 0.2, lz, rot, s * 1.1, s, [col(0x6a4a44), pick(rr, 0x2f5f55, 0x3c6e5c), C0]); return; }
    if (euc > 0.3 && k < 0.6) { m.add(T.euc, lx, h - 0.2, lz, rot, s, s * (0.9 + rr() * 0.4), [C0, pick(rr, 0x8fb0a0, 0xa4c0a8), col(0xf0e6d8)]); return; }
    if (d < 70 && rr() < 0.012) { m.add(rr() < 0.6 ? T.fanPalm : T.datePalm, lx, h - 0.2, lz, rot, s, s, [col(0x8a5a4a), pick(rr, 0x3f8a5a, 0x58a060), col(0x6a4a3a)]); return; }
    if (rr() > 0.08 + chap * 0.6) return;
    if (k < 0.62) m.add(T.shrub, lx, h, lz, rot, s * 1.2, s, [C0, pick(rr, 0x6f8a4a, 0x8a9a50), C0]);
    else if (k < 0.8) m.add(T.yucca, lx, h, lz, rot, s * 1.2, s * 1.2, [C0, pick(rr, 0x7fa07a, 0x9ab48a), C0]);
    else if (k < 0.95) m.add(T.oak, lx, h - 0.2, lz, rot, s, s, [col(0x5a3f36), pick(rr, 0x3f704a, 0x2f6650), C0]);
    else m.add(T.rock, lx, h, lz, rot, s * 1.3, s, [C0, C0, col(0xd48a6a)]);
  } else {
    const sw = swampiness(x, z);
    const pasture = sstep(0.3, 0.55, noise(x / 520 + 77, z / 520 - 11));
    const k = rr();
    const oakC = () => [col(0x5a4636), pick(rr, 0x3f6e3e, 0x2c5a3a), pick(rr, 0xa8b49a, 0xbcc6aa)];
    if (h < WATER + 0.25) {
      if (h > WATER - 1.6 && rr() < 0.55) m.add(T.cypress, lx, h, lz, rot, s, s * (0.9 + rr() * 0.4), [col(0x7a5a46), pick(rr, 0x7a8a3a, 0x5f7a3a), C0]);
      return;
    }
    if (pasture > 0.5) { if (rr() < 0.06) m.add(T.liveOak, lx, h - 0.2, lz, rot, s * 1.1, s, oakC()); return; }
    if (sw > 0.25 && k < 0.35) {
      if (rr() < 0.5) m.add(T.liveOak, lx, h - 0.2, lz, rot, s, s, oakC());
      else m.add(T.sabal, lx, h - 0.1, lz, rot, s, s, [col(0x8a7a5a), pick(rr, 0x4f8a48, 0x62994e), col(0x6e6248)]);
      return;
    }
    if (k < 0.42) m.add(T.slash, lx, h - 0.2, lz, rot, s, s * (0.85 + rr() * 0.35), [col(0x6a4038), pick(rr, 0x2f6a4f, 0x3f7a52), C0]);
    else if (k < 0.85) m.add(T.palmetto, lx, h, lz, rot, s * 1.2, s, [C0, pick(rr, 0x6fa04a, 0x88b450), C0]);
    else if (k < 0.92) m.add(T.sabal, lx, h - 0.1, lz, rot, s, s, [col(0x8a7a5a), pick(rr, 0x4f8a48, 0x62994e), col(0x6e6248)]);
    else if (k < 0.96) m.add(T.liveOak, lx, h - 0.2, lz, rot, s, s, oakC());
  }
}

// ---------------------------------------------------------------------------
// Terrain chunks (toon shading + topographic contour lines)
// ---------------------------------------------------------------------------
const contourU = { value: 1 };
const contourInkU = { value: new THREE.Color(0.8, 0.78, 0.86) };
const terrainMat = toon({ vertexColors: true });
terrainMat.onBeforeCompile = (sh) => {
  sh.uniforms.contourK = contourU; sh.uniforms.contourInk = contourInkU;
  sh.uniforms.contourS = { value: CA ? 4.0 : 0.6 };
  sh.vertexShader = sh.vertexShader
    .replace('#include <common>', '#include <common>\nvarying float vCY;')
    .replace('#include <begin_vertex>', '#include <begin_vertex>\nvCY = (modelMatrix * vec4(transformed, 1.0)).y;');
  sh.fragmentShader = sh.fragmentShader
    .replace('#include <common>', '#include <common>\nvarying float vCY; uniform float contourK, contourS; uniform vec3 contourInk;')
    .replace('#include <fog_fragment>', `
      { float fw = max(fwidth(vCY), 1e-4);
        float f = abs(fract(vCY / contourS + 0.5) - 0.5) * contourS / fw;
        float line = 1.0 - clamp(f - 0.3, 0.0, 1.0);
        float fade = (1.0 - smoothstep(40.0, 240.0, length(vViewPosition))) * (1.0 - smoothstep(0.15, 0.6, fw / contourS));
        gl_FragColor.rgb = mix(gl_FragColor.rgb, gl_FragColor.rgb * contourInk, line * fade * contourK); }
      #include <fog_fragment>`);
};
const chunks = new Map();
const N1 = RES + 1, NB = RES + 3;
const hBuf = new Float32Array(NB * NB), dBuf = new Float32Array(NB * NB);
const _cq = Q();
function buildChunk(cx, cz) {
  const ox = cx * CHUNK, oz = cz * CHUNK, st = CHUNK / RES;
  for (let j = 0; j < NB; j++) for (let i = 0; i < NB; i++) {
    hBuf[j * NB + i] = heightAt(ox + (i - 1) * st, oz + (j - 1) * st, _cq);
    dBuf[j * NB + i] = _cq.d;
  }
  const pos = new Float32Array(N1 * N1 * 3), nrm = new Float32Array(N1 * N1 * 3), cols = new Float32Array(N1 * N1 * 3);
  const c = [0, 0, 0];
  for (let j = 0; j < N1; j++) for (let i = 0; i < N1; i++) {
    const b = (j + 1) * NB + (i + 1), v = j * N1 + i, h = hBuf[b];
    pos[v * 3] = i * st; pos[v * 3 + 1] = h; pos[v * 3 + 2] = j * st;
    let nx = hBuf[b - 1] - hBuf[b + 1], ny = 2 * st, nz = hBuf[b - NB] - hBuf[b + NB];
    const nl = Math.hypot(nx, ny, nz); nx /= nl; ny /= nl; nz /= nl;
    nrm[v * 3] = nx; nrm[v * 3 + 1] = ny; nrm[v * 3 + 2] = nz;
    groundColor(ox + i * st, oz + j * st, h, ny, dBuf[b], c);
    cols[v * 3] = c[0]; cols[v * 3 + 1] = c[1]; cols[v * 3 + 2] = c[2];
  }
  const idx = new Uint32Array(RES * RES * 6);
  let k = 0;
  for (let j = 0; j < RES; j++) for (let i = 0; i < RES; i++) {
    const a = j * N1 + i, b = a + 1, cc = a + N1, dd = cc + 1;
    idx[k++] = a; idx[k++] = cc; idx[k++] = b; idx[k++] = b; idx[k++] = cc; idx[k++] = dd;
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  geo.setAttribute('normal', new THREE.BufferAttribute(nrm, 3));
  geo.setAttribute('color', new THREE.BufferAttribute(cols, 3));
  geo.setIndex(new THREE.BufferAttribute(idx, 1));
  geo.computeBoundingSphere();
  const mesh = new THREE.Mesh(geo, terrainMat);
  mesh.position.set(ox, 0, oz); mesh.receiveShadow = true;
  mesh.matrixAutoUpdate = false; mesh.updateMatrix();
  scene.add(mesh);

  const rr = mulberry32((cx * 73856093) ^ (cz * 19349663) ^ SEED);
  const m = new Merger();
  const tries = FL ? 150 : 110;
  for (let t = 0; t < tries; t++) {
    const lx = rr() * CHUNK, lz = rr() * CHUNK, x = ox + lx, z = oz + lz;
    const gi = clamp(Math.round(lx / st), 0, RES), gj = clamp(Math.round(lz / st), 0, RES), b = (gj + 1) * NB + (gi + 1);
    if (dBuf[b] < ROAD_EDGE + 4.5) continue;
    const slope = Math.abs(hBuf[b - 1] - hBuf[b + 1]) + Math.abs(hBuf[b - NB] - hBuf[b + NB]);
    if (slope > 2.4 * st) continue;
    plant(m, rr, lx, lz, x, z, heightAt(x, z, _cq), dBuf[b]);
  }
  const props = m.build(propMat);
  if (props) { props.position.set(ox, 0, oz); props.matrixAutoUpdate = false; props.updateMatrix(); scene.add(props); }
  chunks.set(hkey(cx, cz), { mesh, props, cx, cz });
}
function disposeChunk(key) {
  const c = chunks.get(key);
  scene.remove(c.mesh); c.mesh.geometry.dispose();
  if (c.props) { scene.remove(c.props); c.props.geometry.dispose(); }
  chunks.delete(key);
}

// ---------------------------------------------------------------------------
// Road segments (+ palms, posts, power lines)
// ---------------------------------------------------------------------------
function makeRoadTexture() {
  const W = 256, H = 512, cv = document.createElement('canvas');
  cv.width = W; cv.height = H;
  const g = cv.getContext('2d'), px = W / (2 * ROAD_EDGE), r = mulberry32(7);
  g.fillStyle = CA ? '#e9b27a' : '#e8d8a6'; g.fillRect(0, 0, W, H);
  for (let i = 0; i < 700; i++) { g.fillStyle = r() < 0.5 ? 'rgba(90,60,40,.25)' : 'rgba(255,240,210,.35)'; g.beginPath(); g.arc(r() * W, r() * H, 1.2, 0, 7); g.fill(); }
  const a0 = (ROAD_EDGE - ROAD_HALF) * px, a1 = W - a0;
  g.fillStyle = CA ? '#3b3350' : '#3c4046'; g.fillRect(a0, 0, a1 - a0, H);
  for (let i = 0; i < 1600; i++) { g.fillStyle = 'rgba(255,255,255,.05)'; g.fillRect(a0 + r() * (a1 - a0), r() * H, 1.5, 1.5); }
  const lw = 0.15 * px;
  g.fillStyle = '#fff3dc';
  g.fillRect(a0 + 0.2 * px, 0, lw, H); g.fillRect(a1 - 0.2 * px - lw, 0, lw, H);
  g.fillStyle = CA ? '#f6c453' : '#f2c14e';
  if (CA) { g.fillRect(W / 2 - lw * 1.6, 0, lw, H); g.fillRect(W / 2 + lw * 0.6, 0, lw, H); }
  else g.fillRect(W / 2 - lw / 2, 0, lw, H * 0.4);
  const tex = new THREE.CanvasTexture(cv);
  tex.wrapS = THREE.ClampToEdgeWrapping; tex.wrapT = THREE.RepeatWrapping;
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = renderer.capabilities.getMaxAnisotropy();
  return tex;
}
const roadMat = toon({ map: makeRoadTexture(), polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -4 });
const wireMat = new THREE.LineBasicMaterial({ color: 0x1c1c1c });
const SEG = 64, TEX_LEN = 16, POLE_EVERY = 22;
const segments = new Map();
function poleTops(i) {
  const p = roadPoint(i * STEP, ROAD_EDGE + 4.2);
  const y = Math.min(Math.max(baseH(p.x, p.z), WATER - 0.5), p.y);
  const c = Math.cos(p.h), s = Math.sin(p.h);
  return { p, y, ends: [-1, 0, 1].map((o) => [p.x + o * c, y + 8.4 + (o === 0 ? 0.7 : 0.2), p.z - o * s]) };
}
function buildSegment(k) {
  const i0 = k * SEG, i1 = i0 + SEG, ox = road.xs[i0], oz = road.zs[i0];
  const lats = [-ROAD_EDGE, -ROAD_HALF, ROAD_HALF, ROAD_EDGE], dy = [-0.13, 0.03, 0.03, -0.13];
  const us = [0, (ROAD_EDGE - ROAD_HALF) / (2 * ROAD_EDGE), 1 - (ROAD_EDGE - ROAD_HALF) / (2 * ROAD_EDGE), 1];
  const pos = [], uv = [], idx = [];
  for (let i = i0; i <= i1; i++) {
    const a = Math.max(i - 1, 0), b = Math.min(i + 1, road.nFinal - 1);
    let dx = road.xs[b] - road.xs[a], dz = road.zs[b] - road.zs[a];
    const l = Math.hypot(dx, dz); dx /= l; dz /= l;
    for (let c = 0; c < 4; c++) {
      pos.push(road.xs[i] - dz * lats[c] - ox, road.ys[i] + dy[c], road.zs[i] + dx * lats[c] - oz);
      uv.push(us[c], (i * STEP) / TEX_LEN);
    }
  }
  for (let i = 0; i < SEG; i++) for (let c = 0; c < 3; c++) { const a = i * 4 + c, b = a + 1, cc = a + 4, d = cc + 1; idx.push(a, b, cc, b, d, cc); }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  const mesh = new THREE.Mesh(geo, roadMat);
  mesh.position.set(ox, 0, oz); mesh.receiveShadow = true;
  mesh.matrixAutoUpdate = false; mesh.updateMatrix();
  scene.add(mesh);

  const m = new Merger();
  let wires = null;
  if (CA) {
    for (let i = i0; i < i1; i++) {
      const s = i * STEP;
      const town = sstep(0.25, 0.45, noise(s / 1600 + 31, 4.4));
      if (town > 0.5 && i % 15 === 0) {
        for (const side of [-1, 1]) {
          const p = roadPoint(s, side * (ROAD_EDGE + 3.2)), gy = heightAt(p.x, p.z);
          if (gy < 2 || Math.abs(gy - p.y) > 3) continue;
          const r = mulberry32(i * 31 + side)();
          m.add(T.fanPalm, p.x - ox, gy - 0.2, p.z - oz, r * 6, 0.9 + r * 0.25, 0.9 + r * 0.35, [col(0x8a5a4a), col(0x3f8a5a), col(0x6a4a3a)]);
        }
      } else if (i % 25 === 0) {
        const side = (i / 25) % 2 ? 1 : -1;
        const p = roadPoint(s, side * (ROAD_EDGE + 0.6));
        if (Math.abs(baseH(p.x, p.z) - p.y) > 2.5) continue;
        m.add(T.post, p.x - ox, p.y - 0.15, p.z - oz, p.h, 1, 1, [C0, side > 0 ? col(0xe0533a) : col(0xfff3dc), col(0xfff3dc)]);
      }
    }
  } else {
    const lp = [], wood = col(0x6a5040), glassy = col(0x9ac0c0);
    for (let i = Math.ceil(i0 / POLE_EVERY) * POLE_EVERY; i < i1; i += POLE_EVERY) {
      const a = poleTops(i), b = poleTops(i + POLE_EVERY);
      m.add(T.pole, a.p.x - ox, a.y - 0.3, a.p.z - oz, a.p.h, 1, 1, [wood, wood, glassy]);
      for (let w = 0; w < 3; w++) {
        const A = a.ends[w], B = b.ends[w];
        for (let t = 0; t < 8; t++) {
          const t0 = t / 8, t1 = (t + 1) / 8;
          lp.push(lerp(A[0], B[0], t0) - ox, lerp(A[1], B[1], t0) - 3.6 * t0 * (1 - t0), lerp(A[2], B[2], t0) - oz,
                  lerp(A[0], B[0], t1) - ox, lerp(A[1], B[1], t1) - 3.6 * t1 * (1 - t1), lerp(A[2], B[2], t1) - oz);
        }
      }
    }
    if (lp.length) {
      const lg = new THREE.BufferGeometry();
      lg.setAttribute('position', new THREE.Float32BufferAttribute(lp, 3));
      wires = new THREE.LineSegments(lg, wireMat);
      wires.position.set(ox, 0, oz); wires.matrixAutoUpdate = false; wires.updateMatrix();
      scene.add(wires);
    }
  }
  const props = m.build(propMat);
  if (props) { props.position.set(ox, 0, oz); props.matrixAutoUpdate = false; props.updateMatrix(); scene.add(props); }
  segments.set(k, { mesh, props, wires });
}
function disposeSegment(k) {
  const s = segments.get(k);
  for (const o of [s.mesh, s.props, s.wires]) if (o) { scene.remove(o); o.geometry.dispose(); }
  segments.delete(k);
}

// ---------------------------------------------------------------------------
// Clouds: flat two-tone pills, the way they're drawn in print
// ---------------------------------------------------------------------------
const cloudLit = new THREE.MeshBasicMaterial({ color: 0xffffff, fog: false });
const cloudShade = new THREE.MeshBasicMaterial({ color: 0xdddddd, fog: false });
const clouds = [];
{
  const r = mulberry32(SEED ^ 0xc10d);
  const count = FL ? 30 : 22;
  for (let i = 0; i < count; i++) {
    const grp = new THREE.Group();
    const n = 2 + ((r() * 3) | 0), tall = FL && r() < 0.3;
    const baseLen = 70 + r() * 140;
    for (let k = 0; k < n; k++) {
      const rad = (tall ? 16 : 10) + r() * 8;
      const len = baseLen * (1 - k * 0.28) * (0.8 + r() * 0.3);
      const y = k * rad * (tall ? 1.5 : 1.1);
      const x = (r() - 0.5) * baseLen * 0.35;
      const shade = new THREE.Mesh(new THREE.CapsuleGeometry(rad, len, 4, 16), cloudShade);
      shade.rotation.z = Math.PI / 2; shade.scale.z = 0.35; shade.position.set(x, y, 0);
      const lit = new THREE.Mesh(new THREE.CapsuleGeometry(rad * 0.92, len * 0.94, 4, 16), cloudLit);
      lit.rotation.z = Math.PI / 2; lit.scale.z = 0.35; lit.position.set(x - rad * 0.15, y + rad * 0.3, 1);
      grp.add(shade, lit);
    }
    grp.position.set((r() - 0.5) * 3600, (FL ? 280 : 360) + r() * 220, (r() - 0.5) * 3600);
    clouds.push(grp); scene.add(grp);
  }
}

// ---------------------------------------------------------------------------
// Vehicles
// ---------------------------------------------------------------------------
const CA_PAINT = [0xff8a7a, 0x7fd1c7, 0xf6c453, 0x9db8ff, 0xf4efe4];
const FL_PAINT = [0xd9573f, 0x2f7a6a, 0xf0e2c0, 0xe8a33d, 0x3f5f8f];
const paintList = CA ? CA_PAINT : FL_PAINT;
const carPaint = toon({ color: paintList[(SEED >>> 3) % paintList.length] });
const M = {
  glass: toon({ color: 0x23304a, transparent: CA, opacity: CA ? 0.5 : 1 }),
  dark: toon({ color: 0x24222a }), chrome: toon({ color: 0xe6e2da }),
  seat: toon({ color: CA ? 0xfff0dc : 0x4a3a2c }), white: toon({ color: 0xfff6ea }),
  hl: new THREE.MeshBasicMaterial({ color: 0xfff6d8 }),
};
function buildCar() {
  const car = new THREE.Group(), body = new THREE.Group(); car.add(body);
  const add = (geo, mat, x, y, z) => { const m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); m.castShadow = true; m.receiveShadow = true; body.add(m); return m; };
  const tl = new THREE.MeshBasicMaterial({ color: 0x8a1010 });
  let wheelR, wheelPos, camH;
  if (CA) {
    add(new THREE.BoxGeometry(1.88, 0.48, 4.7), carPaint, 0, 0.6, 0);
    add(new THREE.BoxGeometry(1.84, 0.16, 4.55), carPaint, 0, 0.9, -0.02);
    add(new THREE.BoxGeometry(1.9, 0.07, 4.64), M.white, 0, 0.74, 0);
    add(new THREE.BoxGeometry(1.5, 0.05, 1.9), M.seat, 0, 0.99, -0.45);
    for (const x of [-0.42, 0.42]) { add(new THREE.BoxGeometry(0.58, 0.55, 0.16), M.seat, x, 1.25, -0.95); add(new THREE.BoxGeometry(0.58, 0.12, 0.6), M.seat, x, 1.05, -0.65); }
    add(new THREE.BoxGeometry(1.7, 0.42, 0.14), M.seat, 0, 1.18, -1.65);
    const ws = add(new THREE.BoxGeometry(1.6, 0.5, 0.04), M.glass, 0, 1.22, 0.62); ws.rotation.x = -0.45;
    const fr = add(new THREE.BoxGeometry(1.64, 0.05, 0.06), M.chrome, 0, 1.45, 0.52); fr.rotation.x = -0.45;
    const sw = add(new THREE.TorusGeometry(0.17, 0.025, 6, 14), M.dark, 0.42, 1.08, 0.2); sw.rotation.x = -0.9;
    add(new THREE.BoxGeometry(1.92, 0.14, 0.18), M.chrome, 0, 0.46, 2.35);
    add(new THREE.BoxGeometry(1.92, 0.14, 0.18), M.chrome, 0, 0.46, -2.35);
    for (const x of [0.66, -0.66]) add(new THREE.CylinderGeometry(0.13, 0.13, 0.06, 12).rotateX(Math.PI / 2), M.hl, x, 0.74, 2.35);
    for (const x of [0.7, -0.7]) add(new THREE.BoxGeometry(0.22, 0.22, 0.06), tl, x, 0.76, -2.36);
    wheelR = 0.36; camH = 1.62;
    wheelPos = [[0.88, 1.5], [-0.88, 1.5], [0.88, -1.5], [-0.88, -1.5]];
  } else {
    add(new THREE.BoxGeometry(1.92, 0.6, 5.0), carPaint, 0, 0.85, 0);
    const cab = new THREE.BoxGeometry(1.82, 0.78, 1.7), p = cab.attributes.position;
    for (let i = 0; i < p.count; i++) if (p.getY(i) > 0) p.setZ(i, p.getZ(i) * 0.88 - 0.05);
    cab.computeVertexNormals();
    add(cab, carPaint, 0, 1.53, 0.35);
    add(new THREE.BoxGeometry(1.84, 0.4, 1.3), M.glass, 0, 1.62, 0.33);
    add(new THREE.BoxGeometry(1.86, 0.1, 1.4), M.white, 0, 1.94, 0.33);
    add(new THREE.BoxGeometry(1.92, 0.08, 2.3), M.dark, 0, 1.17, -1.32);
    for (const x of [0.92, -0.92]) add(new THREE.BoxGeometry(0.08, 0.45, 2.3), carPaint, x, 1.38, -1.32);
    add(new THREE.BoxGeometry(1.92, 0.45, 0.08), carPaint, 0, 1.38, -2.46);
    add(new THREE.BoxGeometry(1.96, 0.2, 0.22), M.chrome, 0, 0.6, 2.55);
    add(new THREE.BoxGeometry(1.96, 0.2, 0.22), M.dark, 0, 0.6, -2.55);
    add(new THREE.BoxGeometry(1.2, 0.34, 0.05), M.chrome, 0, 0.92, 2.52);
    for (const x of [0.74, -0.74]) add(new THREE.CylinderGeometry(0.15, 0.15, 0.06, 12).rotateX(Math.PI / 2), M.hl, x, 0.98, 2.52);
    for (const x of [0.82, -0.82]) add(new THREE.BoxGeometry(0.18, 0.28, 0.06), tl, x, 1.0, -2.52);
    for (const x of [1.0, -1.0]) add(new THREE.BoxGeometry(0.08, 0.2, 0.14), M.chrome, x, 1.6, 1.15);
    wheelR = 0.44; camH = 1.95;
    wheelPos = [[0.9, 1.6], [-0.9, 1.6], [0.9, -1.55], [-0.9, -1.55]];
  }
  const wheels = [];
  const tyre = new THREE.CylinderGeometry(wheelR, wheelR, 0.28, 18).rotateZ(Math.PI / 2);
  const hub = new THREE.CylinderGeometry(wheelR * 0.5, wheelR * 0.5, 0.29, 10).rotateZ(Math.PI / 2);
  const wall = new THREE.CylinderGeometry(wheelR * 0.78, wheelR * 0.78, 0.285, 16).rotateZ(Math.PI / 2);
  for (const [x, z] of wheelPos) {
    const pivot = new THREE.Group(); pivot.position.set(x, wheelR, z);
    const spin = new THREE.Group(); pivot.add(spin);
    const w = new THREE.Mesh(tyre, M.dark); w.castShadow = true; spin.add(w);
    if (CA) spin.add(new THREE.Mesh(wall, M.white));
    spin.add(new THREE.Mesh(hub, M.chrome));
    spin.add(new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.08, wheelR), M.dark));
    car.add(pivot); wheels.push({ pivot, spin, front: z > 0 });
  }
  const beam = new THREE.SpotLight(0xfff1d0, 0, 90, 0.55, 0.6, 1.2);
  beam.position.set(0, 0.9, 2.2); beam.target.position.set(0, -1.5, 22);
  car.add(beam, beam.target);
  return { car, body, wheels, beam, tailMat: tl, wheelBase: Math.abs(wheelPos[0][1] - wheelPos[2][1]), camH };
}
const carParts = buildCar();
scene.add(carParts.car);

// Oncoming traffic: a few simple cars in the other lane
const TRAFFIC_COLORS = CA ? [0xf6c453, 0x7fd1c7, 0xf4efe4, 0x9db8ff, 0xe0533a] : [0xf0e2c0, 0x2f7a6a, 0xd9573f, 0x6a6a72, 0xe8a33d];
function buildTrafficCar(colorHex, truck) {
  const g = new THREE.Group(), paint = toon({ color: colorHex });
  const add = (geo, mat, x, y, z) => { const m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); m.castShadow = true; g.add(m); return m; };
  add(new THREE.BoxGeometry(1.8, 0.6, truck ? 4.9 : 4.3), paint, 0, 0.75, 0);
  add(new THREE.BoxGeometry(1.6, 0.55, truck ? 1.6 : 2.2), M.glass, 0, 1.3, truck ? 0.4 : -0.2);
  add(new THREE.BoxGeometry(1.64, 0.08, truck ? 1.6 : 2.0), paint, 0, 1.6, truck ? 0.4 : -0.25);
  for (const [x, z] of [[0.85, 1.4], [-0.85, 1.4], [0.85, -1.4], [-0.85, -1.4]]) {
    const w = new THREE.Mesh(new THREE.CylinderGeometry(0.36, 0.36, 0.26, 12).rotateZ(Math.PI / 2), M.dark); w.position.set(x, 0.36, z); g.add(w);
  }
  for (const x of [0.6, -0.6]) add(new THREE.BoxGeometry(0.3, 0.14, 0.05), M.hl, x, 0.85, truck ? 2.46 : 2.16);
  return g;
}
const traffic = [];
const trafficRng = mulberry32(SEED ^ 0x7a1);
function updateTraffic(dt) {
  for (let i = traffic.length - 1; i >= 0; i--) {
    const t = traffic[i];
    t.s -= t.v * dt;
    if (t.s < car.s - 120 || t.s / STEP >= road.nFinal - 2 || t.s < 2) { scene.remove(t.mesh); traffic.splice(i, 1); continue; }
    const p = roadPoint(t.s, -LANE);
    t.mesh.position.set(p.x, p.y + 0.02, p.z);
    t.mesh.rotation.y = p.h + Math.PI;
    t.x = p.x; t.z = p.z;
    const dx = t.x - car.x, dz = t.z - car.z;
    if (dx * dx + dz * dz < 6.5 && !t.hit) { // fender bender: knocks the speed off, a little shake
      t.hit = true; car.v *= 0.35; shake = 0.6; toast('bump');
    }
  }
  if (traffic.length < 3 && trafficRng() < dt * 0.25) {
    const s = car.s + 380 + trafficRng() * 250;
    if (s / STEP < road.nFinal - 4) {
      const mesh = buildTrafficCar(TRAFFIC_COLORS[(trafficRng() * TRAFFIC_COLORS.length) | 0], trafficRng() < (FL ? 0.5 : 0.2));
      scene.add(mesh);
      traffic.push({ s, v: 17 + trafficRng() * 8, mesh, x: 0, z: 0, hit: false });
    }
  }
}

// ---------------------------------------------------------------------------
// Driving
// ---------------------------------------------------------------------------
const car = { x: 0, z: 0, y: 0, h: 0, v: 0, steer: 0, pitch: 0, roll: 0, s: 0, lat: 0, d: 0, odo: 0, spin: 0, yv: 0, pitchTerrain: 0 };
const input = { up: false, down: false, left: false, right: false, touchL: false, touchR: false };
let autoDrive = true, throttle = 0, brake = 0, shake = 0;
const WHEELBASE = carParts.wheelBase;
const _carQ = Q();
let cruise = CA ? 24.6 : 21.5; // m/s (55 / 48 mph); W/S nudge it in auto-drive
const LANE = 1.8;
function curvatureAhead(s, dist) {
  let maxC = 0;
  const i0 = Math.floor(s / STEP), n = Math.floor(dist / STEP);
  for (let k = 0; k < n; k += 2) {
    const i = i0 + k;
    if (i + 4 >= road.nFinal) break;
    maxC = Math.max(maxC, (Math.abs(wrapAngle(road.hd[i + 4] - road.hd[i])) / (4 * STEP)) * (1 - 0.55 * (k / n)));
  }
  return maxC;
}
function updateCar(dt) {
  roadQuery(car.x, car.z, _carQ);
  if (_carQ.d !== Infinity) { car.s = _carQ.s; car.lat = _carQ.lat; car.d = _carQ.d; } else car.d = 99;
  const manualSteer = (input.left || input.touchL ? 1 : 0) - (input.right || input.touchR ? 1 : 0);
  if (manualSteer !== 0 && autoDrive) setAuto(false);
  const maxSteer = 0.6 / (1 + car.v / 14);
  let steerTarget, thr = 0, brk = 0;
  if (autoDrive) {
    if (input.up) cruise = Math.min(cruise + dt * 6, 40);
    if (input.down) cruise = Math.max(cruise - dt * 8, 6);
    const la = 9 + Math.abs(car.v) * 0.75;
    const tp = roadPoint(car.s + la, LANE);
    const alpha = wrapAngle(Math.atan2(tp.x - car.x, tp.z - car.z) - car.h);
    steerTarget = clamp(Math.atan(2 * WHEELBASE * Math.sin(alpha) / Math.hypot(tp.x - car.x, tp.z - car.z)), -0.6, 0.6);
    const c = curvatureAhead(car.s, 40 + car.v * 2.5);
    const vt = Math.min(cruise, Math.sqrt(2.6 / Math.max(c, 1e-4)), car.d > ROAD_EDGE ? 10 : 99);
    if (car.v < vt - 0.5) thr = clamp((vt - car.v) * 0.35, 0.15, 1);
    else if (car.v > vt + 1) brk = clamp((car.v - vt) * 0.12, 0, 0.8);
  } else {
    steerTarget = manualSteer * maxSteer;
    if (touchCruise && car.v < 22) thr = 0.6;
    if (input.up) thr = 1;
    if (input.down) brk = 1;
  }
  car.steer += (steerTarget - car.steer) * Math.min(1, dt * (autoDrive ? 5 : 4));
  throttle = lerp(throttle, thr, Math.min(1, dt * 4));
  brake = brk;
  const onRoad = car.d < ROAD_EDGE + 0.3;
  const inWater = !onRoad && groundAt(car.x, car.z) < WATER - 0.1;
  const vmax = CA ? 50 : 42;
  let acc = 0;
  if (brake > 0 && car.v > 0.3) acc -= 11 * brake;
  else if (brake > 0 && !autoDrive) acc -= 4 * brake;
  acc += throttle * (CA ? 6.2 : 5.4) * Math.max(0, 1 - car.v / vmax);
  acc -= 0.25 * Math.sign(car.v) + 0.0011 * car.v * Math.abs(car.v);
  if (!onRoad) acc -= Math.sign(car.v) * (1.5 + Math.abs(car.v) * (inWater ? 0.4 : 0.06));
  acc -= 9.8 * Math.sin(car.pitchTerrain) * 0.6;
  const prevV = car.v;
  car.v += acc * dt;
  if (prevV > 0 && car.v < 0 && (autoDrive || !(brake > 0))) car.v = 0;
  if (!(throttle > 0.01) && !(brake > 0) && Math.abs(car.v) < 0.25) car.v = 0;
  car.v = clamp(car.v, -8, vmax);
  car.h += (car.v * Math.tan(car.steer) / WHEELBASE) * dt;
  car.x += Math.sin(car.h) * car.v * dt;
  car.z += Math.cos(car.h) * car.v * dt;
  car.odo += Math.abs(car.v) * dt;

  const fx = Math.sin(car.h), fz = Math.cos(car.h), lx = Math.cos(car.h), lz = -Math.sin(car.h), hw = WHEELBASE / 2;
  const gF = groundAt(car.x + fx * hw, car.z + fz * hw), gB = groundAt(car.x - fx * hw, car.z - fz * hw);
  const gL = groundAt(car.x + lx * 0.88, car.z + lz * 0.88), gR = groundAt(car.x - lx * 0.88, car.z - lz * 0.88);
  const gy = (gF + gB + gL + gR) / 4;
  car.pitchTerrain = Math.atan2(gF - gB, WHEELBASE);
  car.yv += ((gy - car.y) * 120 - car.yv * 16) * dt;
  car.y += car.yv * dt;
  if (car.y < gy) { car.y = gy; car.yv = Math.max(car.yv, 0); }
  if (car.y > gy + 1.5) car.y = gy + 1.5;
  const lateralG = car.v * car.v * Math.tan(car.steer) / WHEELBASE;
  car.pitch = lerp(car.pitch, -car.pitchTerrain + clamp(-acc * 0.004, -0.03, 0.03), Math.min(1, dt * 10));
  car.roll = lerp(car.roll, Math.atan2(gL - gR, 1.76) - clamp(lateralG * (FL ? 0.009 : 0.006), -0.06, 0.06), Math.min(1, dt * 8));
  const C = carParts.car;
  C.position.set(car.x, car.y, car.z);
  C.rotation.set(car.pitch, car.h, car.roll, 'YXZ');
  car.spin += car.v * dt / 0.4;
  for (const w of carParts.wheels) { w.spin.rotation.x = car.spin; if (w.front) w.pivot.rotation.y = car.steer; }
  carParts.tailMat.color.setHex(brake > 0.05 ? 0xff2a1a : night > 0.4 ? 0xb01818 : 0x7a1010);
}

// ---------------------------------------------------------------------------
// Time of day → palette
// ---------------------------------------------------------------------------
const PRESETS = CA ? [0.3, 0.45, 0.728, 0.752, 0.9] : [0.32, 0.5, 0.62, 0.74, 0.92];
const PRESET_NAMES = CA ? ['sunrise', 'midday', 'golden hour', 'sunset', 'night'] : ['morning', 'noon', 'afternoon', 'dusk', 'night'];
let presetIdx = 2, timeOfDay = PRESETS[presetIdx], timeTarget = timeOfDay, dayCycle = false, night = 0;
const sunDir = new THREE.Vector3(), tmpV = new THREE.Vector3(), tmpC = new THREE.Color();
function updateSky(simT) {
  const ang = (timeOfDay - 0.25) * Math.PI * 2;
  sunDir.set(-Math.cos(ang) * 0.8, Math.sin(ang), 0.55).normalize(); // rises inland (-x), sets over the ocean (+x)
  const elev = sunDir.y;
  night = sstep(0.02, -0.18, elev);
  samplePalette(elev);
  const P = PAL_NOW;
  skyU.top.value.copy(P.top); skyU.mid.value.copy(P.mid); skyU.hor.value.copy(P.hor);
  skyU.sunCol.value.copy(P.sun); skyU.glow.value.copy(P.glow);
  skyU.sunDir.value.copy(sunDir);
  skyU.moonDir.value.set(-sunDir.x * 0.6, Math.max(-sunDir.y, 0.25), 0.7).normalize();
  skyU.night.value = night;
  scene.fog.color.copy(P.hor);
  sun.color.copy(P.light); sun.intensity = P.lightI;
  hemi.color.copy(P.amb); hemi.groundColor.copy(P.ambG); hemi.intensity = P.ambI;
  const lightDir = elev > -0.05 ? sunDir : tmpV.copy(skyU.moonDir.value);
  sun.position.set(car.x + lightDir.x * 300, car.y + Math.max(lightDir.y, 0.1) * 300, car.z + lightDir.z * 300);
  sun.target.position.set(car.x, car.y, car.z);
  stars.material.opacity = night * 0.95;
  carParts.beam.intensity = night * 160;
  cloudLit.color.copy(P.cloud); cloudShade.color.copy(P.cloudS);
  waterMat.color.copy(P.water);
  waterMat.specular.copy(P.glow);
  waterMat.normalMap.offset.set(simT * 0.004, simT * 0.0025);
  for (const r of ridges) r.material.color.copy(P.hor).lerp(P.ridge, r.userData.k);
  postU.ink.value.copy(P.ink);
  postU.shadowTint.value.copy(P.shadow).convertLinearToSRGB();
  postU.hiTint.value.copy(P.hi).convertLinearToSRGB();
  contourInkU.value.copy(P.shadow).lerp(tmpC.setRGB(1, 1, 1), 0.72);
}

// ---------------------------------------------------------------------------
// Camera: chase / driver / cinematic, plus photo-mode orbit
// ---------------------------------------------------------------------------
const CAM_MODES = ['chase', 'driver', 'cinematic'];
let camMode = 0, camYaw = 0, camInit = false;
const look = { yaw: 0, pitch: 0, dragging: false, lastX: 0, lastY: 0, idle: 99 };
const cine = { x: 0, y: 0, z: 0, set: false, s: 0 };
const photo = { on: false, yaw: 0, pitch: 0.25, dist: 10, save: false };
const camPos = new THREE.Vector3(), camLook = new THREE.Vector3();
function updateCamera(dt) {
  if (!look.dragging) { look.idle += dt; if (look.idle > 1.5) { look.yaw *= Math.exp(-dt * 1.5); look.pitch *= Math.exp(-dt * 1.5); } }
  const mode = CAM_MODES[camMode];
  if (photo.on) {
    const cp = Math.cos(photo.pitch);
    camera.position.set(car.x + Math.sin(photo.yaw) * cp * photo.dist, car.y + 1 + Math.sin(photo.pitch) * photo.dist, car.z + Math.cos(photo.yaw) * cp * photo.dist);
    camera.position.y = Math.max(camera.position.y, groundAt(camera.position.x, camera.position.z) + 0.5);
    camera.lookAt(car.x, car.y + 1, car.z);
    camera.fov = lerp(camera.fov, 50, Math.min(1, dt * 4 + 0.05));
  } else if (mode === 'chase') {
    camYaw += wrapAngle(car.h - camYaw) * Math.min(1, dt * 2.8);
    const yaw = camYaw + look.yaw;
    const dist = (FL ? 9.2 : 8.4) + Math.abs(car.v) * 0.03, up = (FL ? 3.0 : 2.5) + look.pitch * 6;
    const tx = car.x - Math.sin(yaw) * dist, tz = car.z - Math.cos(yaw) * dist;
    const target = tmpV.set(tx, Math.max(car.y + up, groundAt(tx, tz) + 1.0), tz);
    if (!camInit) { camPos.copy(target); camInit = true; }
    camPos.lerp(target, Math.min(1, dt * 6));
    camera.position.copy(camPos);
    camera.lookAt(camLook.set(car.x + Math.sin(yaw) * 5, car.y + 1.4, car.z + Math.cos(yaw) * 5));
    camera.fov = lerp(camera.fov, 58 + Math.abs(car.v) * 0.18, Math.min(1, dt * 2));
  } else if (mode === 'driver') {
    const C = carParts.car;
    C.updateMatrixWorld();
    camera.position.set(0.42, carParts.camH, CA ? -0.45 : 0.2).applyMatrix4(C.matrixWorld);
    camera.lookAt(camLook.set(0.42 + Math.sin(look.yaw) * 10, carParts.camH - 0.15 + look.pitch * 10, 10).applyMatrix4(C.matrixWorld));
    camera.fov = lerp(camera.fov, 70, Math.min(1, dt * 3));
  } else {
    if (!cine.set || car.s > cine.s + 45 || Math.hypot(car.x - cine.x, car.z - cine.z) > 260) {
      const s = car.s + 110 + Math.random() * 90;
      if (s / STEP < road.nFinal - 2) {
        const side = Math.random() < 0.5 ? -1 : 1;
        const p = roadPoint(s, side * (FL ? 6.5 + Math.random() * 2.5 : 10 + Math.random() * 18));
        cine.x = p.x; cine.z = p.z; cine.y = Math.max(groundAt(p.x, p.z), WATER) + (FL ? 1.2 + Math.random() * 2 : 1.6 + Math.random() * 5); cine.s = s; cine.set = true;
      }
    }
    camera.position.set(cine.x, cine.y, cine.z);
    camera.lookAt(camLook.set(car.x, car.y + 1, car.z));
    camera.fov = lerp(camera.fov, clamp(900 / Math.max(camera.position.distanceTo(camLook), 1), 18, 60), Math.min(1, dt * 3));
  }
  if (shake > 0) { camera.position.x += (Math.random() - 0.5) * shake * 0.3; camera.position.y += (Math.random() - 0.5) * shake * 0.3; shake = Math.max(0, shake - dt * 1.5); }
  camera.updateProjectionMatrix();
  sky.position.copy(camera.position);
  stars.position.copy(camera.position);
  for (const r of ridges) r.position.set(camera.position.x, 0, camera.position.z);
  water.position.x = Math.round(camera.position.x / 50) * 50;
  water.position.z = Math.round(camera.position.z / 50) * 50;
}

// ---------------------------------------------------------------------------
// World streaming
// ---------------------------------------------------------------------------
const VIEW_M = VIEW_CHUNKS * CHUNK;
function streamWorld(budgetMs) {
  const t0 = performance.now();
  while (road.n < SMOOTH_K + 4 || road.zs[road.nFinal - 1] < car.z + VIEW_M + 200) addRoadSample();
  const ci = Math.floor(car.s / STEP);
  const kMin = Math.max(0, Math.floor((ci - 350) / SEG)), kMax = Math.floor((ci + 520) / SEG);
  for (const k of [...segments.keys()]) if (k < kMin - 1 || k > kMax + 1) disposeSegment(k);
  for (let k = kMin; k <= kMax; k++) if (!segments.has(k) && (k + 1) * SEG + POLE_EVERY + 2 < road.nFinal - 1) buildSegment(k);
  const ccx = Math.floor(car.x / CHUNK), ccz = Math.floor(car.z / CHUNK);
  for (const [key, c] of chunks) if (Math.hypot((c.cx + 0.5) * CHUNK - car.x, (c.cz + 0.5) * CHUNK - car.z) > VIEW_M + CHUNK * 2) disposeChunk(key);
  const zSafe = road.zs[road.nFinal - 1] - CELL * 2;
  const todo = [], fx = Math.sin(car.h), fz = Math.cos(car.h);
  for (let a = -VIEW_CHUNKS - 1; a <= VIEW_CHUNKS + 1; a++) for (let b = -VIEW_CHUNKS - 1; b <= VIEW_CHUNKS + 1; b++) {
    const cx = ccx + a, cz = ccz + b;
    if (chunks.has(hkey(cx, cz))) continue;
    const dx = (cx + 0.5) * CHUNK - car.x, dz = (cz + 0.5) * CHUNK - car.z, dist = Math.hypot(dx, dz);
    if (dist > VIEW_M + CHUNK * 0.7 || (cz + 1) * CHUNK > zSafe) continue;
    todo.push({ cx, cz, p: dist * (1.25 - 0.5 * ((dx * fx + dz * fz) / (dist || 1))) });
  }
  todo.sort((p, q) => p.p - q.p);
  for (const c of todo) { buildChunk(c.cx, c.cz); if (performance.now() - t0 > budgetMs) break; }
  return todo.length;
}
function updateClouds(dt) {
  for (const c of clouds) {
    c.position.x += dt * 3;
    c.lookAt(camera.position.x, c.position.y, camera.position.z); // flat shapes face the viewer
    const dx = c.position.x - car.x, dz = c.position.z - car.z;
    if (dx > 1800) c.position.x -= 3600; else if (dx < -1800) c.position.x += 3600;
    if (dz > 1800) c.position.z -= 3600; else if (dz < -1800) c.position.z += 3600;
  }
}

// ---------------------------------------------------------------------------
// Audio: engine + wind, and a procedural car radio
// ---------------------------------------------------------------------------
const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);
const audio = {
  ctx: null, on: true,
  init() {
    if (this.ctx) return;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    const ctx = this.ctx = new AC();
    this.master = ctx.createGain(); this.master.gain.value = this.on ? 0.6 : 0; this.master.connect(ctx.destination);
    this.filt = ctx.createBiquadFilter(); this.filt.type = 'lowpass'; this.filt.frequency.value = 400; this.filt.Q.value = 0.8;
    this.eng = ctx.createGain(); this.eng.gain.value = 0.04;
    this.filt.connect(this.eng); this.eng.connect(this.master);
    this.o1 = ctx.createOscillator(); this.o1.type = 'sawtooth';
    this.o2 = ctx.createOscillator(); this.o2.type = 'triangle';
    const g2 = ctx.createGain(); g2.gain.value = 0.7;
    this.o1.connect(this.filt); this.o2.connect(g2); g2.connect(this.filt);
    this.o1.start(); this.o2.start();
    const len = ctx.sampleRate * 2, buf = ctx.createBuffer(1, len, ctx.sampleRate), d = buf.getChannelData(0);
    let last = 0;
    for (let i = 0; i < len; i++) { last = (last + 0.02 * (Math.random() * 2 - 1)) / 1.02; d[i] = last * 3.5; }
    const src = ctx.createBufferSource(); src.buffer = buf; src.loop = true;
    this.wf = ctx.createBiquadFilter(); this.wf.type = 'bandpass'; this.wf.frequency.value = 500; this.wf.Q.value = 0.4;
    this.wind = ctx.createGain(); this.wind.gain.value = 0;
    src.connect(this.wf); this.wf.connect(this.wind); this.wind.connect(this.master); src.start();
    radio.init(ctx, this.master);
  },
  update(v, thr, offroad) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime, av = Math.abs(v), tops = [8, 15, 23, 32, 42, 60];
    let g = 0; while (g < tops.length - 1 && av > tops[g]) g++;
    const lo = g ? tops[g - 1] * 0.6 : 0, rpm = clamp((av - lo) / (tops[g] - lo), 0, 1);
    const f = (FL ? 28 : 34) + rpm * (FL ? 50 : 62) + thr * 6;
    this.o1.frequency.setTargetAtTime(f, t, 0.08);
    this.o2.frequency.setTargetAtTime(f * 0.5, t, 0.08);
    this.filt.frequency.setTargetAtTime(220 + rpm * 380 + thr * 300, t, 0.1);
    this.eng.gain.setTargetAtTime((0.03 + thr * 0.035) * (radio.on ? 0.7 : 1), t, 0.15);
    this.wind.gain.setTargetAtTime(Math.min(0.55, (av / 45) ** 2 * (CA ? 0.55 : 0.32)) + (offroad ? Math.min(0.35, av / 40) : 0), t, 0.2);
    this.wf.frequency.setTargetAtTime(offroad ? 160 : 380 + av * 12, t, 0.2);
  },
  setOn(on) { this.on = on; if (this.ctx) this.master.gain.setTargetAtTime(on ? 0.6 : 0, this.ctx.currentTime, 0.1); },
};
const STATION = CA ? {
  name: '101.9 Coastline FM', bpm: 74, swing: 0.16,
  chords: [[53, 57, 60, 64, 67], [52, 55, 59, 62, 66], [50, 53, 57, 60, 64], [48, 52, 55, 59, 62]],
  bass: [41, 40, 38, 36], prog: [0, 1, 2, 3], scale: [72, 74, 76, 79, 81, 84, 86],
} : {
  name: '88.3 Backroads Radio', bpm: 96, swing: 0.3,
  chords: [[52, 56, 59, 62], [57, 61, 64, 67], [59, 63, 66, 69]],
  bass: [40, 45, 47], prog: [0, 0, 0, 0, 1, 1, 0, 0, 2, 1, 0, 2], scale: [64, 67, 69, 70, 71, 74, 76],
};
const radio = {
  on: true, ctx: null, step: 0, bar: 0, next: 0, prevNote: 3,
  init(ctx, dest) {
    this.ctx = ctx;
    this.out = ctx.createGain(); this.out.gain.value = this.on ? 0.5 : 0;
    const hp = ctx.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 70;
    const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = CA ? 3200 : 4200;
    this.out.connect(hp); hp.connect(lp); lp.connect(dest);
    this.pad = ctx.createBiquadFilter(); this.pad.type = 'lowpass'; this.pad.frequency.value = CA ? 1100 : 1800; this.pad.connect(this.out);
    const buf = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate), d = buf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    this.noiseBuf = buf;
    if (CA) {
      const cb = ctx.createBuffer(1, ctx.sampleRate * 3, ctx.sampleRate), cd = cb.getChannelData(0);
      for (let i = 0; i < cd.length; i++) cd[i] = Math.random() < 0.0006 ? (Math.random() * 2 - 1) : (Math.random() * 2 - 1) * 0.015;
      const cs = ctx.createBufferSource(); cs.buffer = cb; cs.loop = true;
      const cg = ctx.createGain(); cg.gain.value = 0.18; cs.connect(cg); cg.connect(this.out); cs.start();
    }
    this.next = ctx.currentTime + 0.3;
    setInterval(() => this.tick(), 25);
  },
  setOn(on) { this.on = on; if (this.out) this.out.gain.setTargetAtTime(on ? 0.5 : 0, this.ctx.currentTime, 0.2); },
  tick() {
    const ctx = this.ctx, six = 60 / STATION.bpm / 4;
    if (this.next < ctx.currentTime - 0.2) this.next = ctx.currentTime + 0.05;
    while (this.next < ctx.currentTime + 0.15) {
      if (this.on) this.play(this.step, this.next + (this.step % 2 ? STATION.swing * six : 0), six);
      this.next += six;
      this.step = (this.step + 1) % 16;
      if (this.step === 0) this.bar++;
    }
  },
  voice(type, freq, t, dur, vol, attack, release, dest = this.out, detune = 0) {
    const o = this.ctx.createOscillator(), g = this.ctx.createGain();
    o.type = type; o.frequency.value = freq; o.detune.value = detune;
    g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(vol, t + attack); g.gain.setTargetAtTime(0, t + Math.max(attack, dur), release / 3);
    o.connect(g); g.connect(dest); o.start(t); o.stop(t + dur + release * 1.5 + 0.05);
  },
  noiseHit(t, vol, type, freq, decay, q = 0.7) {
    const s = this.ctx.createBufferSource(), f = this.ctx.createBiquadFilter(), g = this.ctx.createGain();
    s.buffer = this.noiseBuf; f.type = type; f.frequency.value = freq; f.Q.value = q;
    g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0008, t + decay);
    s.connect(f); f.connect(g); g.connect(this.out); s.start(t, Math.random() * 0.5); s.stop(t + decay + 0.05);
  },
  kick(t, vol) {
    const o = this.ctx.createOscillator(), g = this.ctx.createGain();
    o.frequency.setValueAtTime(110, t); o.frequency.exponentialRampToValueAtTime(42, t + 0.12);
    g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.001, t + 0.32);
    o.connect(g); g.connect(this.out); o.start(t); o.stop(t + 0.35);
  },
  pluck(freq, t, vol) {
    const o = this.ctx.createOscillator(), f = this.ctx.createBiquadFilter(), g = this.ctx.createGain();
    o.type = 'sawtooth'; o.frequency.value = freq;
    f.type = 'lowpass'; f.frequency.setValueAtTime(2600, t); f.frequency.setTargetAtTime(420, t, 0.07);
    g.gain.setValueAtTime(vol, t); g.gain.setTargetAtTime(0, t + 0.02, 0.18);
    o.connect(f); f.connect(g); g.connect(this.out); o.start(t); o.stop(t + 1.0);
  },
  play(step, t, six) {
    const S = STATION, ci = S.prog[this.bar % S.prog.length], chord = S.chords[ci], root = S.bass[ci], r = Math.random();
    if (CA) {
      if (step === 0) for (const n of chord) { this.voice('triangle', mtof(n), t, six * 15, 0.03, 0.6, 1.2, this.pad, -6); this.voice('sine', mtof(n), t, six * 15, 0.025, 0.8, 1.2, this.pad, 7); }
      if (step === 0 || step === 10) this.voice('sine', mtof(root), t, six * 5, 0.2, 0.01, 0.4);
      if (step === 0 || (step === 7 && r < 0.5) || step === 10) this.kick(t, 0.55);
      if (step === 4 || step === 12) { this.noiseHit(t, 0.14, 'bandpass', 1500, 0.16); this.voice('triangle', 190, t, 0.03, 0.05, 0.002, 0.08); }
      if (step % 2 === 0) this.noiseHit(t, step % 4 === 2 ? 0.05 : 0.025, 'highpass', 7000, 0.04);
      if (step % 2 === 0 && r < 0.22) {
        this.prevNote = clamp(this.prevNote + ((Math.random() * 5) | 0) - 2, 0, S.scale.length - 1);
        const f = mtof(S.scale[this.prevNote]);
        this.voice('sine', f, t, 0.05, 0.07, 0.004, 1.4); this.voice('sine', f * 2, t, 0.03, 0.015, 0.004, 0.5);
      }
    } else {
      if (step === 0) for (const n of chord) this.voice('sine', mtof(n + 12), t, six * 15, 0.012, 0.9, 1.0, this.pad, 4);
      if (step % 4 === 0) { const w = [0, 4, 7, 9][step / 4]; this.voice('triangle', mtof(root + w), t, six * 3, 0.17, 0.01, 0.2); this.voice('sine', mtof(root + w), t, six * 3, 0.12, 0.01, 0.2); }
      if (step === 0 || step === 8) this.kick(t, 0.4);
      if (step === 4 || step === 12) this.noiseHit(t, 0.16, 'bandpass', 2600, 0.2, 0.5);
      if (step % 2 === 0) this.noiseHit(t, 0.03, 'bandpass', 5000, 0.07, 0.6);
      if (step === 2 || step === 6 || step === 10 || step === 14) chord.forEach((n, k) => this.pluck(mtof(n + 12), t + k * 0.014, 0.035));
      if (step % 2 === 1 && r < 0.12) { this.prevNote = clamp(this.prevNote + ((Math.random() * 5) | 0) - 2, 0, S.scale.length - 1); this.pluck(mtof(S.scale[this.prevNote]), t, 0.06); }
    }
  },
};

// ---------------------------------------------------------------------------
// Route map: heading-up, flat graphic style
// ---------------------------------------------------------------------------
const mapCv = document.getElementById('map');
const mapCtx = mapCv.getContext('2d');
const MAP_THEME = CA
  ? { bg: '#f6d9a8', sea: '#5079c6', seaLine: '#3b5ea6', ink: '#2a1830', behind: 'rgba(42,24,48,.35)', car: '#ff6b57' }
  : { bg: '#dfe9c8', sea: '#3a6a60', seaLine: '#2a5048', ink: '#14241e', behind: 'rgba(20,36,30,.35)', car: '#e0533a' };
let mapTimer = 0;
function drawMap() {
  const dpr = Math.min(devicePixelRatio || 1, 2), S = mapCv.clientWidth || 180;
  if (mapCv.width !== Math.round(S * dpr)) { mapCv.width = mapCv.height = Math.round(S * dpr); }
  const g = mapCtx, R = S / 2, scale = (R - 8) / 520;
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  g.clearRect(0, 0, S, S);
  g.save();
  g.beginPath(); g.arc(R, R, R - 2, 0, Math.PI * 2); g.clip();
  g.fillStyle = MAP_THEME.bg; g.fillRect(0, 0, S, S);
  const fx = Math.sin(car.h), fz = Math.cos(car.h), rx = -Math.cos(car.h), rz = Math.sin(car.h);
  const P = (x, z) => { const dx = x - car.x, dz = z - car.z; return [R + (dx * rx + dz * rz) * scale, R - (dx * fx + dz * fz) * scale]; };
  const ci = clamp(Math.floor(car.s / STEP), 0, road.nFinal - 1), i0 = Math.max(0, ci - 300), i1 = Math.min(road.nFinal - 1, ci + 320);
  g.strokeStyle = 'rgba(0,0,0,.07)'; g.lineWidth = 1;
  for (let rr = 18; rr < R; rr += 16) { g.beginPath(); g.arc(R, R, rr, 0, Math.PI * 2); g.stroke(); }
  if (CA) { // the ocean
    g.fillStyle = MAP_THEME.sea; g.beginPath();
    for (let i = i0; i <= i1; i += 6) { const [x, y] = P(road.xs[i] + coastDist(road.zs[i]) * OCEAN_SIDE, road.zs[i]); i === i0 ? g.moveTo(x, y) : g.lineTo(x, y); }
    const [ex, ey] = P(road.xs[i1] + 3000 * OCEAN_SIDE, road.zs[i1]), [sx, sy] = P(road.xs[i0] + 3000 * OCEAN_SIDE, road.zs[i0]);
    g.lineTo(ex, ey); g.lineTo(sx, sy); g.closePath(); g.fill();
    g.strokeStyle = MAP_THEME.seaLine; g.lineWidth = 1.5; g.setLineDash([3, 4]);
    g.beginPath();
    for (let i = i0; i <= i1; i += 6) { const [x, y] = P(road.xs[i] + (coastDist(road.zs[i]) + 30) * OCEAN_SIDE, road.zs[i]); i === i0 ? g.moveTo(x, y) : g.lineTo(x, y); }
    g.stroke(); g.setLineDash([]);
  } else { // swamps
    g.fillStyle = MAP_THEME.sea;
    for (let a = -10; a <= 10; a++) for (let b = -10; b <= 10; b++) {
      const wx = Math.round(car.x / 50) * 50 + a * 50, wz = Math.round(car.z / 50) * 50 + b * 50;
      if (flHeight(wx, wz) < 0.4) { const [x, y] = P(wx, wz); g.beginPath(); g.arc(x, y, 50 * scale * 0.75, 0, Math.PI * 2); g.fill(); }
    }
  }
  g.lineCap = 'round'; g.lineJoin = 'round';
  g.strokeStyle = MAP_THEME.behind; g.lineWidth = 3; g.beginPath();
  for (let i = i0; i <= ci; i += 3) { const [x, y] = P(road.xs[i], road.zs[i]); i === i0 ? g.moveTo(x, y) : g.lineTo(x, y); }
  g.stroke();
  g.strokeStyle = MAP_THEME.ink; g.lineWidth = 4; g.beginPath();
  for (let i = ci; i <= i1; i += 3) { const [x, y] = P(road.xs[i], road.zs[i]); i === ci ? g.moveTo(x, y) : g.lineTo(x, y); }
  g.stroke();
  g.fillStyle = MAP_THEME.bg;
  for (let i = Math.ceil(ci / 200) * 200; i <= i1; i += 200) { const [x, y] = P(road.xs[i], road.zs[i]); g.beginPath(); g.arc(x, y, 2.5, 0, 7); g.fill(); }
  g.fillStyle = MAP_THEME.ink;
  for (const t of traffic) { const [x, y] = P(t.x, t.z); g.fillRect(x - 2, y - 2, 4, 4); }
  g.restore();
  g.fillStyle = MAP_THEME.car; g.strokeStyle = MAP_THEME.ink; g.lineWidth = 1.5;
  g.beginPath(); g.moveTo(R, R - 9); g.lineTo(R + 6, R + 6); g.lineTo(R, R + 3); g.lineTo(R - 6, R + 6); g.closePath(); g.fill(); g.stroke();
  g.strokeStyle = MAP_THEME.ink; g.lineWidth = 2; g.beginPath(); g.arc(R, R, R - 2, 0, Math.PI * 2); g.stroke();
  const nx = Math.sin(car.h), ny = -Math.cos(car.h); // screen direction of world +z ("north")
  const lx = R + nx * (R - 14), ly = R + ny * (R - 14);
  g.fillStyle = MAP_THEME.ink; g.beginPath(); g.arc(lx, ly, 9, 0, 7); g.fill();
  g.fillStyle = MAP_THEME.bg; g.font = '700 10px "Space Grotesk", system-ui, sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle';
  g.fillText('N', lx, ly + 0.5);
}

// ---------------------------------------------------------------------------
// UI, settings, input
// ---------------------------------------------------------------------------
const $ = (id) => document.getElementById(id);
const ui = { hud: $('hud'), buttons: $('buttons'), help: $('help'), title: $('title'), spd: $('spd'), dist: $('dist'), mode: $('mode'), paused: $('paused'),
  station: $('station'), region: $('regionName'), toast: $('toast'), coords: $('coords'), clock: $('clock'), photobar: $('photobar'), mapWrap: $('mapwrap'), topleft: $('topleft') };
const LS_KEY = 'twolanes.settings.v2';
const settings = { look: 0, radio: true, sound: true, map: true, cam: 0 };
try { Object.assign(settings, JSON.parse(localStorage.getItem(LS_KEY) || '{}')); } catch (e) { /* storage unavailable */ }
const saveSettings = () => { try { localStorage.setItem(LS_KEY, JSON.stringify(settings)); } catch (e) { /* ignore */ } };
let started = false, paused = false, uiHidden = false, touchCruise = false, ready = false;
const btn = (a) => ui.buttons.querySelector(`[data-act="${a}"]`);
document.body.classList.add('region-' + REGION_ID);
ui.region.textContent = CA ? 'California' : 'North Florida';
ui.station.textContent = STATION.name;
$('seedLabel').textContent = 'SEED ' + String(SEED).padStart(9, '0');
for (const b of document.querySelectorAll('.region')) b.classList.toggle('current', b.dataset.region === REGION_ID);

let toastTimer = 0;
function toast(msg) { ui.toast.textContent = msg; ui.toast.classList.remove('hidden'); clearTimeout(toastTimer); toastTimer = setTimeout(() => ui.toast.classList.add('hidden'), 1500); }
function setAuto(on) { autoDrive = on; btn('auto').classList.toggle('on', on); }
function setCam(i) { camMode = ((i % CAM_MODES.length) + CAM_MODES.length) % CAM_MODES.length; cine.set = false; settings.cam = camMode; saveSettings(); btn('cam').textContent = 'Cam · ' + CAM_MODES[camMode]; }
function setLook(i) {
  settings.look = ((i % LOOKS.length) + LOOKS.length) % LOOKS.length; saveSettings();
  postU.look.value = settings.look;
  contourU.value = settings.look === 2 ? 0 : 1;
  btn('look').textContent = 'Look · ' + LOOKS[settings.look];
}
function nextTime() { presetIdx = (presetIdx + 1) % PRESETS.length; timeTarget = PRESETS[presetIdx]; dayCycle = false; toast(PRESET_NAMES[presetIdx]); }
function setSound(on) { settings.sound = on; saveSettings(); audio.setOn(on); btn('sound').classList.toggle('on', on); }
function setRadio(on) { settings.radio = on; saveSettings(); radio.setOn(on); btn('radio').classList.toggle('on', on); ui.station.classList.toggle('off', !on); }
function setMap(on) { settings.map = on; saveSettings(); btn('map').classList.toggle('on', on); applyChrome(); }
function navigate(region, seed) {
  if (params.has('region') || params.has('seed') || params.has('go')) {
    const u = new URL(location.href);
    u.searchParams.set('region', region);
    if (seed) u.searchParams.set('seed', seed); else u.searchParams.delete('seed');
    u.searchParams.set('go', '1');
    location.href = u.toString();
    return;
  }
  try { sessionStorage.setItem('twolanes.go', '1'); } catch (e) { /* storage unavailable */ }
  location.hash = seed ? `${region}-${seed}` : region;
  location.reload();
}
function gotoRegion(id) { navigate(id, 0); }
function newRoad() { navigate(REGION_ID, ((Math.random() * 1e9) | 0) >>> 0); }
function toggleHelp() { ui.help.classList.toggle('hidden'); btn('help').classList.toggle('on', !ui.help.classList.contains('hidden')); }
function applyChrome() {
  const hide = uiHidden || photo.on || !started;
  ui.hud.classList.toggle('hidden', hide);
  ui.buttons.classList.toggle('hidden', hide);
  ui.topleft.classList.toggle('hidden', hide);
  ui.mapWrap.classList.toggle('hidden', hide || !settings.map);
  ui.photobar.classList.toggle('hidden', !photo.on);
  if (hide) ui.help.classList.add('hidden');
}
function toggleUI() { uiHidden = !uiHidden; applyChrome(); }
function togglePause() { if (photo.on) return; paused = !paused; ui.paused.classList.toggle('hidden', !paused); }
function setPhoto(on) {
  photo.on = on;
  if (on) { photo.yaw = car.h + Math.PI + 0.7; photo.pitch = 0.22; photo.dist = 10; }
  applyChrome();
}
function savePhoto() { photo.save = true; }

ui.buttons.addEventListener('click', (e) => {
  const a = e.target.closest('button')?.dataset.act;
  if (!a) return;
  e.stopPropagation();
  ({ auto: () => setAuto(!autoDrive), cam: () => setCam(camMode + 1), time: nextTime, look: () => setLook(settings.look + 1),
     photo: () => setPhoto(true), radio: () => setRadio(!radio.on), sound: () => setSound(!audio.on), map: () => setMap(!settings.map),
     region: () => gotoRegion(CA ? 'fl' : 'ca'), new: newRoad, help: toggleHelp })[a]();
  e.target.blur();
});
ui.buttons.addEventListener('pointerdown', (e) => e.stopPropagation());
ui.photobar.addEventListener('pointerdown', (e) => e.stopPropagation());
ui.photobar.addEventListener('click', (e) => {
  const a = e.target.closest('button')?.dataset.act;
  if (a === 'shoot') savePhoto(); else if (a === 'exit') setPhoto(false); else if (a === 'look') setLook(settings.look + 1); else if (a === 'time') nextTime();
});
setAuto(true);
setLook(settings.look);
setCam(settings.cam);
btn('sound').classList.toggle('on', settings.sound);
btn('radio').classList.toggle('on', settings.radio);
btn('map').classList.toggle('on', settings.map);
audio.on = settings.sound; radio.on = settings.radio;
ui.station.classList.toggle('off', !settings.radio);

function wakeAudio() { audio.init(); if (audio.ctx && audio.ctx.state === 'suspended') audio.ctx.resume(); }
function start() {
  if (started || !ready) return;
  started = true;
  ui.title.classList.add('hidden');
  applyChrome();
  wakeAudio();
}
for (const b of document.querySelectorAll('.region')) b.addEventListener('click', (e) => { e.stopPropagation(); if (b.dataset.region === REGION_ID) start(); else gotoRegion(b.dataset.region); });
ui.title.addEventListener('click', start);
addEventListener('pointerdown', wakeAudio);

const KEYMAP = { ArrowUp: 'up', KeyW: 'up', ArrowDown: 'down', KeyS: 'down', ArrowLeft: 'left', KeyA: 'left', ArrowRight: 'right', KeyD: 'right' };
addEventListener('keydown', (e) => {
  wakeAudio();
  if (!started) { if (e.code === 'Digit1') gotoRegion('ca'); else if (e.code === 'Digit2') gotoRegion('fl'); else start(); return; }
  const k = KEYMAP[e.code];
  if (k) { input[k] = true; e.preventDefault(); return; }
  if (e.repeat) return;
  if (photo.on) {
    if (e.code === 'Enter' || e.code === 'Space') { savePhoto(); e.preventDefault(); }
    else if (e.code === 'KeyF' || e.code === 'Escape') setPhoto(false);
    else if (e.code === 'KeyX') setLook(settings.look + 1);
    else if (e.code === 'KeyT') nextTime();
    return;
  }
  switch (e.code) {
    case 'KeyE': setAuto(!autoDrive); break;
    case 'KeyC': setCam(camMode + 1); toast('camera · ' + CAM_MODES[camMode]); break;
    case 'KeyT': nextTime(); break;
    case 'KeyY': dayCycle = !dayCycle; toast(dayCycle ? 'day cycle on' : 'day cycle off'); break;
    case 'KeyX': setLook(settings.look + 1); toast('look · ' + LOOKS[settings.look]); break;
    case 'KeyF': setPhoto(true); break;
    case 'KeyR': setRadio(!radio.on); toast(radio.on ? STATION.name : 'radio off'); break;
    case 'KeyV': setSound(!audio.on); toast(audio.on ? 'sound on' : 'muted'); break;
    case 'KeyM': setMap(!settings.map); break;
    case 'KeyH': toggleHelp(); break;
    case 'KeyU': toggleUI(); break;
    case 'KeyN': newRoad(); break;
    case 'KeyG': gotoRegion(CA ? 'fl' : 'ca'); break;
    case 'KeyP': case 'Escape': togglePause(); break;
  }
});
addEventListener('keyup', (e) => { const k = KEYMAP[e.code]; if (k) input[k] = false; });
addEventListener('blur', () => { for (const k in input) input[k] = false; });

const activeTouches = new Map();
canvas.addEventListener('pointerdown', (e) => {
  if (!started) { start(); return; }
  if (e.pointerType === 'touch' && !photo.on) {
    activeTouches.set(e.pointerId, e.clientX < innerWidth / 2 ? 'L' : 'R');
    touchCruise = true; updateTouch();
  } else {
    look.dragging = true; look.lastX = e.clientX; look.lastY = e.clientY;
    try { canvas.setPointerCapture(e.pointerId); } catch (err) { /* synthetic pointer */ }
  }
});
canvas.addEventListener('pointermove', (e) => {
  if (!look.dragging) return;
  const dx = e.clientX - look.lastX, dy = e.clientY - look.lastY;
  if (photo.on) { photo.yaw -= dx * 0.008; photo.pitch = clamp(photo.pitch + dy * 0.005, -0.05, 1.3); }
  else { look.yaw = clamp(look.yaw - dx * 0.006, -Math.PI, Math.PI); look.pitch = clamp(look.pitch + dy * 0.004, -0.3, 0.8); }
  look.lastX = e.clientX; look.lastY = e.clientY; look.idle = 0;
});
const endPointer = (e) => { if (activeTouches.has(e.pointerId)) { activeTouches.delete(e.pointerId); updateTouch(); } look.dragging = false; look.idle = 0; };
canvas.addEventListener('pointerup', endPointer);
canvas.addEventListener('pointercancel', endPointer);
canvas.addEventListener('wheel', (e) => { if (photo.on) { photo.dist = clamp(photo.dist * (1 + e.deltaY * 0.001), 4, 60); e.preventDefault(); } }, { passive: false });
function updateTouch() { const v = [...activeTouches.values()]; input.touchL = v.includes('L'); input.touchR = v.includes('R'); }
addEventListener('resize', resize);

// ---------------------------------------------------------------------------
// HUD text
// ---------------------------------------------------------------------------
const BASE_LL = CA ? [34.0259, -118.7798] : [30.4383, -84.2807];
const fmtCoord = (v, pos, neg) => Math.abs(v).toFixed(4) + '°' + (v >= 0 ? pos : neg);
function updateHud() {
  ui.spd.textContent = String(Math.round(Math.abs(car.v) * 2.23694)).padStart(2, '0');
  ui.dist.textContent = (car.odo / 1609.34).toFixed(1) + ' mi';
  ui.mode.textContent = autoDrive ? 'auto · ' + Math.round(cruise * 2.23694) : 'manual';
  const lat = BASE_LL[0] + car.z / 111320, lon = BASE_LL[1] - car.x / (111320 * Math.cos(lat * Math.PI / 180));
  ui.coords.textContent = fmtCoord(lat, 'N', 'S') + '  ' + fmtCoord(lon, 'E', 'W');
  const mins = Math.floor(timeOfDay * 24 * 60);
  ui.clock.textContent = String(Math.floor(mins / 60)).padStart(2, '0') + ':' + String(mins % 60).padStart(2, '0');
}

// ---------------------------------------------------------------------------
// Boot & main loop
// ---------------------------------------------------------------------------
{
  while (road.nFinal < 400) addRoadSample();
  const p = roadPoint(500, LANE);
  car.x = p.x; car.z = p.z; car.h = p.h; car.s = 500; camYaw = p.h; car.y = p.y; car.v = 16;
}
let last = performance.now(), simT = 0, bootFrames = 0, frameEma = 1 / 60, resTimer = 0;
const stats = { frames: 0 };
function frame(now) {
  const rawDt = (now - last) / 1000, dt = Math.min(0.05, rawDt);
  last = now;
  stats.frames++;
  if (!ready) {
    const left = streamWorld(40);
    $('loadfill').style.width = Math.min(100, 100 * (1 - left / (Math.PI * VIEW_CHUNKS * VIEW_CHUNKS))) + '%';
    if (left === 0 || ++bootFrames > 400) {
      ready = true;
      document.body.classList.add('ready');
      $('start').textContent = 'Choose a coast';
      if (AUTOGO) start();
    }
  } else {
    streamWorld(started ? 6 : 12);
    // dynamic resolution: keep things smooth on slower machines
    frameEma = lerp(frameEma, rawDt, 0.05);
    resTimer += rawDt;
    if (started && resTimer > 2 && DYNRES) {
      resTimer = 0;
      if (frameEma > 1 / 38 && prScale > 0.55) { prScale = Math.max(0.55, prScale - 0.15); resize(); }
      else if (frameEma < 1 / 57 && prScale < 1) { prScale = Math.min(1, prScale + 0.1); resize(); }
    }
  }
  const frozen = paused || photo.on;
  if (!paused) {
    simT += dt;
    if (dayCycle) timeTarget = (timeTarget + dt / 720) % 1;
    let dT = timeTarget - timeOfDay;
    if (dT < -0.5) dT += 1;
    if (dT > 0.5) dT -= 1;
    timeOfDay = (timeOfDay + dT * Math.min(1, dt * (dayCycle ? 10 : 1.4)) + 1) % 1;
    if (ready && !frozen) { updateCar(dt); updateTraffic(dt); }
    updateClouds(dt);
  }
  updateSky(simT);
  updateCamera(paused ? 0 : dt);
  audio.update(frozen ? 0 : car.v, frozen ? 0 : throttle, car.d > ROAD_EDGE + 0.3);
  if (started) {
    updateHud();
    mapTimer -= dt;
    if (settings.map && mapTimer <= 0 && !photo.on && !uiHidden) { mapTimer = 0.1; drawMap(); }
  }
  postU.time.value = simT % 1000;
  postU.near.value = camera.near; postU.far.value = camera.far;
  renderer.setRenderTarget(rt);
  renderer.render(scene, camera);
  renderer.setRenderTarget(null);
  renderer.render(postScene, postCam);
  if (photo.save) {
    photo.save = false;
    const a = document.createElement('a');
    a.href = canvas.toDataURL('image/png');
    a.download = `two-lanes-${REGION_ID}-${SEED}-${Date.now()}.png`;
    a.click();
    toast('photo saved');
  }
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

// Hooks for the automated tests (tests/smoke.cjs)
window.__game = {
  car, road, chunks, segments, traffic, stats, SEED, REGION_ID, ROAD_EDGE,
  heightAt, baseH, roadXAtZ, coastDist,
  isReady: () => ready, start,
  setTime: (t) => { timeOfDay = timeTarget = t; }, setCam, setLook, setPhoto, setMap,
  state: () => ({ autoDrive, camMode, look: settings.look, photo: photo.on, map: settings.map, paused, started, prScale, cruise, steer: car.steer }),
};
