// Two Lanes — an endless, procedurally generated drive.
// Two regions: the California coast and the North Florida backroads.
import * as THREE from 'three';

// ---------------------------------------------------------------------------
// Seed, region, RNG and noise
// ---------------------------------------------------------------------------
const params = new URLSearchParams(location.search);
const SEED = (parseInt(params.get('seed'), 10) || ((Math.random() * 1e9) | 0)) >>> 0;
const REGION_ID = params.get('region') === 'fl' ? 'fl' : 'ca';
const CA = REGION_ID === 'ca', FL = !CA;
const AUTOGO = params.get('go') === '1';

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
// World constants
// ---------------------------------------------------------------------------
const ROAD_HALF = 3.6;      // half width of the asphalt
const ROAD_EDGE = 4.9;      // half width incl. shoulder
const FLAT = 6.5;           // terrain is flattened under the road out to this distance
const BLEND = 32;           // ... and blends back to natural terrain over this distance
const STEP = 2;             // metres between road samples
const SMOOTH_K = 50;        // road elevation smoothing window (samples each side)
const WATER = 0;            // sea level (CA) / swamp water table (FL)
const CHUNK = 64, RES = 32; // terrain chunk size (m) and resolution (quads)
const VIEW_CHUNKS = 8;      // terrain radius in chunks
const CELL = 42;            // spatial hash cell for road lookup
const OCEAN_SIDE = 1;       // CA: the Pacific is on the +x side of the road (driver's left, heading "north")

// ---------------------------------------------------------------------------
// Road centreline (declared early: CA terrain needs the road's x at a given z)
// ---------------------------------------------------------------------------
const road = { xs: [], zs: [], ys: [], raw: [], hd: [], n: 0, nFinal: 0 };
function roadXAtZ(z) {
  const zs = road.zs, n = road.n;
  if (n === 0) return 0;
  if (z <= zs[0]) return road.xs[0];
  if (z >= zs[n - 1]) return road.xs[n - 1];
  let lo = 0, hi = n - 1;
  while (hi - lo > 1) { const m = (lo + hi) >> 1; if (zs[m] <= z) lo = m; else hi = m; }
  const t = (z - zs[lo]) / (zs[hi] - zs[lo]);
  return road.xs[lo] + (road.xs[hi] - road.xs[lo]) * t;
}

// ---------------------------------------------------------------------------
// Terrain height (per region)
// ---------------------------------------------------------------------------
function mountainFactor(x, z) {
  const m = 0.5 + 0.5 * noise(x / 1400 - 40.2, z / 1400 + 20.6);
  return m * m;
}
// California: hills that rise inland, cliffs and beaches dropping to the Pacific.
function coastDist(z) { return 55 + 110 * (0.5 + 0.5 * noise(z / 1100 + 5.1, 3.3)) + 25 * noise(z / 280, 8.8); }
function cliffiness(z) { return 0.5 + 0.5 * noise(z / 520, 1.7); }
function caLand(x, z) {
  const m = mountainFactor(x, z);
  let h = 16 + 14 * noise(x / 900, z / 900) + fbm(x / 260, z / 260, 5) * (8 + 34 * m);
  const r = 1 - Math.abs(noise(x / 480 + 9.4, z / 480 - 9.8));
  h += (r * r - 0.3) * (6 + 20 * m);
  h += noise(x / 45, z / 45) * 0.9;
  return h;
}
function caHeight(x, z) {
  const u = (x - roadXAtZ(z)) * OCEAN_SIDE; // > 0: towards the ocean
  const m = mountainFactor(x, z);
  let h = caLand(x, z) + sstep(20, 420, -u) * (45 + 85 * m);
  h = Math.max(h, 3.5);
  const c = coastDist(z);
  if (u > 0) h = lerp(h, 9 + 5 * noise(x / 160, z / 160), sstep(0, c * 0.6, u)); // low coastal terrace
  if (u > c - 140) {
    const cl = cliffiness(z);
    const width = lerp(120, 16, cl);
    const t = sstep(c - width, c, u);
    const shore = 1.6 - (u - c) * (u > c ? 0.16 : 0.02) + noise(x / 30, z / 30) * 0.4;
    h = lerp(h, shore, t);
  }
  return Math.max(h, -26);
}
// North Florida: nearly flat sandy ground, low wet spots full of swamp water.
function swampiness(x, z) { return sstep(0.12, 0.5, noise(x / 650 + 3.3, z / 650 - 8.1)); }
function flHeight(x, z) {
  return 3.2 + 2.0 * noise(x / 700, z / 700) + 1.3 * fbm(x / 170, z / 170, 3) +
         0.22 * noise(x / 16, z / 16) - swampiness(x, z) * 4.6;
}
const baseH = CA ? caHeight : flHeight;
function roadRawHeight(x, z, s) {
  if (CA) return clamp(8 + 0.3 * (caLand(x, z) - 16) + 3 * Math.sin(s / 140), 6, 30);
  return Math.max(2.2 + 0.6 * noise(x / 500, z / 500), 1.3);
}

// ---------------------------------------------------------------------------
// Road: an endless centreline generated ahead of the car
// ---------------------------------------------------------------------------
const ph = Array.from({ length: 6 }, () => rng() * Math.PI * 2);
const AMP_SCALE = CA ? 1 : 0.5, LEN_SCALE = CA ? 1 : 1.9;
const roadAmp = [0.6 + rng() * 0.15, 0.32 + rng() * 0.1, 0.2 + rng() * 0.06, 0.1].map((a) => a * AMP_SCALE);
function headingAt(s) {
  // Bounded sum of sines: the road wanders but always progresses along +z, so it never loops back.
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
  const i = road.n;
  let x = 0, z = 0;
  const s = i * STEP;
  const h = headingAt(s);
  if (i > 0) {
    const hm = headingAt(s - STEP / 2);
    x = road.xs[i - 1] + Math.sin(hm) * STEP;
    z = road.zs[i - 1] + Math.cos(hm) * STEP;
  }
  road.xs.push(x); road.zs.push(z); road.hd.push(h);
  road.raw.push(roadRawHeight(x, z, s));
  road.ys.push(undefined);
  road.n++;
  const key = hkey(Math.floor(x / CELL), Math.floor(z / CELL));
  let arr = hash.get(key); if (!arr) hash.set(key, (arr = [])); arr.push(i);
  const f = road.n - 1 - SMOOTH_K; // finalise (smooth) elevation of the sample SMOOTH_K behind
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
      const i = arr[k];
      const ddx = road.xs[i] - x, ddz = road.zs[i] - z;
      const d2 = ddx * ddx + ddz * ddz;
      if (d2 < best) { best = d2; bi = i; }
    }
  }
  out.d = Infinity;
  if (bi < 0) return out;
  let bd = Infinity;
  for (let a = bi - 1; a <= bi; a++) {
    const b = a + 1;
    if (a < 0 || b >= road.n) continue;
    const ax = road.xs[a], az = road.zs[a];
    const sx = road.xs[b] - ax, sz = road.zs[b] - az;
    const len2 = sx * sx + sz * sz;
    const t = clamp(((x - ax) * sx + (z - az) * sz) / len2, 0, 1);
    const px = ax + sx * t - x, pz = az + sz * t - z;
    const d2 = px * px + pz * pz;
    if (d2 < bd) {
      bd = d2;
      const len = Math.sqrt(len2), dx = sx / len, dz = sz / len;
      const ya = road.ys[a] ?? road.raw[a], yb = road.ys[b] ?? road.raw[b];
      out.y = ya + (yb - ya) * t;
      out.s = (a + t) * STEP; out.i = a; out.t = t; out.dx = dx; out.dz = dz;
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
const _gq = Q();
function groundAt(x, z) { // drivable surface
  const h = heightAt(x, z, _gq);
  if (_gq.d < ROAD_HALF) return _gq.y + 0.03;
  if (_gq.d < ROAD_EDGE) return lerp(_gq.y + 0.03, _gq.y - 0.12, (_gq.d - ROAD_HALF) / (ROAD_EDGE - ROAD_HALF));
  return Math.max(h, WATER - 0.6);
}
function roadPoint(s, lat = 0) {
  const f = clamp(s / STEP, 0, road.nFinal - 2);
  const i = Math.floor(f), t = f - i;
  const x = lerp(road.xs[i], road.xs[i + 1], t), z = lerp(road.zs[i], road.zs[i + 1], t);
  const dx = road.xs[i + 1] - road.xs[i], dz = road.zs[i + 1] - road.zs[i];
  const l = Math.hypot(dx, dz) || 1;
  return { x: x + (-dz / l) * lat, z: z + (dx / l) * lat, y: lerp(road.ys[i], road.ys[i + 1], t), h: Math.atan2(dx, dz) };
}

// ---------------------------------------------------------------------------
// Renderer, scene, lights
// ---------------------------------------------------------------------------
const canvas = document.getElementById('game');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.08;

const scene = new THREE.Scene();
const FOG = CA ? [90, 560] : [45, 430];
scene.fog = new THREE.Fog(0xbcd9ef, FOG[0], FOG[1]);
const camera = new THREE.PerspectiveCamera(60, innerWidth / innerHeight, 0.2, 9000);

const hemi = new THREE.HemisphereLight(0xcfe6ff, 0x6b7a4a, 1.1);
scene.add(hemi);
const sun = new THREE.DirectionalLight(0xfff2dd, 2.6);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
Object.assign(sun.shadow.camera, { left: -70, right: 70, top: 70, bottom: -70, near: 1, far: 700 });
sun.shadow.bias = -0.0004;
sun.shadow.normalBias = 0.4;
scene.add(sun, sun.target);

const skyUniforms = {
  top: { value: new THREE.Color(0x4a86d4) },
  horizon: { value: new THREE.Color(0xbcd9ef) },
  bottom: { value: new THREE.Color(0x8fa7b8) },
  sunDir: { value: new THREE.Vector3(0, 1, 0) },
  sunColor: { value: new THREE.Color(0xfff4e0) },
};
const sky = new THREE.Mesh(
  new THREE.SphereGeometry(6000, 32, 16),
  new THREE.ShaderMaterial({
    uniforms: skyUniforms, side: THREE.BackSide, depthWrite: false, fog: false,
    vertexShader: `varying vec3 vDir; void main(){ vDir = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
    fragmentShader: `
      uniform vec3 top, horizon, bottom, sunDir, sunColor; varying vec3 vDir;
      void main(){
        vec3 d = normalize(vDir); float h = d.y;
        vec3 col = mix(horizon, top, pow(clamp(h,0.0,1.0), 0.5));
        if (h < 0.0) col = mix(horizon, bottom, clamp(-h*4.0, 0.0, 1.0));
        float sd = max(dot(d, normalize(sunDir)), 0.0);
        col += sunColor * (smoothstep(0.9990, 0.9995, sd) * 2.5 + pow(sd, 12.0) * 0.38 + pow(sd, 3.0) * 0.1);
        gl_FragColor = vec4(col, 1.0);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }`,
  })
);
sky.renderOrder = -10;
scene.add(sky);

const stars = (() => {
  const g = new THREE.BufferGeometry(), pos = [];
  const r = mulberry32(99);
  for (let i = 0; i < 1600; i++) {
    const u = r() * 2 - 1, th = r() * Math.PI * 2, y = Math.abs(u);
    const rr = Math.sqrt(1 - y * y);
    pos.push(Math.cos(th) * rr * 5500, y * 5500, Math.sin(th) * rr * 5500);
  }
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  const m = new THREE.PointsMaterial({ color: 0xffffff, size: 1.6, sizeAttenuation: false, transparent: true, opacity: 0, fog: false, depthWrite: false });
  const p = new THREE.Points(g, m); p.renderOrder = -9; return p;
})();
scene.add(stars);

// Water: the Pacific (CA) or tea-coloured swamp water (FL), with a scrolling ripple normal map.
function makeRippleTexture() {
  const N = 256, cv = document.createElement('canvas'); cv.width = cv.height = N;
  const g = cv.getContext('2d'), img = g.createImageData(N, N);
  const nz = makeNoise2D(mulberry32(42));
  const P = (x, y) => { // tileable height
    const a = x / N * Math.PI * 2, b = y / N * Math.PI * 2;
    return nz(Math.cos(a) * 3, Math.sin(a) * 3 + Math.cos(b) * 3) + 0.5 * nz(Math.sin(b) * 6 + 20, Math.cos(a) * 6);
  };
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    const dx = P(x + 1, y) - P(x - 1, y), dy = P(x, y + 1) - P(x, y - 1);
    const i = (y * N + x) * 4;
    img.data[i] = 128 + dx * 160; img.data[i + 1] = 128 + dy * 160; img.data[i + 2] = 255; img.data[i + 3] = 255;
  }
  g.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(cv);
  t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(60, 60);
  return t;
}
const WATER_BASE = CA ? 0x2f6f92 : 0x3d4a30;
const waterMat = new THREE.MeshPhongMaterial({
  color: WATER_BASE, shininess: CA ? 90 : 120, specular: CA ? 0x9ab8d0 : 0x8a8f70,
  transparent: true, opacity: CA ? 0.9 : 0.94, normalMap: makeRippleTexture(), normalScale: new THREE.Vector2(0.35, 0.35),
});
const water = new THREE.Mesh(new THREE.PlaneGeometry(9000, 9000), waterMat);
water.rotation.x = -Math.PI / 2;
water.position.y = WATER;
water.receiveShadow = true;
scene.add(water);

// ---------------------------------------------------------------------------
// Ground colours (per region)
// ---------------------------------------------------------------------------
const PAL = CA ? {
  goldA: col(0xd4ae62), goldB: col(0xbb914c), chap: col(0x6c7646), chapB: col(0x56603a),
  green: col(0x8a9a52), rock: col(0xa48d6c), rockB: col(0x8a7a66), sand: col(0xe8d6a8), wetSand: col(0xbfae86),
  dirt: col(0xb39c74),
} : {
  grassA: col(0x76a243), grassB: col(0x557f30), sand: col(0xd2c495), mud: col(0x4f5530),
  under: col(0x3a3c26), pine: col(0x8c8a52), dirt: col(0xbcae83), rock: col(0x9a9480),
};
const _c = [0, 0, 0], _g = [0, 0, 0], _r = [0, 0, 0];
function groundColor(x, z, h, ny, d, out) {
  const vary = clamp(0.5 + 0.45 * noise(x / 38, z / 38) + 0.12 * noise(x / 9, z / 9), 0, 1);
  if (CA) {
    mix3(_g, PAL.goldA, PAL.goldB, vary);
    const chap = sstep(-0.1, 0.4, noise(x / 230 + 7, z / 230 - 3) + 0.25 * noise(x / 60, z / 60));
    mix3(_r, PAL.chap, PAL.chapB, vary); mix3(_g, _g, _r, chap * 0.85);
    mix3(_g, _g, PAL.green, sstep(0.3, 0.7, noise(x / 900 - 20, z / 900)) * 0.4);
    mix3(_r, PAL.rock, PAL.rockB, vary);
    mix3(out, _g, _r, sstep(0.84, 0.62, ny));
    if (h < 3.2) mix3(out, out, h < 0.6 ? PAL.wetSand : PAL.sand, sstep(3.2, 1.6, h));
  } else {
    mix3(_g, PAL.grassA, PAL.grassB, vary);
    const sandy = sstep(0.15, 0.55, noise(x / 110 + 2, z / 110 - 6));
    mix3(_g, _g, PAL.pine, sstep(-0.1, 0.4, noise(x / 380 + 50, z / 380 - 50)) * 0.45);
    mix3(_g, _g, PAL.sand, sandy * 0.4);
    mix3(out, _g, PAL.mud, sstep(1.5, 0.3, h));
    if (h < WATER) mix3(out, out, PAL.under, 0.7);
  }
  if (d < FLAT + 4) mix3(out, out, PAL.dirt, sstep(FLAT + 4, FLAT - 1, d) * 0.75);
  return out;
}

// ---------------------------------------------------------------------------
// Plant / prop templates (baked once, merged per chunk)
// ---------------------------------------------------------------------------
const K0 = 0, K1 = 1, K2 = 2; // three colour slots per template (trunk, foliage, extra)
const M4 = new THREE.Matrix4();
function bake(parts) {
  const pos = [], nrm = [], kind = [];
  for (const [geo, k] of parts) {
    const g = geo.index ? geo.toNonIndexed() : geo; g.computeVertexNormals();
    pos.push(...g.attributes.position.array); nrm.push(...g.attributes.normal.array);
    for (let i = 0; i < g.attributes.position.count; i++) kind.push(k);
  }
  return { pos: new Float32Array(pos), nrm: new Float32Array(nrm), kind: new Uint8Array(kind), count: kind.length };
}
// A leaf/frond: a thin box with an inner rising part and an outer drooping part.
function frond(len, width, yaw, tilt, droop, y, x0 = 0) {
  const a = new THREE.BoxGeometry(width, 0.06, len * 0.5).translate(0, 0, len * 0.25);
  a.applyMatrix4(M4.makeRotationX(tilt));
  const b = new THREE.BoxGeometry(width * 0.8, 0.05, len * 0.55).translate(0, 0, len * 0.27);
  b.applyMatrix4(M4.makeRotationX(tilt + droop));
  b.translate(0, -Math.sin(tilt) * len * 0.5, Math.cos(tilt) * len * 0.5);
  const parts = [a, b];
  for (const p of parts) { p.applyMatrix4(M4.makeRotationY(yaw)); p.translate(x0, y, 0); }
  return parts;
}
function palm(height, n, len, width, lean, tiltMin, tiltMax, ball) {
  const parts = [];
  const segs = 4;
  for (let i = 0; i < segs; i++) { // slightly curved trunk
    const y0 = (i / segs) * height, hgt = height / segs;
    const r0 = lerp(0.3, 0.17, i / segs), r1 = lerp(0.3, 0.17, (i + 1) / segs);
    const g = new THREE.CylinderGeometry(r1, r0, hgt, 6).translate(lean * (i / segs) ** 2 * height * 0.1, y0 + hgt / 2, 0);
    parts.push([g, K0]);
  }
  const tx = lean * height * 0.1;
  for (let k = 0; k < n; k++) {
    const yaw = (k / n) * Math.PI * 2 + (k % 2) * 0.3;
    const tilt = lerp(tiltMin, tiltMax, (k * 0.618) % 1);
    for (const g of frond(len, width, yaw, tilt, 0.5, height, tx)) parts.push([g, K1]);
  }
  if (ball) parts.push([new THREE.IcosahedronGeometry(ball, 0).translate(tx, height, 0), K2]);
  return bake(parts);
}

const T = {};
T.post = bake([
  [new THREE.BoxGeometry(0.14, 1.0, 0.14).translate(0, 0.5, 0), K2],
  [new THREE.BoxGeometry(0.15, 0.12, 0.15).translate(0, 0.86, 0), K1],
]);
T.rock = bake([[new THREE.DodecahedronGeometry(1, 0).scale(1.3, 0.8, 1.1).translate(0, 0.25, 0), K2]]);
T.shrub = bake([[new THREE.IcosahedronGeometry(0.9, 0).scale(1.3, 0.75, 1.3).translate(0, 0.45, 0), K1]]);
if (CA) {
  T.fanPalm = palm(13, 9, 3.0, 0.42, 1, 0.15, 0.55, 0.55);    // tall skinny LA palm
  T.datePalm = palm(6.5, 14, 4.2, 0.6, 0.4, -0.25, 0.45, 0.7); // shorter, fuller
  T.oak = bake([
    [new THREE.CylinderGeometry(0.22, 0.34, 2.2, 5).translate(0, 1.1, 0), K0],
    [new THREE.IcosahedronGeometry(2.3, 0).scale(1.3, 0.75, 1.2).translate(0, 3.3, 0), K1],
    [new THREE.IcosahedronGeometry(1.6, 0).scale(1.2, 0.8, 1).translate(1.7, 2.9, 0.6), K1],
    [new THREE.IcosahedronGeometry(1.5, 0).scale(1.2, 0.8, 1).translate(-1.6, 2.8, -0.7), K1],
  ]);
  T.cypress = bake([ // wind-swept Monterey cypress
    [new THREE.CylinderGeometry(0.2, 0.35, 3.6, 5).applyMatrix4(M4.makeRotationZ(-0.25)).translate(0.4, 1.7, 0), K0],
    [new THREE.CylinderGeometry(2.6, 3.0, 0.9, 7).translate(1.5, 3.8, 0), K1],
    [new THREE.CylinderGeometry(1.9, 2.3, 0.8, 7).translate(2.3, 4.5, 0.4), K1],
    [new THREE.CylinderGeometry(1.6, 2.0, 0.8, 7).translate(0.2, 3.2, -0.6), K1],
  ]);
  T.euc = bake([
    [new THREE.CylinderGeometry(0.16, 0.3, 11, 5).translate(0, 5.5, 0), K2],
    [new THREE.IcosahedronGeometry(1.9, 0).scale(1, 1.3, 1).translate(0.4, 10.5, 0), K1],
    [new THREE.IcosahedronGeometry(1.5, 0).scale(1, 1.3, 1).translate(-1.0, 8.6, 0.6), K1],
    [new THREE.IcosahedronGeometry(1.3, 0).translate(0.9, 7.6, -0.8), K1],
  ]);
} else {
  T.slash = bake([ // tall straight slash pine with a small crown up top
    [new THREE.CylinderGeometry(0.15, 0.28, 12, 6).translate(0, 6, 0), K0],
    [new THREE.IcosahedronGeometry(1.6, 0).scale(1.3, 0.8, 1.2).translate(0, 12.2, 0), K1],
    [new THREE.IcosahedronGeometry(1.3, 0).scale(1.2, 0.7, 1.2).translate(1.1, 11.1, 0.3), K1],
    [new THREE.IcosahedronGeometry(1.1, 0).scale(1.2, 0.7, 1.2).translate(-0.9, 10.6, -0.5), K1],
  ]);
  const oakParts = [
    [new THREE.CylinderGeometry(0.4, 0.6, 2.6, 6).translate(0, 1.3, 0), K0],
    [new THREE.CylinderGeometry(0.18, 0.3, 4.5, 5).applyMatrix4(M4.makeRotationZ(1.1)).translate(1.9, 3.2, 0), K0],
    [new THREE.CylinderGeometry(0.18, 0.3, 4.5, 5).applyMatrix4(M4.makeRotationZ(-1.0)).translate(-1.8, 3.3, 0.4), K0],
    [new THREE.IcosahedronGeometry(2.6, 0).scale(1.5, 0.6, 1.3).translate(0, 4.6, 0), K1],
    [new THREE.IcosahedronGeometry(2.2, 0).scale(1.4, 0.55, 1.2).translate(3.6, 4.1, 0.6), K1],
    [new THREE.IcosahedronGeometry(2.1, 0).scale(1.4, 0.55, 1.2).translate(-3.4, 4.2, -0.4), K1],
    [new THREE.IcosahedronGeometry(1.9, 0).scale(1.3, 0.55, 1.2).translate(0.5, 4.3, 2.8), K1],
    [new THREE.IcosahedronGeometry(1.9, 0).scale(1.3, 0.55, 1.2).translate(-0.4, 4.2, -2.8), K1],
  ];
  const mr = mulberry32(5);
  for (let k = 0; k < 14; k++) { // Spanish moss strands
    const a = mr() * Math.PI * 2, r = 1 + mr() * 3.8, len = 1.1 + mr() * 1.4;
    oakParts.push([new THREE.ConeGeometry(0.11, len, 4).rotateX(Math.PI).translate(Math.cos(a) * r, 3.7 - len / 2, Math.sin(a) * r), K2]);
  }
  T.liveOak = bake(oakParts);
  T.sabal = palm(6, 16, 1.9, 0.75, 0.2, -0.9, 0.4, 0.8);
  T.palmetto = bake((() => {
    const p = [];
    for (let k = 0; k < 8; k++) for (const g of frond(1.5, 0.7, k * 0.8, -0.75 + (k % 3) * 0.25, 0.25, 0.1)) p.push([g, K1]);
    return p;
  })());
  T.cypress = bake([ // bald cypress standing in the water
    [new THREE.CylinderGeometry(0.25, 0.75, 1.6, 6).translate(0, 0.2, 0), K0],
    [new THREE.CylinderGeometry(0.14, 0.25, 8, 5).translate(0, 4.8, 0), K0],
    [new THREE.ConeGeometry(1.7, 5.5, 6).translate(0, 8.4, 0), K1],
    [new THREE.IcosahedronGeometry(1.2, 0).scale(1.3, 0.7, 1.3).translate(0.6, 6.4, 0.3), K1],
  ]);
  T.pole = bake([
    [new THREE.CylinderGeometry(0.12, 0.16, 9, 6).translate(0, 4.5, 0), K0],
    [new THREE.BoxGeometry(2.4, 0.13, 0.13).translate(0, 8.4, 0), K0],
    [new THREE.CylinderGeometry(0.05, 0.05, 0.25, 5).translate(1.0, 8.6, 0), K2],
    [new THREE.CylinderGeometry(0.05, 0.05, 0.25, 5).translate(-1.0, 8.6, 0), K2],
    [new THREE.CylinderGeometry(0.05, 0.05, 0.25, 5).translate(0.0, 9.1, 0), K2],
  ]);
}

const propMat = new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true });

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

// Vegetation for one candidate spot. Returns nothing; adds to merger.
function plant(m, rr, lx, lz, x, z, h, d) {
  const s = 0.75 + rr() * 0.6, rot = rr() * 6.283;
  if (CA) {
    const u = (x - roadXAtZ(z)) * OCEAN_SIDE;
    if (h < 3.4) return; // beach
    const chap = sstep(-0.1, 0.4, noise(x / 230 + 7, z / 230 - 3) + 0.25 * noise(x / 60, z / 60));
    const euc = sstep(0.35, 0.6, noise(x / 420 - 30, z / 420 + 12));
    const coastal = sstep(coastDist(z) - 110, coastDist(z) - 30, u);
    const k = rr();
    if (coastal > 0.4 && k < 0.3) { m.add(T.cypress, lx, h - 0.2, lz, rot, s * 1.1, s, [col(0x5a4a3a), pick(rr, 0x40613a, 0x52703f), col(0)]); return; }
    if (euc > 0.3 && k < 0.6) { m.add(T.euc, lx, h - 0.2, lz, rot, s, s * (0.9 + rr() * 0.4), [col(0), pick(rr, 0x7f9a74, 0x93a882), col(0xd9cfbd)]); return; }
    if (d < 70 && rr() < 0.012) { m.add(rr() < 0.6 ? T.fanPalm : T.datePalm, lx, h - 0.2, lz, rot, s, s, [col(0x8a7558), pick(rr, 0x4f7a34, 0x6a8a3c), col(0x6b5a40)]); return; }
    if (rr() > 0.08 + chap * 0.6) return;
    if (k < 0.78) m.add(T.shrub, lx, h, lz, rot, s * 1.2, s, [col(0), pick(rr, 0x4e5a33, 0x6b7444), col(0)]);
    else if (k < 0.94) m.add(T.oak, lx, h - 0.2, lz, rot, s, s, [col(0x4a3b2e), pick(rr, 0x3d5530, 0x4f6636), col(0)]);
    else m.add(T.rock, lx, h, lz, rot, s * 1.3, s, [col(0), col(0), col(0xa69274)]);
  } else {
    const sw = swampiness(x, z);
    const pasture = sstep(0.3, 0.55, noise(x / 520 + 77, z / 520 - 11));
    const k = rr();
    if (h < WATER + 0.25) { // in the swamp
      if (h > WATER - 1.6 && rr() < 0.55) m.add(T.cypress, lx, h, lz, rot, s, s * (0.9 + rr() * 0.4), [col(0x6b5844), pick(rr, 0x5d6e34, 0x76803e), col(0)]);
      return;
    }
    if (pasture > 0.5) {
      if (rr() < 0.06) m.add(T.liveOak, lx, h - 0.2, lz, rot, s * 1.1, s, [col(0x4d4236), pick(rr, 0x35512b, 0x47602f), pick(rr, 0x7f8770, 0x939a80)]);
      return;
    }
    if (sw > 0.25 && k < 0.35) {
      if (rr() < 0.5) m.add(T.liveOak, lx, h - 0.2, lz, rot, s, s, [col(0x4d4236), pick(rr, 0x35512b, 0x47602f), pick(rr, 0x7f8770, 0x939a80)]);
      else m.add(T.sabal, lx, h - 0.1, lz, rot, s, s, [col(0x7d7058), pick(rr, 0x4f7038, 0x63813f), col(0x6e6248)]);
      return;
    }
    if (k < 0.42) m.add(T.slash, lx, h - 0.2, lz, rot, s, s * (0.85 + rr() * 0.35), [col(0x5c4a3a), pick(rr, 0x3d5a2e, 0x50693a), col(0)]);
    else if (k < 0.85) m.add(T.palmetto, lx, h, lz, rot, s * 1.2, s, [col(0), pick(rr, 0x5f7f3c, 0x7a9446), col(0)]);
    else if (k < 0.92) m.add(T.sabal, lx, h - 0.1, lz, rot, s, s, [col(0x7d7058), pick(rr, 0x4f7038, 0x63813f), col(0x6e6248)]);
    else if (k < 0.96) m.add(T.liveOak, lx, h - 0.2, lz, rot, s, s, [col(0x4d4236), pick(rr, 0x35512b, 0x47602f), pick(rr, 0x7f8770, 0x939a80)]);
  }
}

// ---------------------------------------------------------------------------
// Terrain chunks
// ---------------------------------------------------------------------------
const terrainMat = new THREE.MeshLambertMaterial({ vertexColors: true });
const chunks = new Map();
const N1 = RES + 1, NB = RES + 3;
const hBuf = new Float32Array(NB * NB), dBuf = new Float32Array(NB * NB);
const _cq = Q();

function buildChunk(cx, cz) {
  const ox = cx * CHUNK, oz = cz * CHUNK, st = CHUNK / RES;
  for (let j = 0; j < NB; j++) for (let i = 0; i < NB; i++) {
    const x = ox + (i - 1) * st, z = oz + (j - 1) * st;
    hBuf[j * NB + i] = heightAt(x, z, _cq);
    dBuf[j * NB + i] = _cq.d;
  }
  const pos = new Float32Array(N1 * N1 * 3), nrm = new Float32Array(N1 * N1 * 3), cols = new Float32Array(N1 * N1 * 3);
  const c = [0, 0, 0];
  for (let j = 0; j < N1; j++) for (let i = 0; i < N1; i++) {
    const b = (j + 1) * NB + (i + 1), v = j * N1 + i;
    const h = hBuf[b];
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
    idx[k++] = a; idx[k++] = cc; idx[k++] = b;
    idx[k++] = b; idx[k++] = cc; idx[k++] = dd;
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  geo.setAttribute('normal', new THREE.BufferAttribute(nrm, 3));
  geo.setAttribute('color', new THREE.BufferAttribute(cols, 3));
  geo.setIndex(new THREE.BufferAttribute(idx, 1));
  geo.computeBoundingSphere();
  const mesh = new THREE.Mesh(geo, terrainMat);
  mesh.position.set(ox, 0, oz);
  mesh.receiveShadow = true;
  mesh.matrixAutoUpdate = false; mesh.updateMatrix();
  scene.add(mesh);

  const rr = mulberry32((cx * 73856093) ^ (cz * 19349663) ^ SEED);
  const m = new Merger();
  const tries = FL ? 150 : 110;
  for (let t = 0; t < tries; t++) {
    const lx = rr() * CHUNK, lz = rr() * CHUNK, x = ox + lx, z = oz + lz;
    const gi = clamp(Math.round(lx / st), 0, RES), gj = clamp(Math.round(lz / st), 0, RES);
    const b = (gj + 1) * NB + (gi + 1);
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
// Road mesh segments (+ roadside palms, posts, power lines)
// ---------------------------------------------------------------------------
function makeRoadTexture() {
  const W = 256, H = 512, cv = document.createElement('canvas');
  cv.width = W; cv.height = H;
  const g = cv.getContext('2d');
  const px = W / (2 * ROAD_EDGE);
  const r = mulberry32(7);
  g.fillStyle = CA ? '#a8987a' : '#b4a57e'; g.fillRect(0, 0, W, H);
  for (let i = 0; i < 2500; i++) { g.fillStyle = r() < 0.5 ? 'rgba(70,60,45,.25)' : 'rgba(220,210,180,.25)'; g.fillRect(r() * W, r() * H, 2, 2); }
  const a0 = (ROAD_EDGE - ROAD_HALF) * px, a1 = W - a0;
  g.fillStyle = CA ? '#4c4f54' : '#5a5b5c'; g.fillRect(a0, 0, a1 - a0, H);
  for (let i = 0; i < 9000; i++) { const v = 60 + r() * 55 | 0; g.fillStyle = `rgba(${v},${v},${v + 4},.35)`; g.fillRect(a0 + r() * (a1 - a0), r() * H, 1.5, 1.5); }
  if (FL) { // patched, sun-bleached asphalt
    for (let i = 0; i < 6; i++) { g.fillStyle = 'rgba(40,40,42,.16)'; g.fillRect(a0 + r() * (a1 - a0 - 60), r() * H, 20 + r() * 60, 10 + r() * 50); }
  }
  g.fillStyle = 'rgba(30,30,32,.10)';
  for (const off of [-2.4, -0.9, 0.9, 2.4]) g.fillRect(W / 2 + (off - 0.35) * px, 0, 0.7 * px, H);
  const lw = 0.14 * px;
  g.fillStyle = '#ece6d6';
  g.fillRect(a0 + 0.2 * px, 0, lw, H);
  g.fillRect(a1 - 0.2 * px - lw, 0, lw, H);
  g.fillStyle = '#e0b43a';
  if (CA) { // double yellow
    g.fillRect(W / 2 - lw * 1.6, 0, lw, H);
    g.fillRect(W / 2 + lw * 0.6, 0, lw, H);
  } else {
    g.fillRect(W / 2 - lw / 2, 0, lw, H * 0.4);
  }
  const tex = new THREE.CanvasTexture(cv);
  tex.wrapS = THREE.ClampToEdgeWrapping; tex.wrapT = THREE.RepeatWrapping;
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = renderer.capabilities.getMaxAnisotropy();
  return tex;
}
const roadMat = new THREE.MeshLambertMaterial({ map: makeRoadTexture(), polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -4 });
const wireMat = new THREE.LineBasicMaterial({ color: 0x1c1c1c });
const SEG = 64;
const segments = new Map();
const TEX_LEN = 16;
const POLE_EVERY = 22;

function poleTops(i) {
  const p = roadPoint(i * STEP, ROAD_EDGE + 4.2);
  const y = Math.max(baseH(p.x, p.z), WATER - 0.5);
  const top = Math.min(y, p.y) + 8.4 * 1;
  const c = Math.cos(p.h), s = Math.sin(p.h);
  return { p, y: Math.min(y, p.y), ends: [-1, 0, 1].map((o) => [p.x + o * c, top + (o === 0 ? 0.7 : 0.2), p.z - o * s]) };
}

function buildSegment(k) {
  const i0 = k * SEG, i1 = i0 + SEG;
  const ox = road.xs[i0], oz = road.zs[i0];
  const lats = [-ROAD_EDGE, -ROAD_HALF, ROAD_HALF, ROAD_EDGE];
  const dy = [-0.13, 0.03, 0.03, -0.13];
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
  for (let i = 0; i < SEG; i++) for (let c = 0; c < 3; c++) {
    const a = i * 4 + c, b = a + 1, cc = a + 4, d = cc + 1;
    idx.push(a, b, cc, b, d, cc);
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  const mesh = new THREE.Mesh(geo, roadMat);
  mesh.position.set(ox, 0, oz);
  mesh.receiveShadow = true;
  mesh.matrixAutoUpdate = false; mesh.updateMatrix();
  scene.add(mesh);

  const m = new Merger();
  const white = col(0xeeeeea), red = col(0xd04a2a), dark = col(0x222222);
  let wires = null;
  if (CA) {
    for (let i = i0; i < i1; i++) {
      const s = i * STEP;
      const town = sstep(0.25, 0.45, noise(s / 1600 + 31, 4.4)); // palm-lined stretches
      if (town > 0.5 && i % 15 === 0) {
        for (const side of [-1, 1]) {
          const p = roadPoint(s, side * (ROAD_EDGE + 3.2));
          const gy = heightAt(p.x, p.z);
          if (gy < 2 || Math.abs(gy - p.y) > 3) continue;
          const r = mulberry32(i * 31 + side)();
          m.add(T.fanPalm, p.x - ox, gy - 0.2, p.z - oz, r * 6, 0.9 + r * 0.25, 0.9 + r * 0.35, [col(0x8a7558), col(0x55803a), col(0x6b5a40)]);
        }
      } else if (i % 25 === 0) {
        const side = (i / 25) % 2 ? 1 : -1;
        const p = roadPoint(s, side * (ROAD_EDGE + 0.6));
        if (Math.abs(baseH(p.x, p.z) - p.y) > 2.5) continue;
        m.add(T.post, p.x - ox, p.y - 0.15, p.z - oz, p.h, 1, 1, [dark, side > 0 ? red : white, white]);
      }
    }
  } else {
    const lp = [];
    const wood = col(0x5e5040), glassy = col(0x7d9a9a);
    const first = Math.ceil(i0 / POLE_EVERY) * POLE_EVERY;
    for (let i = first; i < i1; i += POLE_EVERY) {
      const a = poleTops(i), b = poleTops(i + POLE_EVERY);
      m.add(T.pole, a.p.x - ox, a.y - 0.3, a.p.z - oz, a.p.h, 1, 1, [wood, wood, glassy]);
      for (let w = 0; w < 3; w++) {
        const A = a.ends[w], B = b.ends[w];
        const N = 8;
        for (let t = 0; t < N; t++) {
          const t0 = t / N, t1 = (t + 1) / N;
          const sag0 = 0.9 * 4 * t0 * (1 - t0), sag1 = 0.9 * 4 * t1 * (1 - t1);
          lp.push(lerp(A[0], B[0], t0) - ox, lerp(A[1], B[1], t0) - sag0, lerp(A[2], B[2], t0) - oz,
                  lerp(A[0], B[0], t1) - ox, lerp(A[1], B[1], t1) - sag1, lerp(A[2], B[2], t1) - oz);
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
// Clouds
// ---------------------------------------------------------------------------
const cloudMat = new THREE.MeshLambertMaterial({ color: 0xffffff, flatShading: true, fog: false, transparent: true, opacity: 0.92 });
const clouds = [];
{
  const r = mulberry32(SEED ^ 0xc10d);
  const count = FL ? 34 : 22;
  for (let i = 0; i < count; i++) {
    const grp = new THREE.Group();
    const n = 4 + ((r() * 5) | 0);
    const tall = FL && r() < 0.35; // afternoon thunderheads
    for (let k = 0; k < n; k++) {
      const s = 18 + r() * 26;
      const b = new THREE.Mesh(new THREE.IcosahedronGeometry(s, 1), cloudMat);
      b.position.set((k - n / 2) * 22 + r() * 10, tall ? k * 18 * r() + r() * 20 : r() * 10, r() * 24 - 12);
      b.scale.y = tall ? 0.95 : 0.5;
      grp.add(b);
    }
    grp.position.set((r() - 0.5) * 3200, (FL ? 260 : 380) + r() * 160, (r() - 0.5) * 3200);
    grp.rotation.y = r() * Math.PI;
    clouds.push(grp); scene.add(grp);
  }
}

// ---------------------------------------------------------------------------
// The vehicle: a pastel convertible (CA) or an old pickup (FL)
// ---------------------------------------------------------------------------
const CA_PAINT = [0x8fd3c1, 0xf08a74, 0x9cc4e8, 0xf2e4c4, 0xe9b949];
const FL_PAINT = [0x9e3b2c, 0x4f7f6a, 0x2f4f6f, 0xd8d2c0, 0x8a6a3a];
const paintList = CA ? CA_PAINT : FL_PAINT;
const carPaint = new THREE.MeshLambertMaterial({ color: paintList[(SEED >>> 3) % paintList.length] });
function buildCar() {
  const car = new THREE.Group();
  const body = new THREE.Group(); car.add(body);
  const glass = new THREE.MeshLambertMaterial({ color: 0x1d2a33, transparent: CA, opacity: CA ? 0.45 : 1 });
  const dark = new THREE.MeshLambertMaterial({ color: 0x222326 });
  const chrome = new THREE.MeshLambertMaterial({ color: 0xd4d6d8 });
  const seat = new THREE.MeshLambertMaterial({ color: CA ? 0xf1e7d2 : 0x3b3329 });
  const white = new THREE.MeshLambertMaterial({ color: 0xece6da });
  const add = (geo, mat, x, y, z) => { const m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); m.castShadow = true; m.receiveShadow = true; body.add(m); return m; };
  const hl = new THREE.MeshBasicMaterial({ color: 0xfff6d8 });
  const tl = new THREE.MeshBasicMaterial({ color: 0x8a1010 });
  let wheelR, wheelPos, camH;
  if (CA) {
    // long, low convertible
    add(new THREE.BoxGeometry(1.88, 0.48, 4.7), carPaint, 0, 0.6, 0);
    add(new THREE.BoxGeometry(1.84, 0.16, 4.55), carPaint, 0, 0.9, -0.02);
    add(new THREE.BoxGeometry(1.86, 0.05, 4.62), white, 0, 0.74, 0); // pinstripe
    add(new THREE.BoxGeometry(1.5, 0.05, 1.9), seat, 0, 0.99, -0.45);  // cockpit floor
    for (const x of [-0.42, 0.42]) {
      add(new THREE.BoxGeometry(0.58, 0.55, 0.16), seat, x, 1.25, -0.95);
      add(new THREE.BoxGeometry(0.58, 0.12, 0.6), seat, x, 1.05, -0.65);
    }
    add(new THREE.BoxGeometry(1.7, 0.42, 0.14), seat, 0, 1.18, -1.65); // rear bench back
    const ws = add(new THREE.BoxGeometry(1.6, 0.5, 0.04), glass, 0, 1.22, 0.62);
    ws.rotation.x = -0.45;
    const frame = add(new THREE.BoxGeometry(1.64, 0.05, 0.06), chrome, 0, 1.45, 0.52); frame.rotation.x = -0.45;
    const wheel = add(new THREE.TorusGeometry(0.17, 0.025, 6, 14), dark, 0.42, 1.08, 0.2); wheel.rotation.x = -0.9;
    add(new THREE.BoxGeometry(1.92, 0.14, 0.18), chrome, 0, 0.46, 2.35);
    add(new THREE.BoxGeometry(1.92, 0.14, 0.18), chrome, 0, 0.46, -2.35);
    add(new THREE.CylinderGeometry(0.13, 0.13, 0.06, 12).rotateX(Math.PI / 2), hl, 0.66, 0.74, 2.35);
    add(new THREE.CylinderGeometry(0.13, 0.13, 0.06, 12).rotateX(Math.PI / 2), hl, -0.66, 0.74, 2.35);
    add(new THREE.BoxGeometry(0.22, 0.22, 0.06), tl, 0.7, 0.76, -2.36);
    add(new THREE.BoxGeometry(0.22, 0.22, 0.06), tl, -0.7, 0.76, -2.36);
    add(new THREE.BoxGeometry(0.75, 0.2, 0.04), chrome, 0, 0.62, 2.36);
    wheelR = 0.36; camH = 1.62;
    wheelPos = [[0.88, 1.5], [-0.88, 1.5], [0.88, -1.5], [-0.88, -1.5]];
  } else {
    // old pickup truck
    add(new THREE.BoxGeometry(1.92, 0.6, 5.0), carPaint, 0, 0.85, 0);
    const cab = new THREE.BoxGeometry(1.82, 0.78, 1.7);
    const p = cab.attributes.position;
    for (let i = 0; i < p.count; i++) if (p.getY(i) > 0) p.setZ(i, p.getZ(i) * 0.88 - 0.05);
    cab.computeVertexNormals();
    add(cab, carPaint, 0, 1.53, 0.35);
    add(new THREE.BoxGeometry(1.84, 0.4, 1.3), glass, 0, 1.62, 0.33);  // window band
    add(new THREE.BoxGeometry(1.86, 0.1, 1.4), white, 0, 1.94, 0.33);  // roof stripe
    add(new THREE.BoxGeometry(1.92, 0.08, 2.3), dark, 0, 1.17, -1.32); // bed floor
    add(new THREE.BoxGeometry(0.08, 0.45, 2.3), carPaint, 0.92, 1.38, -1.32);
    add(new THREE.BoxGeometry(0.08, 0.45, 2.3), carPaint, -0.92, 1.38, -1.32);
    add(new THREE.BoxGeometry(1.92, 0.45, 0.08), carPaint, 0, 1.38, -2.46);
    add(new THREE.BoxGeometry(1.96, 0.2, 0.22), chrome, 0, 0.6, 2.55);
    add(new THREE.BoxGeometry(1.96, 0.2, 0.22), dark, 0, 0.6, -2.55);
    add(new THREE.BoxGeometry(1.2, 0.34, 0.05), chrome, 0, 0.92, 2.52); // grille
    add(new THREE.CylinderGeometry(0.15, 0.15, 0.06, 12).rotateX(Math.PI / 2), hl, 0.74, 0.98, 2.52);
    add(new THREE.CylinderGeometry(0.15, 0.15, 0.06, 12).rotateX(Math.PI / 2), hl, -0.74, 0.98, 2.52);
    add(new THREE.BoxGeometry(0.18, 0.28, 0.06), tl, 0.82, 1.0, -2.52);
    add(new THREE.BoxGeometry(0.18, 0.28, 0.06), tl, -0.82, 1.0, -2.52);
    add(new THREE.BoxGeometry(0.08, 0.2, 0.14), chrome, 1.0, 1.6, 1.15);  // mirrors
    add(new THREE.BoxGeometry(0.08, 0.2, 0.14), chrome, -1.0, 1.6, 1.15);
    wheelR = 0.44; camH = 1.95;
    wheelPos = [[0.9, 1.6], [-0.9, 1.6], [0.9, -1.55], [-0.9, -1.55]];
  }
  const wheels = [];
  const tyre = new THREE.CylinderGeometry(wheelR, wheelR, 0.28, 16).rotateZ(Math.PI / 2);
  const hub = new THREE.CylinderGeometry(wheelR * 0.55, wheelR * 0.55, 0.29, 10).rotateZ(Math.PI / 2);
  const wall = new THREE.CylinderGeometry(wheelR * 0.8, wheelR * 0.8, 0.285, 14).rotateZ(Math.PI / 2);
  for (const [x, z] of wheelPos) {
    const pivot = new THREE.Group(); pivot.position.set(x, wheelR, z);
    const spin = new THREE.Group(); pivot.add(spin);
    const w = new THREE.Mesh(tyre, dark); w.castShadow = true; spin.add(w);
    if (CA) spin.add(new THREE.Mesh(wall, white)); // whitewalls
    spin.add(new THREE.Mesh(hub, chrome));
    spin.add(new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.08, wheelR * 1.0), dark)); // makes rotation visible
    car.add(pivot); wheels.push({ pivot, spin, front: z > 0 });
  }
  const beam = new THREE.SpotLight(0xfff1d0, 0, 90, 0.55, 0.6, 1.2);
  beam.position.set(0, 0.9, 2.2);
  beam.target.position.set(0, -1.5, 22);
  car.add(beam, beam.target);
  return { car, body, wheels, beam, tailMat: tl, wheelBase: Math.abs(wheelPos[0][1] - wheelPos[2][1]), camH };
}
const carParts = buildCar();
scene.add(carParts.car);

const car = { x: 0, z: 0, y: 0, h: 0, v: 0, steer: 0, pitch: 0, roll: 0, s: 0, lat: 0, d: 0, odo: 0, spin: 0, yv: 0, pitchTerrain: 0 };
const input = { up: false, down: false, left: false, right: false, touchL: false, touchR: false };
let autoDrive = true;
let throttle = 0, brake = 0;
const WHEELBASE = carParts.wheelBase;
const _carQ = Q();
const CRUISE = CA ? 24 : 21; // m/s auto-drive cruise
const LANE = 1.8;

function curvatureAhead(s, dist) {
  let maxC = 0;
  const i0 = Math.floor(s / STEP), n = Math.floor(dist / STEP);
  for (let k = 0; k < n; k += 2) {
    const i = i0 + k;
    if (i + 4 >= road.nFinal) break;
    const c = Math.abs(wrapAngle(road.hd[i + 4] - road.hd[i])) / (4 * STEP);
    maxC = Math.max(maxC, c * (1 - 0.55 * (k / n)));
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
    const la = 9 + Math.abs(car.v) * 0.75;
    const tp = roadPoint(car.s + la, LANE);
    const desired = Math.atan2(tp.x - car.x, tp.z - car.z);
    const alpha = wrapAngle(desired - car.h);
    const dist = Math.hypot(tp.x - car.x, tp.z - car.z);
    steerTarget = clamp(Math.atan(2 * WHEELBASE * Math.sin(alpha) / dist), -0.6, 0.6);
    const c = curvatureAhead(car.s, 40 + car.v * 2.5);
    const vt = Math.min(CRUISE, Math.sqrt(2.6 / Math.max(c, 1e-4)), car.d > ROAD_EDGE ? 10 : 99);
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
  else if (brake > 0 && !autoDrive) acc -= 4 * brake; // reverse
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

  const fx = Math.sin(car.h), fz = Math.cos(car.h), lx = Math.cos(car.h), lz = -Math.sin(car.h);
  const hw = WHEELBASE / 2;
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
  for (const w of carParts.wheels) {
    w.spin.rotation.x = car.spin;
    if (w.front) w.pivot.rotation.y = car.steer;
  }
  carParts.tailMat.color.setHex(brake > 0.05 ? 0xff2a1a : (night > 0.4 ? 0xb01818 : 0x7a1010));
}

// ---------------------------------------------------------------------------
// Time of day
// ---------------------------------------------------------------------------
const PRESETS = CA ? [0.3, 0.45, 0.728, 0.752, 0.9] : [0.32, 0.5, 0.62, 0.74, 0.92];
const PRESET_NAMES = CA ? ['sunrise', 'midday', 'golden hour', 'sunset', 'night'] : ['morning', 'noon', 'afternoon', 'dusk', 'night'];
let presetIdx = CA ? 2 : 2;
let timeOfDay = PRESETS[presetIdx];
let timeTarget = timeOfDay;
let dayCycle = false;
let night = 0;
const tmpC = new THREE.Color(), tmpC2 = new THREE.Color(), tmpV = new THREE.Vector3();
const KEYS = [ // keyed by sun elevation
  { e: -0.35, top: 0x070b1c, hor: 0x161d36, sun: 0x7f96d0, sunI: 0.5, hemiS: 0x2c3a5f, hemiG: 0x14181f, hemiI: 0.7 },
  { e: -0.08, top: 0x1f2552, hor: 0x6a5478, sun: 0xb98ab0, sunI: 0.4, hemiS: 0x4a5070, hemiG: 0x1a1c20, hemiI: 0.6 },
  { e: 0.02, top: 0x3d5590, hor: 0xf59a68, sun: 0xff9a5a, sunI: 1.6, hemiS: 0xb0a0c8, hemiG: 0x4a4030, hemiI: 0.8 },
  { e: 0.16, top: 0x4c7cc4, hor: 0xf6cfa0, sun: 0xffd6a0, sunI: 2.3, hemiS: 0xc8d0f0, hemiG: 0x5e6a40, hemiI: 1.0 },
  { e: 0.45, top: 0x3f7ccc, hor: 0xbcd8ec, sun: 0xfff3e2, sunI: 2.7, hemiS: 0xcfe4ff, hemiG: 0x667a48, hemiI: 1.1 },
  { e: 1.0, top: 0x3672c6, hor: 0xb0d0ea, sun: 0xffffff, sunI: 2.9, hemiS: 0xd6e8ff, hemiG: 0x6b7e4a, hemiI: 1.15 },
];
function sampleKey(e, key, out) {
  let a = KEYS[0], b = KEYS[KEYS.length - 1], t = 0;
  if (e <= KEYS[0].e) b = a;
  else if (e >= b.e) a = b;
  else for (let i = 0; i < KEYS.length - 1; i++) if (e >= KEYS[i].e && e <= KEYS[i + 1].e) { a = KEYS[i]; b = KEYS[i + 1]; t = (e - a.e) / (b.e - a.e); break; }
  t = smooth(t);
  if (!out) return lerp(a[key], b[key], t);
  return out.set(a[key]).lerp(tmpC2.set(b[key]), t);
}
const sunDir = new THREE.Vector3();
const HAZE = new THREE.Color(FL ? 0xe4e6d8 : 0xf3dccb);
const HAZE_AMT = FL ? 0.35 : 0.15;
function updateSky(simT) {
  const ang = (timeOfDay - 0.25) * Math.PI * 2;
  // The sun rises inland (-x) and sets over the ocean side (+x).
  sunDir.set(-Math.cos(ang) * 0.8, Math.sin(ang), 0.35).normalize();
  const elev = sunDir.y;
  night = sstep(0.02, -0.18, elev);
  sampleKey(elev, 'top', skyUniforms.top.value);
  sampleKey(elev, 'hor', skyUniforms.horizon.value);
  skyUniforms.horizon.value.lerp(HAZE, HAZE_AMT * (1 - night) * sstep(0.0, 0.3, elev));
  skyUniforms.bottom.value.copy(skyUniforms.horizon.value).multiplyScalar(0.8);
  scene.fog.color.copy(skyUniforms.horizon.value);
  sampleKey(elev, 'sun', sun.color);
  skyUniforms.sunColor.value.copy(sun.color).multiplyScalar(elev > -0.05 ? 1 : 0);
  sun.intensity = sampleKey(elev, 'sunI');
  sampleKey(elev, 'hemiS', hemi.color);
  sampleKey(elev, 'hemiG', hemi.groundColor);
  hemi.intensity = sampleKey(elev, 'hemiI');
  skyUniforms.sunDir.value.copy(sunDir);
  const lightDir = elev > -0.05 ? sunDir : tmpV.set(-0.3, 0.8, 0.4).normalize(); // moonlight at night
  sun.position.set(car.x + lightDir.x * 300, car.y + Math.max(lightDir.y, 0.08) * 300, car.z + lightDir.z * 300);
  sun.target.position.set(car.x, car.y, car.z);
  stars.material.opacity = night * 0.9;
  carParts.beam.intensity = night * 150;
  cloudMat.color.copy(skyUniforms.horizon.value).lerp(tmpC.set(0xffffff), 0.6 - night * 0.5);
  cloudMat.opacity = 0.92 - night * 0.5;
  waterMat.color.set(WATER_BASE).lerp(skyUniforms.top.value, CA ? 0.3 : 0.12).multiplyScalar(1 - night * 0.7);
  waterMat.normalMap.offset.set(simT * 0.004, simT * 0.0025);
}

// ---------------------------------------------------------------------------
// Camera
// ---------------------------------------------------------------------------
const CAM_MODES = ['chase', 'hood', 'cinematic'];
let camMode = 0;
let camYaw = 0;
const look = { yaw: 0, pitch: 0, dragging: false, lastX: 0, lastY: 0, idle: 99 };
const cine = { x: 0, y: 0, z: 0, set: false, s: 0 };
const camPos = new THREE.Vector3(), camLook = new THREE.Vector3();
let camInit = false;

function updateCamera(dt) {
  const mode = CAM_MODES[camMode];
  if (!look.dragging) {
    look.idle += dt;
    if (look.idle > 1.5) { look.yaw *= Math.exp(-dt * 1.5); look.pitch *= Math.exp(-dt * 1.5); }
  }
  if (mode === 'chase') {
    camYaw += wrapAngle(car.h - camYaw) * Math.min(1, dt * 2.8);
    const yaw = camYaw + look.yaw;
    const dist = (FL ? 9.2 : 8.4) + Math.abs(car.v) * 0.03, up = (FL ? 3.0 : 2.5) + look.pitch * 6;
    const tx = car.x - Math.sin(yaw) * dist, tz = car.z - Math.cos(yaw) * dist;
    const ty = Math.max(car.y + up, groundAt(tx, tz) + 1.0);
    const target = tmpV.set(tx, ty, tz);
    if (!camInit) { camPos.copy(target); camInit = true; }
    camPos.lerp(target, Math.min(1, dt * 6));
    camLook.set(car.x + Math.sin(yaw) * 5, car.y + 1.4, car.z + Math.cos(yaw) * 5);
    camera.position.copy(camPos);
    camera.lookAt(camLook);
    camera.fov = lerp(camera.fov, 58 + Math.abs(car.v) * 0.18, Math.min(1, dt * 2));
  } else if (mode === 'hood') {
    const C = carParts.car;
    C.updateMatrixWorld();
    camera.position.set(0.42, carParts.camH, CA ? -0.45 : 0.2).applyMatrix4(C.matrixWorld);
    camLook.set(0.42 + Math.sin(look.yaw) * 10, carParts.camH - 0.15 + look.pitch * 10, 10).applyMatrix4(C.matrixWorld);
    camera.lookAt(camLook);
    camera.fov = lerp(camera.fov, 70, Math.min(1, dt * 3));
  } else {
    const dx = car.x - cine.x, dz = car.z - cine.z;
    if (!cine.set || car.s > cine.s + 45 || Math.hypot(dx, dz) > 260) {
      const s = car.s + 110 + Math.random() * 90;
      if (s / STEP < road.nFinal - 2) {
        const side = Math.random() < 0.5 ? -1 : 1;
        const p = roadPoint(s, side * (FL ? 6.5 + Math.random() * 2.5 : 10 + Math.random() * 18));
        cine.x = p.x; cine.z = p.z; cine.y = Math.max(groundAt(p.x, p.z), WATER) + (FL ? 1.2 + Math.random() * 2 : 1.6 + Math.random() * 5); cine.s = s; cine.set = true;
      }
    }
    camera.position.set(cine.x, cine.y, cine.z);
    camLook.set(car.x, car.y + 1, car.z);
    camera.lookAt(camLook);
    const d = camera.position.distanceTo(camLook);
    camera.fov = lerp(camera.fov, clamp(900 / Math.max(d, 1), 18, 60), Math.min(1, dt * 3));
  }
  camera.updateProjectionMatrix();
  sky.position.copy(camera.position);
  stars.position.copy(camera.position);
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
  for (const [key, c] of chunks) {
    const dx = (c.cx + 0.5) * CHUNK - car.x, dz = (c.cz + 0.5) * CHUNK - car.z;
    if (Math.hypot(dx, dz) > VIEW_M + CHUNK * 2) disposeChunk(key);
  }
  const zSafe = road.zs[road.nFinal - 1] - CELL * 2;
  const todo = [];
  const fx = Math.sin(car.h), fz = Math.cos(car.h);
  for (let a = -VIEW_CHUNKS - 1; a <= VIEW_CHUNKS + 1; a++) for (let b = -VIEW_CHUNKS - 1; b <= VIEW_CHUNKS + 1; b++) {
    const cx = ccx + a, cz = ccz + b;
    if (chunks.has(hkey(cx, cz))) continue;
    const dx = (cx + 0.5) * CHUNK - car.x, dz = (cz + 0.5) * CHUNK - car.z;
    const dist = Math.hypot(dx, dz);
    if (dist > VIEW_M + CHUNK * 0.7) continue;
    if ((cz + 1) * CHUNK > zSafe) continue;
    const ahead = (dx * fx + dz * fz) / (dist || 1);
    todo.push({ cx, cz, p: dist * (1.25 - 0.5 * ahead) });
  }
  todo.sort((p, q) => p.p - q.p);
  for (const c of todo) {
    buildChunk(c.cx, c.cz);
    if (performance.now() - t0 > budgetMs) break;
  }
  return todo.length;
}

function updateClouds(dt) {
  for (const c of clouds) {
    c.position.x += dt * 3;
    const dx = c.position.x - car.x, dz = c.position.z - car.z;
    if (dx > 1600) c.position.x -= 3200; else if (dx < -1600) c.position.x += 3200;
    if (dz > 1600) c.position.z -= 3200; else if (dz < -1600) c.position.z += 3200;
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
    const t = this.ctx.currentTime, av = Math.abs(v);
    const tops = [8, 15, 23, 32, 42, 60];
    let g = 0; while (g < tops.length - 1 && av > tops[g]) g++;
    const lo = g ? tops[g - 1] * 0.6 : 0;
    const rpm = clamp((av - lo) / (tops[g] - lo), 0, 1);
    const f = (FL ? 28 : 34) + rpm * (FL ? 50 : 62) + thr * 6;
    this.o1.frequency.setTargetAtTime(f, t, 0.08);
    this.o2.frequency.setTargetAtTime(f * 0.5, t, 0.08);
    this.filt.frequency.setTargetAtTime(220 + rpm * 380 + thr * 300, t, 0.1);
    this.eng.gain.setTargetAtTime((0.03 + thr * 0.035) * (radio.on ? 0.7 : 1), t, 0.15);
    // the convertible is open-top: more wind
    const windK = CA ? 0.55 : 0.32;
    this.wind.gain.setTargetAtTime(Math.min(0.55, (av / 45) ** 2 * windK) + (offroad ? Math.min(0.35, av / 40) : 0), t, 0.2);
    this.wf.frequency.setTargetAtTime(offroad ? 160 : 380 + av * 12, t, 0.2);
  },
  toggle() {
    this.on = !this.on;
    if (this.ctx) this.master.gain.setTargetAtTime(this.on ? 0.6 : 0, this.ctx.currentTime, 0.1);
  },
};

const STATION = CA ? {
  name: '101.9 Coastline FM', bpm: 74, swing: 0.16,
  chords: [[53, 57, 60, 64, 67], [52, 55, 59, 62, 66], [50, 53, 57, 60, 64], [48, 52, 55, 59, 62]],
  bass: [41, 40, 38, 36], prog: [0, 1, 2, 3],
  scale: [72, 74, 76, 79, 81, 84, 86],
} : {
  name: '88.3 Backroads Radio', bpm: 96, swing: 0.3,
  chords: [[52, 56, 59, 62], [57, 61, 64, 67], [59, 63, 66, 69]],
  bass: [40, 45, 47], prog: [0, 0, 0, 0, 1, 1, 0, 0, 2, 1, 0, 2],
  scale: [64, 67, 69, 70, 71, 74, 76],
};
const radio = {
  on: true, ctx: null, step: 0, bar: 0, next: 0, prevNote: 3,
  init(ctx, dest) {
    this.ctx = ctx;
    this.out = ctx.createGain(); this.out.gain.value = this.on ? 0.5 : 0;
    // "car speaker" colouring: band-limited and slightly warm
    const hp = ctx.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 70;
    const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = CA ? 3200 : 4200;
    this.out.connect(hp); hp.connect(lp); lp.connect(dest);
    this.pad = ctx.createBiquadFilter(); this.pad.type = 'lowpass'; this.pad.frequency.value = CA ? 1100 : 1800; this.pad.connect(this.out);
    const len = ctx.sampleRate, buf = ctx.createBuffer(1, len, ctx.sampleRate), d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    this.noiseBuf = buf;
    if (CA) { // vinyl crackle
      const cb = ctx.createBuffer(1, ctx.sampleRate * 3, ctx.sampleRate), cd = cb.getChannelData(0);
      for (let i = 0; i < cd.length; i++) cd[i] = Math.random() < 0.0006 ? (Math.random() * 2 - 1) : (Math.random() * 2 - 1) * 0.015;
      const cs = ctx.createBufferSource(); cs.buffer = cb; cs.loop = true;
      const cg = ctx.createGain(); cg.gain.value = 0.18; cs.connect(cg); cg.connect(this.out); cs.start();
    }
    this.next = ctx.currentTime + 0.3;
    setInterval(() => this.tick(), 25);
  },
  toggle() {
    this.on = !this.on;
    if (this.out) this.out.gain.setTargetAtTime(this.on ? 0.5 : 0, this.ctx.currentTime, 0.2);
  },
  tick() {
    const ctx = this.ctx, sixteenth = 60 / STATION.bpm / 4;
    if (this.next < ctx.currentTime - 0.2) this.next = ctx.currentTime + 0.05;
    while (this.next < ctx.currentTime + 0.15) {
      const swing = this.step % 2 ? STATION.swing * sixteenth : 0;
      if (this.on) this.play(this.step, this.next + swing, sixteenth);
      this.next += sixteenth;
      this.step = (this.step + 1) % 16;
      if (this.step === 0) this.bar++;
    }
  },
  voice(type, freq, t, dur, vol, attack, release, dest = this.out, detune = 0) {
    const ctx = this.ctx, o = ctx.createOscillator(), g = ctx.createGain();
    o.type = type; o.frequency.value = freq; o.detune.value = detune;
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(vol, t + attack);
    g.gain.setTargetAtTime(0, t + Math.max(attack, dur), release / 3);
    o.connect(g); g.connect(dest);
    o.start(t); o.stop(t + dur + release * 1.5 + 0.05);
  },
  noiseHit(t, vol, type, freq, decay, q = 0.7) {
    const ctx = this.ctx, s = ctx.createBufferSource(), f = ctx.createBiquadFilter(), g = ctx.createGain();
    s.buffer = this.noiseBuf; f.type = type; f.frequency.value = freq; f.Q.value = q;
    g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0008, t + decay);
    s.connect(f); f.connect(g); g.connect(this.out);
    s.start(t, Math.random() * 0.5); s.stop(t + decay + 0.05);
  },
  kick(t, vol) {
    const ctx = this.ctx, o = ctx.createOscillator(), g = ctx.createGain();
    o.frequency.setValueAtTime(110, t); o.frequency.exponentialRampToValueAtTime(42, t + 0.12);
    g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.001, t + 0.32);
    o.connect(g); g.connect(this.out); o.start(t); o.stop(t + 0.35);
  },
  pluck(freq, t, vol) {
    const ctx = this.ctx, o = ctx.createOscillator(), f = ctx.createBiquadFilter(), g = ctx.createGain();
    o.type = 'sawtooth'; o.frequency.value = freq;
    f.type = 'lowpass'; f.frequency.setValueAtTime(2600, t); f.frequency.setTargetAtTime(420, t, 0.07);
    g.gain.setValueAtTime(vol, t); g.gain.setTargetAtTime(0, t + 0.02, 0.18);
    o.connect(f); f.connect(g); g.connect(this.out); o.start(t); o.stop(t + 1.0);
  },
  play(step, t, six) {
    const S = STATION, ci = S.prog[this.bar % S.prog.length];
    const chord = S.chords[ci], root = S.bass[ci];
    const r = Math.random();
    if (CA) {
      if (step === 0) for (const n of chord) { // warm pad
        this.voice('triangle', mtof(n), t, six * 15, 0.03, 0.6, 1.2, this.pad, -6);
        this.voice('sine', mtof(n), t, six * 15, 0.025, 0.8, 1.2, this.pad, 7);
      }
      if (step === 0 || step === 10) this.voice('sine', mtof(root), t, six * 5, 0.2, 0.01, 0.4);
      if (step === 0 || (step === 7 && r < 0.5) || step === 10) this.kick(t, 0.55);
      if (step === 4 || step === 12) { this.noiseHit(t, 0.14, 'bandpass', 1500, 0.16); this.voice('triangle', 190, t, 0.03, 0.05, 0.002, 0.08); }
      if (step % 2 === 0) this.noiseHit(t, step % 4 === 2 ? 0.05 : 0.025, 'highpass', 7000, 0.04);
      if (step % 2 === 0 && r < 0.22) { // keys melody, wandering on a pentatonic scale
        this.prevNote = clamp(this.prevNote + ((Math.random() * 5) | 0) - 2, 0, S.scale.length - 1);
        const f = mtof(S.scale[this.prevNote]);
        this.voice('sine', f, t, 0.05, 0.07, 0.004, 1.4);
        this.voice('sine', f * 2, t, 0.03, 0.015, 0.004, 0.5);
      }
    } else {
      if (step === 0) for (const n of chord) this.voice('sine', mtof(n + 12), t, six * 15, 0.012, 0.9, 1.0, this.pad, 4); // soft steel-ish pad
      if (step % 4 === 0) { // walking bass
        const walk = [0, 4, 7, 9][step / 4];
        this.voice('triangle', mtof(root + walk), t, six * 3, 0.17, 0.01, 0.2);
        this.voice('sine', mtof(root + walk), t, six * 3, 0.12, 0.01, 0.2);
      }
      if (step === 0 || step === 8) this.kick(t, 0.4);
      if (step === 4 || step === 12) this.noiseHit(t, 0.16, 'bandpass', 2600, 0.2, 0.5); // brush snare
      if (step % 2 === 0) this.noiseHit(t, 0.03, 'bandpass', 5000, 0.07, 0.6);
      if (step === 2 || step === 6 || step === 10 || step === 14) { // offbeat strums
        chord.forEach((n, k) => this.pluck(mtof(n + 12), t + k * 0.014, 0.035));
      }
      if (step % 2 === 1 && r < 0.12) { // little guitar licks
        this.prevNote = clamp(this.prevNote + ((Math.random() * 5) | 0) - 2, 0, S.scale.length - 1);
        this.pluck(mtof(S.scale[this.prevNote]), t, 0.06);
      }
    }
  },
};

// ---------------------------------------------------------------------------
// UI & input
// ---------------------------------------------------------------------------
const $ = (id) => document.getElementById(id);
const ui = { hud: $('hud'), buttons: $('buttons'), help: $('help'), title: $('title'), spd: $('spd'), dist: $('dist'), mode: $('mode'), paused: $('paused'), station: $('station'), region: $('regionName'), toast: $('toast') };
let started = false, paused = false, uiHidden = false, touchCruise = false;
const btn = (a) => ui.buttons.querySelector(`[data-act="${a}"]`);
document.body.classList.add('region-' + REGION_ID);
ui.region.textContent = CA ? 'California coast' : 'North Florida';
ui.station.textContent = '♪ ' + STATION.name;
btn('region').textContent = CA ? 'Go to Florida' : 'Go to California';
for (const b of document.querySelectorAll('.region')) b.classList.toggle('current', b.dataset.region === REGION_ID);

let toastTimer = 0;
function toast(msg) { ui.toast.textContent = msg; ui.toast.classList.remove('hidden'); clearTimeout(toastTimer); toastTimer = setTimeout(() => ui.toast.classList.add('hidden'), 1600); }
function setAuto(on) { autoDrive = on; btn('auto').classList.toggle('on', on); }
function cycleCam() { camMode = (camMode + 1) % CAM_MODES.length; cine.set = false; toast('Camera: ' + CAM_MODES[camMode]); }
function nextTime() { presetIdx = (presetIdx + 1) % PRESETS.length; timeTarget = PRESETS[presetIdx]; dayCycle = false; toast(PRESET_NAMES[presetIdx]); }
function toggleSound() { audio.toggle(); btn('sound').classList.toggle('on', audio.on); }
function toggleRadio() { radio.toggle(); btn('radio').classList.toggle('on', radio.on); ui.station.classList.toggle('off', !radio.on); toast(radio.on ? STATION.name : 'Radio off'); }
function gotoRegion(id, go = true) {
  const u = new URL(location.href);
  u.searchParams.set('region', id);
  u.searchParams.delete('seed');
  if (go) u.searchParams.set('go', '1'); else u.searchParams.delete('go');
  location.href = u.toString();
}
function newRoad() { const u = new URL(location.href); u.searchParams.set('seed', (Math.random() * 1e9) | 0); u.searchParams.set('go', '1'); location.href = u.toString(); }
function toggleHelp() { ui.help.classList.toggle('hidden'); btn('help').classList.toggle('on', !ui.help.classList.contains('hidden')); }
function toggleUI() { uiHidden = !uiHidden; ui.hud.classList.toggle('hidden', uiHidden); ui.buttons.classList.toggle('hidden', uiHidden); if (uiHidden) ui.help.classList.add('hidden'); }
function togglePause() { paused = !paused; ui.paused.classList.toggle('hidden', !paused); }
setAuto(true);
btn('sound').classList.add('on');
btn('radio').classList.add('on');

ui.buttons.addEventListener('click', (e) => {
  const a = e.target.dataset && e.target.dataset.act;
  if (!a) return;
  e.stopPropagation();
  ({ auto: () => setAuto(!autoDrive), cam: cycleCam, time: nextTime, radio: toggleRadio, sound: toggleSound,
     region: () => gotoRegion(CA ? 'fl' : 'ca'), new: newRoad, help: toggleHelp })[a]();
  e.target.blur();
});
ui.buttons.addEventListener('pointerdown', (e) => e.stopPropagation());

let ready = false;
function wakeAudio() {
  audio.init();
  if (audio.ctx && audio.ctx.state === 'suspended') audio.ctx.resume();
}
function start() {
  if (started || !ready) return;
  started = true;
  ui.title.classList.add('hidden');
  ui.hud.classList.remove('hidden');
  ui.buttons.classList.remove('hidden');
  wakeAudio();
}
for (const b of document.querySelectorAll('.region')) {
  b.addEventListener('click', (e) => {
    e.stopPropagation();
    if (b.dataset.region === REGION_ID) start(); else gotoRegion(b.dataset.region);
  });
}
ui.title.addEventListener('click', start);
addEventListener('pointerdown', wakeAudio, { once: false });

const KEYMAP = { ArrowUp: 'up', KeyW: 'up', ArrowDown: 'down', KeyS: 'down', ArrowLeft: 'left', KeyA: 'left', ArrowRight: 'right', KeyD: 'right' };
addEventListener('keydown', (e) => {
  wakeAudio();
  if (!started) { if (e.code === 'Digit1') gotoRegion('ca'); else if (e.code === 'Digit2') gotoRegion('fl'); else start(); return; }
  const k = KEYMAP[e.code];
  if (k) {
    input[k] = true; e.preventDefault();
    if ((k === 'up' || k === 'down') && autoDrive) setAuto(false);
    return;
  }
  if (e.repeat) return;
  switch (e.code) {
    case 'KeyE': setAuto(!autoDrive); break;
    case 'KeyC': cycleCam(); break;
    case 'KeyT': nextTime(); break;
    case 'KeyY': dayCycle = !dayCycle; toast(dayCycle ? 'Day cycle on' : 'Day cycle off'); break;
    case 'KeyR': toggleRadio(); break;
    case 'KeyM': toggleSound(); break;
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
  if (e.pointerType === 'touch') {
    activeTouches.set(e.pointerId, e.clientX < innerWidth / 2 ? 'L' : 'R');
    touchCruise = true;
    updateTouch();
  } else {
    look.dragging = true; look.lastX = e.clientX; look.lastY = e.clientY;
    canvas.setPointerCapture(e.pointerId);
  }
});
canvas.addEventListener('pointermove', (e) => {
  if (!look.dragging) return;
  look.yaw = clamp(look.yaw - (e.clientX - look.lastX) * 0.006, -Math.PI, Math.PI);
  look.pitch = clamp(look.pitch + (e.clientY - look.lastY) * 0.004, -0.3, 0.8);
  look.lastX = e.clientX; look.lastY = e.clientY; look.idle = 0;
});
const endPointer = (e) => {
  if (activeTouches.has(e.pointerId)) { activeTouches.delete(e.pointerId); updateTouch(); }
  look.dragging = false; look.idle = 0;
};
canvas.addEventListener('pointerup', endPointer);
canvas.addEventListener('pointercancel', endPointer);
function updateTouch() {
  const v = [...activeTouches.values()];
  input.touchL = v.includes('L'); input.touchR = v.includes('R');
}

addEventListener('resize', () => {
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight);
});

// ---------------------------------------------------------------------------
// Boot & main loop
// ---------------------------------------------------------------------------
{
  while (road.nFinal < 400) addRoadSample();
  const p = roadPoint(500, LANE);
  car.x = p.x; car.z = p.z; car.h = p.h; car.s = 500; camYaw = p.h;
  car.y = p.y; car.v = 16;
}

let last = performance.now(), simT = 0;
let bootFrames = 0;
function frame(now) {
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  if (!ready) {
    const left = streamWorld(40);
    const total = Math.PI * VIEW_CHUNKS * VIEW_CHUNKS;
    $('loadfill').style.width = Math.min(100, 100 * (1 - left / total)) + '%';
    bootFrames++;
    if (left === 0 || bootFrames > 400) {
      ready = true;
      document.body.classList.add('ready');
      $('start').textContent = 'Pick a coast to start driving';
      if (AUTOGO) start();
    }
  } else {
    streamWorld(started ? 6 : 12);
  }
  if (!paused) {
    simT += dt;
    if (dayCycle) timeTarget = (timeTarget + dt / 720) % 1;
    let dT = timeTarget - timeOfDay;
    if (dT < -0.5) dT += 1;
    if (dT > 0.5) dT -= 1;
    timeOfDay = (timeOfDay + dT * Math.min(1, dt * (dayCycle ? 10 : 1.4)) + 1) % 1;
    if (ready) updateCar(dt);
    updateClouds(dt);
  }
  updateSky(simT);
  updateCamera(paused ? 0 : dt);
  audio.update(paused ? 0 : car.v, paused ? 0 : throttle, car.d > ROAD_EDGE + 0.3);
  if (started) {
    ui.spd.textContent = Math.round(Math.abs(car.v) * 2.23694);
    ui.dist.textContent = (car.odo / 1609.34).toFixed(1) + ' mi';
    ui.mode.textContent = autoDrive ? 'auto-drive' : 'manual';
  }
  renderer.render(scene, camera);
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

// for debugging / tests
window.__game = { heightAt, baseH, roadXAtZ, coastDist, car, road, chunks, segments, setTime: (t) => { timeOfDay = timeTarget = t; }, setCam: (m) => { camMode = m; cine.set = false; }, start, isReady: () => ready, SEED, REGION_ID };
