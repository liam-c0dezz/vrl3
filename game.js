// Two Lanes — an endless drive along the California coast or through a South Florida city.
// Main thread: rendering (PBR + HDR bloom + filmic grade), fixed-step vehicle physics, camera,
// seasons & weather, audio, UI. World geometry is generated in a worker (gen-worker.js).
import * as THREE from 'three';
import { createWorld, mulberry32, makeNoise2D, clamp, lerp, smooth, sstep, wrapAngle, K } from './world.js';
import { createGen, SIGN_WORDS } from './gen.js';
import { createCars, CARS, PAINT_SWATCHES } from './cars.js';

// ---------------------------------------------------------------------------
// Params & quality
// ---------------------------------------------------------------------------
const params = new URLSearchParams(location.search);
const HASH = (location.hash || '').slice(1).match(/^(ca|sf|fl)(?:-(\d+))?$/);
const SEED = (parseInt(params.get('seed'), 10) || (HASH && parseInt(HASH[2], 10)) || ((Math.random() * 1e9) | 0)) >>> 0;
const rawRegion = params.get('region') || (HASH && HASH[1]) || 'ca';
const REGION_ID = rawRegion === 'sf' || rawRegion === 'fl' ? 'sf' : 'ca';
const CA = REGION_ID === 'ca', SF = !CA;
let AUTOGO = params.get('go') === '1';
try { if (sessionStorage.getItem('twolanes.go') === '1') { AUTOGO = true; sessionStorage.removeItem('twolanes.go'); } } catch (e) { /* storage unavailable */ }
const DYNRES = params.get('dynres') !== '0';
const MOBILE = matchMedia('(pointer: coarse)').matches || innerWidth < 700;
const QUALITY = {
  view: clamp(parseInt(params.get('view'), 10) || (MOBILE ? 6 : 8), 3, 10),
  shadow: MOBILE ? 2048 : 4096,
  bloomLevels: MOBILE ? 4 : 5,
  pr: Math.min(devicePixelRatio || 1, MOBILE ? 1.5 : 1.75),
};
const { ROAD_HALF, ROAD_EDGE, STEP, WATER, CHUNK, SEG, LANE } = K;
const VIEW_M = QUALITY.view * CHUNK;

const world = createWorld(SEED, REGION_ID);
const { road, roadQuery, roadPoint, groundAt } = world;

// ---------------------------------------------------------------------------
// Renderer, HDR target, bloom, composite
// ---------------------------------------------------------------------------
const canvas = document.getElementById('game');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: 'high-performance', stencil: false });
renderer.toneMapping = THREE.NoToneMapping; // tone mapping happens in the composite pass
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
let prScale = 1;

const scene = new THREE.Scene();
scene.fog = new THREE.Fog(0xcfd8e0, 120, VIEW_M - 10);
const camera = new THREE.PerspectiveCamera(62, innerWidth / innerHeight, 0.3, 9000);

const depthTex = new THREE.DepthTexture(1, 1);
depthTex.type = THREE.UnsignedIntType;
const rtHDR = new THREE.WebGLRenderTarget(1, 1, { type: THREE.HalfFloatType, samples: 4, depthTexture: depthTex });
const FSV = `varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`;
const fsMat = (uniforms, frag) => new THREE.ShaderMaterial({ uniforms, vertexShader: FSV, fragmentShader: frag, depthTest: false, depthWrite: false, toneMapped: false });
const brightMat = fsMat({ tSrc: { value: null }, threshold: { value: 1.5 } }, `
  uniform sampler2D tSrc; uniform float threshold; varying vec2 vUv;
  void main(){ vec3 c = min(texture2D(tSrc, vUv).rgb, vec3(40.0)); float br = max(c.r, max(c.g, c.b));
    float w = smoothstep(threshold, threshold + 0.8, br); gl_FragColor = vec4(c * w, 1.0); }`);
const downMat = fsMat({ tSrc: { value: null }, texel: { value: new THREE.Vector2() } }, `
  uniform sampler2D tSrc; uniform vec2 texel; varying vec2 vUv;
  void main(){ vec2 h = texel * 0.5;
    vec3 s = texture2D(tSrc, vUv).rgb * 4.0 + texture2D(tSrc, vUv - h).rgb + texture2D(tSrc, vUv + h).rgb
           + texture2D(tSrc, vUv + vec2(h.x, -h.y)).rgb + texture2D(tSrc, vUv - vec2(h.x, -h.y)).rgb;
    gl_FragColor = vec4(s / 8.0, 1.0); }`);
const upMat = fsMat({ tSrc: { value: null }, tAdd: { value: null }, texel: { value: new THREE.Vector2() } }, `
  uniform sampler2D tSrc, tAdd; uniform vec2 texel; varying vec2 vUv;
  void main(){ vec2 h = texel * 0.5;
    vec3 s = texture2D(tSrc, vUv + vec2(-h.x * 2.0, 0.0)).rgb + texture2D(tSrc, vUv + vec2(-h.x, h.y)).rgb * 2.0
           + texture2D(tSrc, vUv + vec2(0.0, h.y * 2.0)).rgb + texture2D(tSrc, vUv + vec2(h.x, h.y)).rgb * 2.0
           + texture2D(tSrc, vUv + vec2(h.x * 2.0, 0.0)).rgb + texture2D(tSrc, vUv + vec2(h.x, -h.y)).rgb * 2.0
           + texture2D(tSrc, vUv + vec2(0.0, -h.y * 2.0)).rgb + texture2D(tSrc, vUv + vec2(-h.x, -h.y)).rgb * 2.0;
    gl_FragColor = vec4(s / 12.0 + texture2D(tAdd, vUv).rgb, 1.0); }`);
const LOOKS = ['cinematic', 'poster', 'riso'];
const compU = {
  tColor: { value: rtHDR.texture }, tDepth: { value: depthTex }, tBloom: { value: null }, res: { value: new THREE.Vector2(1, 1) },
  near: { value: camera.near }, far: { value: camera.far }, time: { value: 0 }, look: { value: 0 }, pr: { value: 1 },
  exposure: { value: 1 }, bloom: { value: 0.5 }, sat: { value: 1.08 }, contrast: { value: 1.06 },
  shadowTint: { value: new THREE.Color(0.18, 0.2, 0.32) }, hiTint: { value: new THREE.Color(1.0, 0.96, 0.9) }, ink: { value: new THREE.Color(0.1, 0.08, 0.14) },
  paper: { value: new THREE.Color(1.0, 0.96, 0.9) },
};
const compMat = fsMat(compU, `
  uniform sampler2D tColor, tDepth, tBloom; uniform vec2 res; uniform float near, far, time, look, pr, exposure, bloom, sat, contrast;
  uniform vec3 shadowTint, hiTint, ink, paper; varying vec2 vUv;
  float lin(vec2 uv){ float z = texture2D(tDepth, uv).x * 2.0 - 1.0; return 2.0 * near * far / (far + near - z * (far - near)); }
  float hash(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
  float bayer(vec2 p){ vec2 q = mod(floor(p), 4.0); int i = int(q.x + q.y * 4.0);
    float m[16] = float[16](0.,8.,2.,10.,12.,4.,14.,6.,3.,11.,1.,9.,15.,7.,13.,5.); return (m[i] + 0.5) / 16.0; }
  vec3 aces(vec3 x){ return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0); }
  vec3 toSRGB(vec3 c){ c = clamp(c, 0.0, 1.0); return mix(c * 12.92, 1.055 * pow(c, vec3(1.0/2.4)) - 0.055, step(0.0031308, c)); }
  void main(){
    vec2 px = 1.0 / res, q = vUv - 0.5;
    vec3 c;
    if (look < 0.5) { // subtle lens chromatic aberration toward the edges
      vec2 o = q * dot(q, q) * 0.012;
      c = vec3(texture2D(tColor, vUv - o).r, texture2D(tColor, vUv).g, texture2D(tColor, vUv + o).b);
    } else c = texture2D(tColor, vUv).rgb;
    c += texture2D(tBloom, vUv).rgb * bloom;
    if (look > 0.5) { // ink outlines from depth discontinuities
      float d = lin(vUv), o = max(1.0, pr * 0.8);
      float lap = abs(lin(vUv - vec2(px.x * o, 0.0)) + lin(vUv + vec2(px.x * o, 0.0)) - 2.0 * d)
                + abs(lin(vUv + vec2(0.0, px.y * o)) + lin(vUv - vec2(0.0, px.y * o)) - 2.0 * d);
      float edge = smoothstep(0.025, 0.08, lap / d) * (1.0 - smoothstep(70.0, 260.0, d));
      c = mix(c, ink * 0.3, edge * 0.85);
    }
    c = aces(c * exposure);
    c = toSRGB(c);
    float L = dot(c, vec3(0.2126, 0.7152, 0.0722));
    c = mix(vec3(L), c, sat);
    c = (c - 0.5) * contrast + 0.5;
    c = mix(c, c * shadowTint * 2.2, (1.0 - smoothstep(0.0, 0.45, L)) * 0.35);
    c = mix(c, c * hiTint, smoothstep(0.5, 1.0, L) * 0.4);
    if (look > 0.5 && look < 1.5) c = floor(c * 7.0 + hash(gl_FragCoord.xy) * 0.6 + 0.2) / 7.0; // poster: few tones per channel
    if (look > 1.5) { // riso print
      c = floor(c * 5.0 + bayer(gl_FragCoord.xy / max(1.0, floor(pr)))) / 5.0;
      vec2 hp = mat2(0.7071, -0.7071, 0.7071, 0.7071) * gl_FragCoord.xy / (5.0 * pr);
      float L2 = dot(c, vec3(0.299, 0.587, 0.114)), r = sqrt(clamp(1.0 - L2, 0.0, 1.0)) * 0.55;
      float m = 1.0 - smoothstep(r - 0.08, r + 0.08, length(fract(hp) - 0.5));
      c = mix(c, c * toSRGB(ink) * 1.6, m * 0.45 * (1.0 - smoothstep(0.25, 0.7, L2)));
      c *= paper;
    }
    c += (hash(gl_FragCoord.xy + fract(time) * 97.0) - 0.5) * (look > 1.5 ? 0.09 : 0.03);
    c *= 1.0 - dot(q, q) * (look > 0.5 ? 0.55 : 0.42);
    gl_FragColor = vec4(c, 1.0);
  }`);
const fsScene = new THREE.Scene(), fsCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
const fsQuad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), compMat);
fsQuad.frustumCulled = false;
fsScene.add(fsQuad);
const bloomDown = [], bloomUp = [];
for (let i = 0; i < QUALITY.bloomLevels; i++) {
  bloomDown.push(new THREE.WebGLRenderTarget(1, 1, { type: THREE.HalfFloatType, depthBuffer: false }));
  if (i < QUALITY.bloomLevels - 1) bloomUp.push(new THREE.WebGLRenderTarget(1, 1, { type: THREE.HalfFloatType, depthBuffer: false }));
}
function pass(mat, target) { fsQuad.material = mat; renderer.setRenderTarget(target); renderer.render(fsScene, fsCam); }
function renderBloom() {
  brightMat.uniforms.tSrc.value = rtHDR.texture;
  pass(brightMat, bloomDown[0]);
  for (let i = 1; i < bloomDown.length; i++) {
    downMat.uniforms.tSrc.value = bloomDown[i - 1].texture;
    downMat.uniforms.texel.value.set(1 / bloomDown[i - 1].width, 1 / bloomDown[i - 1].height);
    pass(downMat, bloomDown[i]);
  }
  let src = bloomDown[bloomDown.length - 1];
  for (let i = bloomDown.length - 2; i >= 0; i--) {
    upMat.uniforms.tSrc.value = src.texture; upMat.uniforms.tAdd.value = bloomDown[i].texture;
    upMat.uniforms.texel.value.set(1 / src.width, 1 / src.height);
    pass(upMat, bloomUp[i]);
    src = bloomUp[i];
  }
  return src;
}
function resize() {
  const pr = QUALITY.pr * prScale;
  renderer.setPixelRatio(pr);
  renderer.setSize(innerWidth, innerHeight);
  const w = Math.max(1, Math.floor(innerWidth * pr)), h = Math.max(1, Math.floor(innerHeight * pr));
  rtHDR.setSize(w, h);
  for (let i = 0; i < bloomDown.length; i++) bloomDown[i].setSize(Math.max(1, w >> (i + 1)), Math.max(1, h >> (i + 1)));
  for (let i = 0; i < bloomUp.length; i++) bloomUp[i].setSize(Math.max(1, w >> (i + 1)), Math.max(1, h >> (i + 1)));
  compU.res.value.set(w, h); compU.pr.value = pr;
  camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix();
}
resize();

// ---------------------------------------------------------------------------
// Lights, sky, environment reflections
// ---------------------------------------------------------------------------
const sun = new THREE.DirectionalLight(0xffffff, 3);
sun.castShadow = true;
sun.shadow.mapSize.set(QUALITY.shadow, QUALITY.shadow);
Object.assign(sun.shadow.camera, { left: -65, right: 65, top: 65, bottom: -65, near: 1, far: 800 });
sun.shadow.bias = -0.0003; sun.shadow.normalBias = 0.35;
scene.add(sun, sun.target);
const hemi = new THREE.HemisphereLight(0xbcd0ff, 0x4a4030, 0.25);
scene.add(hemi);

const skyU = {
  zen: { value: new THREE.Color() }, hor: { value: new THREE.Color() }, sunDir: { value: new THREE.Vector3(0, 1, 0) }, sunCol: { value: new THREE.Color() },
  moonDir: { value: new THREE.Vector3(0, 1, 0) }, cloudLit: { value: new THREE.Color() }, cloudShade: { value: new THREE.Color() },
  night: { value: 0 }, cover: { value: 0.3 }, time: { value: 0 }, sunSize: { value: 0.00045 },
};
const skyMat = new THREE.ShaderMaterial({
  uniforms: skyU, side: THREE.BackSide, depthWrite: false, fog: false, toneMapped: false,
  vertexShader: `varying vec3 vDir; void main(){ vDir = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
  fragmentShader: `
    uniform vec3 zen, hor, sunDir, sunCol, moonDir, cloudLit, cloudShade; uniform float night, cover, time, sunSize; varying vec3 vDir;
    float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
    float vn(vec2 p){ vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
      return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y); }
    float fbm(vec2 p){ float s = 0.0, a = 0.5; for (int i = 0; i < 5; i++) { s += a * vn(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; } return s; }
    void main(){
      vec3 d = normalize(vDir); float h = d.y, day = 1.0 - night;
      vec3 c = mix(hor, zen, pow(clamp(h, 0.0, 1.0), 0.45));
      float mu = dot(d, sunDir);
      c += sunCol * (pow(max(mu, 0.0), 6.0) * 0.16 + pow(max(mu, 0.0), 60.0) * 0.5) * day * (1.0 - cover * 0.5);
      c += sunCol * smoothstep(1.0 - sunSize, 1.0 - sunSize * 0.55, mu) * 24.0 * day * (1.0 - cover * 0.8);
      float mm = dot(d, moonDir);
      c += vec3(0.9, 0.92, 1.0) * smoothstep(0.99955, 0.9997, mm) * 4.0 * night + vec3(0.2, 0.25, 0.4) * pow(max(mm, 0.0), 30.0) * 0.4 * night;
      if (h > 0.0) {
        vec2 uv = d.xz / (h + 0.1) * 0.8 + vec2(time * 0.006, time * 0.002);
        float n = fbm(uv * 1.3), n2 = fbm(uv * 1.3 + sunDir.xz * 0.12);
        float cov = smoothstep(1.0 - cover - 0.08, 1.0 - cover + 0.3, n) * smoothstep(0.0, 0.16, h);
        float lit = clamp(0.55 + (n - n2) * 5.0, 0.0, 1.0);
        vec3 cc = mix(cloudShade, cloudLit, lit) + sunCol * pow(max(mu, 0.0), 10.0) * 0.5 * day;
        c = mix(c, cc, cov * 0.94);
      } else c = hor;
      gl_FragColor = vec4(c, 1.0);
    }`,
});
const skyGeo = new THREE.SphereGeometry(6000, 48, 24);
const sky = new THREE.Mesh(skyGeo, skyMat);
sky.renderOrder = -10; sky.frustumCulled = false;
scene.add(sky);
const envScene = new THREE.Scene();
envScene.add(new THREE.Mesh(skyGeo, skyMat));
const pmrem = new THREE.PMREMGenerator(renderer);
let envRT = null, envStamp = { t: -1, cover: -1, rain: -1, at: -99 };
function updateEnv(force) {
  const changed = Math.abs(envStamp.t - timeOfDay) > 0.003 || Math.abs(envStamp.cover - cover) > 0.04 || Math.abs(envStamp.rain - rain) > 0.05;
  if (!force && (!changed || simT - envStamp.at < 1.2)) return;
  const old = envRT;
  envRT = pmrem.fromScene(envScene, 0, 1, 7000);
  scene.environment = envRT.texture;
  if (old) old.dispose();
  envStamp = { t: timeOfDay, cover, rain, at: simT };
}

const stars = (() => {
  const g = new THREE.BufferGeometry(), pos = [], r = mulberry32(99);
  for (let i = 0; i < 1800; i++) {
    const y = 0.04 + r() * 0.96, th = r() * Math.PI * 2, rr = Math.sqrt(1 - y * y);
    pos.push(Math.cos(th) * rr * 5500, y * 5500, Math.sin(th) * rr * 5500);
  }
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  const p = new THREE.Points(g, new THREE.PointsMaterial({ color: 0xfff6e0, size: 1.8, sizeAttenuation: false, transparent: true, opacity: 0, fog: false, depthWrite: false }));
  p.renderOrder = -9; p.frustumCulled = false;
  return p;
})();
scene.add(stars);

// Far horizon: mountain ranges inland (California) or a city skyline with lit windows (Florida)
const horizonU = { hor: { value: new THREE.Color() }, ridge: { value: new THREE.Color() }, night: { value: 0 }, snow: { value: 0 } };
const horizonMat = new THREE.ShaderMaterial({
  uniforms: horizonU, fog: false, side: THREE.DoubleSide, toneMapped: false,
  vertexShader: `attribute vec3 aF; varying vec3 vF; varying float vY; void main(){ vF = aF; vY = position.y; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
  fragmentShader: `
    uniform vec3 hor, ridge; uniform float night, snow; varying vec3 vF; varying float vY;
    float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
    void main(){
      vec3 c = mix(hor, ridge, vF.z);
      if (vF.x < -0.5) { // mountains: snowcaps in winter
        c = mix(c, vec3(0.9, 0.93, 0.98) * mix(1.0, 0.25, night), snow * smoothstep(0.55, 0.62, vY / max(vF.y, 1.0)) * smoothstep(120.0, 160.0, vF.y));
      } else { // skyline: lit windows at night
        vec2 cell = floor(vec2(vF.x / 4.0, vY / 3.6));
        float win = step(0.35, fract(vF.x / 4.0)) * step(0.3, fract(vY / 3.6)) * step(0.5, hash(cell + vF.y));
        c *= 1.0 - win * 0.12 * (1.0 - night);
        c += win * vec3(1.0, 0.78, 0.48) * night * 1.6 * step(2.0, vY);
      }
      gl_FragColor = vec4(c, 1.0);
    }`,
});
const horizon = (() => {
  const pos = [], aF = [], idx = [];
  const nz = makeNoise2D(mulberry32(SEED ^ 0xabc));
  if (CA) {
    [[1700, 0.85], [2500, 0.6], [3500, 0.38]].forEach(([Rr, k], li) => {
      const N = 512, base = pos.length / 3;
      for (let i = 0; i <= N; i++) {
        const th = (i / N) * Math.PI * 2, cx = Math.cos(th), sz = Math.sin(th);
        const inl = sstep(-0.15, 0.35, -cx);
        const n1 = 0.5 + 0.5 * nz(cx * (3 + li * 2) + li * 10, sz * (3 + li * 2)), n2 = 1 - Math.abs(nz(cx * 9 + li, sz * 9 - li));
        const Hm = [60 + 150 * n1 + 40 * n2, 110 + 280 * n1 + 60 * n2, 220 + 480 * n1 + 90 * n2][li];
        const h = Hm * inl - 12 * (1 - inl);
        pos.push(cx * Rr, h, sz * Rr, cx * Rr, -80, sz * Rr);
        aF.push(-1, Hm, k, -1, Hm, k);
        if (i < N) { const a = base + i * 2; idx.push(a, a + 1, a + 2, a + 1, a + 3, a + 2); }
      }
    });
  } else {
    const r = mulberry32(SEED ^ 0x5c1);
    for (let i = 0; i < 260; i++) {
      const th = r() * Math.PI * 2, cx = Math.cos(th), sz = Math.sin(th);
      if (cx < -0.25 && r() < 0.92) continue; // the ocean side stays open
      const Rr = 1300 + r() * 1400, k = lerp(0.85, 0.4, (Rr - 1300) / 1400);
      const cluster = Math.pow(0.5 + 0.5 * nz(cx * 2.5, sz * 2.5), 2);
      const H = 25 + r() * 60 + cluster * (120 + r() * 220), w = 30 + r() * 50;
      const px = cx * Rr, pz = sz * Rr, tx = -sz, tz = cx;
      const c0 = [px - tx * w / 2, pz - tz * w / 2], c1 = [px + tx * w / 2, pz + tz * w / 2];
      const base = pos.length / 3;
      pos.push(c0[0], -40, c0[1], c1[0], -40, c1[1], c1[0], H, c1[1], c0[0], H, c0[1]);
      aF.push(0, i, k, w, i, k, w, i, k, 0, i, k);
      idx.push(base, base + 1, base + 2, base, base + 2, base + 3);
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('aF', new THREE.Float32BufferAttribute(aF, 3));
  g.setIndex(idx);
  const m = new THREE.Mesh(g, horizonMat);
  m.renderOrder = -8; m.frustumCulled = false;
  return m;
})();
scene.add(horizon);

// Water: reflective, with a scrolling ripple normal map
function rippleTexture() {
  const N = 256, cv = document.createElement('canvas'); cv.width = cv.height = N;
  const g = cv.getContext('2d'), img = g.createImageData(N, N), nz = makeNoise2D(mulberry32(42));
  const P = (x, y) => { const a = x / N * Math.PI * 2, b = y / N * Math.PI * 2; return nz(Math.cos(a) * 3, Math.sin(a) * 3 + Math.cos(b) * 3) + 0.5 * nz(Math.sin(b) * 6 + 20, Math.cos(a) * 6) + 0.25 * nz(Math.cos(b) * 12, Math.sin(a) * 12 + 5); };
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    const dx = P(x + 1, y) - P(x - 1, y), dy = P(x, y + 1) - P(x, y - 1), i = (y * N + x) * 4;
    img.data[i] = 128 + dx * 150; img.data[i + 1] = 128 + dy * 150; img.data[i + 2] = 255; img.data[i + 3] = 255;
  }
  g.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(cv);
  t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(220, 220);
  return t;
}
const waterMat = new THREE.MeshStandardMaterial({ color: 0x1f4f66, roughness: 0.07, metalness: 0.15, normalMap: rippleTexture(), normalScale: new THREE.Vector2(0.35, 0.35), transparent: true, opacity: 0.93 });
const water = new THREE.Mesh(new THREE.PlaneGeometry(9000, 9000), waterMat);
water.rotation.x = -Math.PI / 2; water.position.y = WATER; water.receiveShadow = true;
scene.add(water);

// Rain streaks drawn around the camera in the vertex shader
const rainU = { uTime: { value: 0 }, uCam: { value: new THREE.Vector3() }, uRain: { value: 0 }, uWindX: { value: 2 } };
const rainMesh = (() => {
  const N = MOBILE ? 2500 : 6000, pos = new Float32Array(N * 6), aEnd = new Float32Array(N * 2), r = mulberry32(7);
  for (let i = 0; i < N; i++) {
    const x = r() * 60, y = r() * 40, z = r() * 60;
    pos.set([x, y, z, x, y, z], i * 6); aEnd[i * 2] = 0; aEnd[i * 2 + 1] = 1;
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setAttribute('aEnd', new THREE.BufferAttribute(aEnd, 1));
  const m = new THREE.ShaderMaterial({
    uniforms: rainU, transparent: true, depthWrite: false, toneMapped: false,
    vertexShader: `attribute float aEnd; uniform float uTime, uWindX; uniform vec3 uCam; varying float vA;
      void main(){ vec3 p = position; float sp = 22.0 + fract(p.x * 13.1) * 6.0;
        p.y = mod(p.y - uTime * sp, 40.0) - 12.0 + uCam.y;
        p.x = uCam.x + mod(p.x - uCam.x + uTime * uWindX + 30.0, 60.0) - 30.0;
        p.z = uCam.z + mod(p.z - uCam.z + 30.0, 60.0) - 30.0;
        p += vec3(uWindX * 0.03, 0.75, 0.0) * aEnd; vA = 1.0 - aEnd * 0.6;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0); }`,
    fragmentShader: `uniform float uRain; varying float vA; void main(){ gl_FragColor = vec4(vec3(0.75, 0.8, 0.88), 0.32 * uRain * vA); }`,
  });
  const l = new THREE.LineSegments(g, m);
  l.frustumCulled = false; l.renderOrder = 5;
  return l;
})();
scene.add(rainMesh);

// ---------------------------------------------------------------------------
// Textures (procedural canvases)
// ---------------------------------------------------------------------------
const ANISO = renderer.capabilities.getMaxAnisotropy();
function canvasTex(w, h, draw, srgb = true, repeat = true) {
  const cv = document.createElement('canvas'); cv.width = w; cv.height = h;
  draw(cv.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(cv);
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  if (repeat) t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.anisotropy = ANISO;
  return t;
}
const texR = mulberry32(1234);
function speckle(g, x, y, w, h, n, alpha, size = 1.5) {
  for (let i = 0; i < n; i++) { const v = (texR() * 255) | 0; g.fillStyle = `rgba(${v},${v},${v},${alpha})`; g.fillRect(x + texR() * w, y + texR() * h, size, size); }
}
const roadTex = canvasTex(512, 1024, (g, W, H) => {
  const px = W / (2 * ROAD_EDGE), a0 = (ROAD_EDGE - ROAD_HALF) * px, a1 = W - a0;
  if (CA) { g.fillStyle = '#9c8c72'; g.fillRect(0, 0, W, H); speckle(g, 0, 0, W, H, 9000, 0.3, 2); }
  const ax = CA ? a0 : 0, aw = CA ? a1 - a0 : W;
  g.fillStyle = CA ? '#3e3f44' : '#36383d'; g.fillRect(ax, 0, aw, H);
  speckle(g, ax, 0, aw, H, 40000, 0.14, 1.5);
  g.fillStyle = 'rgba(20,20,22,.18)';
  for (const off of [-2.5, -1.0, 1.0, 2.5]) g.fillRect(W / 2 + (off - 0.4) * px, 0, 0.8 * px, H);
  for (let i = 0; i < 5; i++) { // patches and cracks
    g.fillStyle = 'rgba(25,25,28,.25)'; g.fillRect(a0 + texR() * (a1 - a0 - 80), texR() * H, 30 + texR() * 70, 20 + texR() * 120);
    g.strokeStyle = 'rgba(15,15,15,.35)'; g.lineWidth = 1; g.beginPath();
    let x = a0 + texR() * (a1 - a0), y = texR() * H; g.moveTo(x, y);
    for (let k = 0; k < 8; k++) { x += (texR() - 0.5) * 30; y += texR() * 30; g.lineTo(x, y); }
    g.stroke();
  }
  if (SF) { g.fillStyle = '#8f8b84'; g.fillRect(0, 0, 0.3 * px, H); g.fillRect(W - 0.3 * px, 0, 0.3 * px, H); }
  const lw = 0.15 * px, edgeLat = CA ? ROAD_HALF - 0.2 : 3.45;
  g.fillStyle = 'rgba(240,238,228,.92)';
  g.fillRect(W / 2 - edgeLat * px - lw / 2, 0, lw, H);
  g.fillRect(W / 2 + edgeLat * px - lw / 2, 0, lw, H);
  g.fillStyle = 'rgba(236,188,64,.95)';
  g.fillRect(W / 2 - lw * 1.6, 0, lw, H); g.fillRect(W / 2 + lw * 0.6, 0, lw, H);
});
roadTex.wrapS = THREE.ClampToEdgeWrapping;
const sidewalkTex = canvasTex(256, 256, (g, W, H) => {
  g.fillStyle = '#c4beb3'; g.fillRect(0, 0, W, H); speckle(g, 0, 0, W, H, 6000, 0.12, 1.5);
  g.fillStyle = 'rgba(70,65,60,.45)'; g.fillRect(0, 0, W, 2); g.fillRect(0, 0, 2, H);
  g.fillStyle = 'rgba(255,255,255,.08)'; g.fillRect(2, 2, W - 4, 3);
});
// Facades: 8 bays × 8 floors per tile; albedo, roughness and lit-window maps.
function facadeTextures(style) {
  const N = 512, cw = N / 8, fh = N / 8, r = mulberry32(style.length * 977 + style.charCodeAt(0));
  const cells = [];
  for (let j = 0; j < 8; j++) for (let i = 0; i < 8; i++) cells.push({ i, j, lit: r() < 0.38, warm: r() < 0.75, blind: r() });
  const win = (i, j) => {
    if (style === 'deco') return [i * cw + cw * 0.3, j * fh + fh * 0.28, cw * 0.4, fh * 0.42];
    if (style === 'condo') return [i * cw + cw * 0.08, j * fh + fh * 0.2, cw * 0.84, fh * 0.6];
    if (style === 'tower') return [i * cw + 3, j * fh + fh * 0.16, cw - 6, fh * 0.74];
    return [i * cw + cw * 0.3, j * fh + fh * 0.25, cw * 0.4, fh * 0.48];
  };
  const map = canvasTex(N, N, (g) => {
    g.fillStyle = style === 'tower' ? '#c8ccd0' : '#f2efe8'; g.fillRect(0, 0, N, N);
    speckle(g, 0, 0, N, N, 5000, 0.06, 2);
    for (const c of cells) {
      const [x, y, w, h] = win(c.i, c.j);
      if (style === 'deco') { g.fillStyle = 'rgba(0,0,0,.18)'; g.fillRect(x - 6, y - 7, w + 12, 5); }
      if (style === 'house') { g.fillStyle = '#5a8a9a'; g.fillRect(x - 7, y, 6, h); g.fillRect(x + w + 1, y, 6, h); }
      g.fillStyle = '#e8e6e0'; g.fillRect(x - 2, y - 2, w + 4, h + 4);
      const gr = g.createLinearGradient(x, y, x + w, y + h);
      gr.addColorStop(0, '#2a3a4a'); gr.addColorStop(1, '#1a2430');
      g.fillStyle = gr; g.fillRect(x, y, w, h);
      if (c.blind > 0.6) { g.fillStyle = 'rgba(220,215,200,.55)'; g.fillRect(x, y, w, h * (c.blind - 0.5)); }
      if (style === 'condo' || style === 'tower') { g.fillStyle = 'rgba(210,214,220,.9)'; g.fillRect(x + w / 2 - 1, y, 2, h); }
    }
    if (style === 'tower') { g.fillStyle = 'rgba(150,160,170,.9)'; for (let j = 0; j < 8; j++) g.fillRect(0, j * fh, N, fh * 0.14); }
  });
  const rough = canvasTex(N, N, (g) => {
    g.fillStyle = style === 'tower' ? '#606060' : '#d8d8d8'; g.fillRect(0, 0, N, N);
    g.fillStyle = '#141414';
    for (const c of cells) { const [x, y, w, h] = win(c.i, c.j); g.fillRect(x, y, w, h); }
  }, false);
  const lit = canvasTex(N, N, (g) => {
    g.fillStyle = '#000'; g.fillRect(0, 0, N, N);
    for (const c of cells) {
      if (!c.lit) continue;
      const [x, y, w, h] = win(c.i, c.j);
      g.fillStyle = c.warm ? '#ffd9a0' : '#cfe4ff'; g.fillRect(x, y, w, h);
      if (c.blind > 0.6) { g.fillStyle = 'rgba(0,0,0,.4)'; g.fillRect(x, y, w, h * (c.blind - 0.5)); }
    }
  });
  return { map, rough, lit };
}
const signTex = canvasTex(1024, 1024, (g, W) => {
  const cs = W / 4, cols = ['#ff3d9a', '#2ff3ff', '#b45cff', '#ffe14d', '#3dff9a', '#ff6a3d'];
  g.clearRect(0, 0, W, W);
  SIGN_WORDS.forEach((word, i) => {
    const cx = (i % 4) * cs + cs / 2, cy = ((i / 4) | 0) * cs + cs / 2, color = cols[i % cols.length];
    const size = Math.min(cs * 0.36, (cs * 1.6) / word.length);
    g.font = `800 ${size}px "Archivo", "Arial Black", sans-serif`; g.textAlign = 'center'; g.textBaseline = 'middle';
    g.shadowColor = color; g.shadowBlur = 22; g.fillStyle = color; g.fillText(word, cx, cy);
    g.shadowBlur = 0; g.fillStyle = '#ffffff'; g.fillText(word, cx, cy);
    g.strokeStyle = color; g.lineWidth = 4; g.shadowColor = color; g.shadowBlur = 14;
    g.strokeRect(cx - cs * 0.46, cy - cs * 0.3, cs * 0.92, cs * 0.6);
  });
}, true, false);

// ---------------------------------------------------------------------------
// Materials (+ seasons, wind and wet-ground shader hooks)
// ---------------------------------------------------------------------------
const seasonU = {
  uSeason: { value: new THREE.Vector4(0, 1, 0, 0) }, uCA: { value: CA ? 1 : 0 }, uWet: { value: 0 }, uTime: { value: 0 },
  uWind: { value: 1 }, uHoliday: { value: 0 },
};
function seasonize(mat, sway) {
  mat.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, seasonU);
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nattribute vec2 aSea; varying vec2 vSea; varying vec3 vWP; uniform float uTime, uWind;')
      .replace('#include <begin_vertex>', `#include <begin_vertex>
        vSea = aSea;
        vec4 wp0 = modelMatrix * vec4(transformed, 1.0);
        ${sway ? `if ((aSea.x > 0.5 && aSea.x < 1.5) || aSea.x > 3.5) {
          float ph = uTime * 1.7 + wp0.x * 0.23 + wp0.z * 0.19 + aSea.y * 6.0;
          transformed.x += sin(ph) * 0.06 * uWind; transformed.z += cos(ph * 0.83) * 0.05 * uWind; transformed.y += sin(ph * 1.3) * 0.02 * uWind; }` : ''}
        vWP = wp0.xyz;`);
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', '#include <common>\nvarying vec2 vSea; varying vec3 vWP; uniform vec4 uSeason; uniform float uCA, uWet, uHoliday;')
      .replace('#include <color_fragment>', `#include <color_fragment>
        {
          float st = vSea.x, sr = vSea.y; vec3 c = diffuseColor.rgb;
          if (st > 0.5 && st < 1.5) {
            vec3 fall = mix(vec3(0.72, 0.2, 0.03), vec3(0.85, 0.52, 0.06), sr); fall = mix(fall, vec3(0.42, 0.06, 0.04), step(0.82, sr));
            vec3 spring = mix(c * vec3(1.15, 1.3, 1.0), vec3(0.95, 0.55, 0.68), step(0.78, sr) * 0.85);
            vec3 winter = mix(c, vec3(0.3, 0.24, 0.18), 0.55);
            c = c * uSeason.y + spring * uSeason.x + fall * uSeason.z + winter * uSeason.w;
          } else if (st > 1.5 && st < 2.5) {
            if (uCA > 0.5) {
              vec3 green = mix(vec3(0.14, 0.3, 0.06), vec3(0.26, 0.4, 0.09), sr);
              vec3 spring = mix(green * 1.15, vec3(0.75, 0.55, 0.08), step(0.86, sr));
              c = c * uSeason.y + spring * uSeason.x + mix(c, c * vec3(0.85, 0.78, 0.7), 0.5) * uSeason.z + mix(c, green, 0.85) * uSeason.w;
              vec3 wn = normalize(cross(dFdx(vWP), dFdy(vWP)));
              float snow = smoothstep(52.0, 66.0, vWP.y + sr * 10.0) * smoothstep(0.7, 0.88, abs(wn.y)) * uSeason.w;
              c = mix(c, vec3(0.9, 0.93, 0.97), snow);
            } else {
              c = c * (uSeason.x + uSeason.y) + c * vec3(1.08, 1.02, 0.8) * uSeason.w + c * 0.94 * uSeason.z;
            }
          } else if (st > 3.5 && st < 4.5) {
            c *= uSeason.y + uSeason.x * 1.08 + uSeason.z * 0.95 + uSeason.w * 0.86;
          } else if (st > 4.5) {
            vec3 bloom = mix(vec3(0.8, 0.08, 0.4), vec3(0.95, 0.3, 0.6), sr);
            c = mix(c, bloom, step(0.3, sr) * (uSeason.x + uSeason.y * 0.85 + uSeason.z * 0.3 + uSeason.w * 0.15));
          }
          diffuseColor.rgb = c * (1.0 - uWet * 0.28);
        }`)
      .replace('#include <roughnessmap_fragment>', `#include <roughnessmap_fragment>
        roughnessFactor = mix(roughnessFactor, 0.28, uWet * step(1.5, vSea.x) * step(vSea.x, 2.5));`)
      .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
        if (vSea.x > 2.5 && vSea.x < 3.5 && uHoliday > 0.01) {
          float band = vWP.y * 1.6 + vSea.y * 7.0;
          float on = smoothstep(0.8, 0.92, fract(band));
          float k = mod(floor(band), 4.0);
          vec3 lc = k < 1.0 ? vec3(1.0, 0.12, 0.08) : k < 2.0 ? vec3(0.1, 1.0, 0.3) : k < 3.0 ? vec3(1.0, 0.75, 0.2) : vec3(0.2, 0.5, 1.0);
          totalEmissiveRadiance += lc * on * uHoliday * 6.0;
        }`);
  };
  mat.customProgramCacheKey = () => 'season-' + (sway ? 1 : 0);
  return mat;
}
const std = (o) => new THREE.MeshStandardMaterial(o);
const FAC = { deco: facadeTextures('deco'), condo: facadeTextures('condo'), tower: facadeTextures('tower'), house: facadeTextures('house') };
const facadeMat = (t, metal = 0) => std({ map: t.map, roughnessMap: t.rough, emissiveMap: t.lit, emissive: 0xffffff, emissiveIntensity: 0, vertexColors: true, roughness: 1, metalness: metal });
const MATS = {
  terrain: seasonize(std({ vertexColors: true, roughness: 0.95 }), false),
  props: seasonize(std({ vertexColors: true, roughness: 0.82, side: THREE.DoubleSide }), true),
  trim: std({ vertexColors: true, roughness: 0.72 }),
  glass: std({ color: 0x52697a, roughness: 0.06, metalness: 0.45, emissive: 0xffc890, emissiveIntensity: 0 }),
  rail: std({ color: 0xa9d0dc, roughness: 0.05, metalness: 0.3, transparent: true, opacity: 0.35, depthWrite: false }),
  neon: new THREE.MeshBasicMaterial({ vertexColors: true }),
  sign: new THREE.MeshBasicMaterial({ map: signTex, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending }),
  pool: std({ color: 0x3fd0e8, roughness: 0.04, metalness: 0.1, emissive: 0x18a8c8, emissiveIntensity: 0.15 }),
  road: std({ map: roadTex, roughness: 0.88 }),
  road2: std({ color: 0x3a3c41, roughness: 0.9, polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -2 }),
  paint: std({ color: 0xeeeeea, roughness: 0.6, polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -6 }),
  sidewalk: std({ map: sidewalkTex, roughness: 0.9 }),
  facade_deco: facadeMat(FAC.deco), facade_condo: facadeMat(FAC.condo), facade_tower: facadeMat(FAC.tower, 0.55), facade_house: facadeMat(FAC.house),
};
const NO_SHADOW = new Set(['neon', 'sign', 'paint', 'road', 'road2', 'sidewalk', 'rail', 'pool']);
const FACADES = [MATS.facade_deco, MATS.facade_condo, MATS.facade_tower, MATS.facade_house];

// ---------------------------------------------------------------------------
// World streaming: requests go to the worker, results become meshes
// ---------------------------------------------------------------------------
const chunks = new Map(), segments = new Map(), pending = new Map(), uploads = [], fallbackQueue = [];
const hkey = (cx, cz) => cx * 1048576 + cz;
let worker = null, workerReady = false, fallbackGen = null;
function useFallback() {
  if (fallbackGen) return;
  if (worker) { worker.terminate(); worker = null; }
  workerReady = false;
  fallbackGen = createGen(THREE, SEED, REGION_ID);
  for (const req of pending.values()) fallbackQueue.push(req);
}
function startWorker() {
  try {
    worker = new Worker(new URL('./gen-worker.js', import.meta.url), { type: 'module' });
    worker.onmessage = (e) => {
      const m = e.data;
      if (m.type === 'ready') { workerReady = true; return; }
      if (m.type === 'error') { console.warn('world generation:', m.message); pending.delete(m.key); return; }
      uploads.push(m);
    };
    worker.onerror = (e) => { console.warn('worker failed, generating on the main thread:', e.message); useFallback(); };
    const threeUrl = import.meta.resolve ? import.meta.resolve('three') : new URL('./vendor/three.module.min.js', import.meta.url).href;
    worker.postMessage({ type: 'init', seed: SEED, region: REGION_ID, threeUrl });
  } catch (err) { useFallback(); }
}
startWorker();
setTimeout(() => { if (!workerReady && !fallbackGen) useFallback(); }, 8000);

function request(req) {
  pending.set(req.key, req);
  if (fallbackGen) fallbackQueue.push(req);
  else worker.postMessage(req);
}
function buildGeometry(a, index) {
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(a.position, 3));
  g.setAttribute('normal', new THREE.BufferAttribute(a.normal, 3));
  g.setAttribute('color', new THREE.BufferAttribute(a.color, 3));
  if (a.uv) g.setAttribute('uv', new THREE.BufferAttribute(a.uv, 2));
  g.setAttribute('aSea', new THREE.BufferAttribute(a.aSea, 2));
  if (index) g.setIndex(new THREE.BufferAttribute(index, 1));
  g.computeBoundingSphere();
  return g;
}
function meshesFrom(groups, ox, oz) {
  const out = [];
  for (const name in groups) {
    const mat = MATS[name];
    if (!mat) continue;
    const mesh = new THREE.Mesh(buildGeometry(groups[name]), mat);
    mesh.position.set(ox, 0, oz);
    mesh.castShadow = !NO_SHADOW.has(name); mesh.receiveShadow = name !== 'neon' && name !== 'sign';
    if (name === 'rail' || name === 'sign') mesh.renderOrder = 2;
    mesh.matrixAutoUpdate = false; mesh.updateMatrix();
    scene.add(mesh); out.push(mesh);
  }
  return out;
}
function upload(m) {
  if (m.type === 'chunk') {
    const key = hkey(m.cx, m.cz);
    pending.delete('c' + key);
    if (chunks.has(key) || !chunkWanted(m.cx, m.cz)) return;
    const t = m.terrain;
    const terrain = new THREE.Mesh(buildGeometry(t, t.index), MATS.terrain);
    terrain.position.set(m.ox, 0, m.oz); terrain.receiveShadow = true;
    terrain.matrixAutoUpdate = false; terrain.updateMatrix();
    scene.add(terrain);
    chunks.set(key, { cx: m.cx, cz: m.cz, meshes: [terrain, ...meshesFrom(m.groups, m.ox, m.oz)], foot: m.foot });
  } else if (m.type === 'segment') {
    pending.delete('s' + m.k);
    if (segments.has(m.k) || !segWanted(m.k)) return;
    segments.set(m.k, { meshes: meshesFrom(m.groups, m.ox, m.oz), lights: m.lights, foot: m.foot });
  }
}
function dispose(entry) { for (const mesh of entry.meshes) { scene.remove(mesh); mesh.geometry.dispose(); } }
let segRange = [0, 0];
function segWanted(k) { return k >= segRange[0] - 1 && k <= segRange[1] + 1; }
function chunkWanted(cx, cz) { return Math.hypot((cx + 0.5) * CHUNK - car.x, (cz + 0.5) * CHUNK - car.z) < VIEW_M + CHUNK * 1.5; }
function streamWorld(budgetMs, maxUploads) {
  const t0 = performance.now();
  world.ensureRoadZ(car.z + VIEW_M + 300);
  let n = 0; // uploads first, spread over frames so nothing hitches
  while (uploads.length && n < maxUploads && (n === 0 || performance.now() - t0 < budgetMs)) { upload(uploads.shift()); n++; }
  if (fallbackGen) {
    while (fallbackQueue.length && performance.now() - t0 < budgetMs + 4) {
      const req = fallbackQueue.shift();
      if (!pending.has(req.key)) continue;
      uploads.push((req.type === 'chunk' ? fallbackGen.chunk(req.cx, req.cz) : fallbackGen.segment(req.k)).msg);
    }
  }
  const ci = Math.floor(car.s / STEP);
  segRange = [Math.max(0, Math.floor((ci - 300) / SEG)), Math.floor((ci + 480) / SEG)];
  for (const [k, s] of segments) if (!segWanted(k)) { dispose(s); segments.delete(k); }
  for (const [key, c] of chunks) if (!chunkWanted(c.cx, c.cz)) { dispose(c); chunks.delete(key); }
  const MAXQ = fallbackGen ? 2 : 4;
  const segOrder = [];
  for (let k = segRange[0]; k <= segRange[1]; k++) if (!segments.has(k) && !pending.has('s' + k)) segOrder.push(k);
  segOrder.sort((a, b) => Math.abs(a * SEG - ci) - Math.abs(b * SEG - ci));
  const todo = [];
  const ccx = Math.floor(car.x / CHUNK), ccz = Math.floor(car.z / CHUNK), fx = Math.sin(car.h), fz = Math.cos(car.h), RV = QUALITY.view;
  for (let a = -RV - 1; a <= RV + 1; a++) for (let b = -RV - 1; b <= RV + 1; b++) {
    const cx = ccx + a, cz = ccz + b, key = hkey(cx, cz);
    if (chunks.has(key) || pending.has('c' + key)) continue;
    const dx = (cx + 0.5) * CHUNK - car.x, dz = (cz + 0.5) * CHUNK - car.z, dist = Math.hypot(dx, dz);
    if (dist > VIEW_M + CHUNK * 0.7) continue;
    todo.push({ cx, cz, key, p: dist * (1.25 - 0.5 * ((dx * fx + dz * fz) / (dist || 1))) });
  }
  todo.sort((p, q) => p.p - q.p);
  let si = 0, ti = 0;
  while (pending.size < MAXQ && (si < segOrder.length || ti < todo.length)) {
    const segNext = si < segOrder.length ? Math.abs(segOrder[si] * SEG - ci) * STEP : Infinity;
    const chunkNext = ti < todo.length ? todo[ti].p : Infinity;
    if (segNext <= chunkNext + 60) { const k = segOrder[si++]; request({ type: 'segment', k, key: 's' + k }); }
    else { const c = todo[ti++]; request({ type: 'chunk', cx: c.cx, cz: c.cz, key: 'c' + c.key }); }
  }
  return todo.length + segOrder.length + pending.size + uploads.length;
}

// ---------------------------------------------------------------------------
// Vehicles
// ---------------------------------------------------------------------------
const VM = {
  paint: new THREE.MeshPhysicalMaterial({ color: 0xb0090f, metalness: 0.5, roughness: 0.28, clearcoat: 1, clearcoatRoughness: 0.04 }),
  chrome: std({ color: 0xe8eaec, metalness: 1, roughness: 0.12 }),
  glass: std({ color: 0x0b1118, metalness: 0.65, roughness: 0.03, transparent: true, opacity: 0.78 }),
  rubber: std({ color: 0x18181a, roughness: 0.92 }),
  dark: std({ color: 0x1c1d20, roughness: 0.6 }),
  seat: std({ color: 0x2a1d1a, roughness: 0.7 }),
  head: std({ color: 0xffffff, emissive: 0xfff2d8, emissiveIntensity: 0.4, roughness: 0.2 }),
  tail: std({ color: 0x400000, emissive: 0xff1a10, emissiveIntensity: 1.2, roughness: 0.3 }),
  plate: std({ color: 0xf2f2ea, roughness: 0.6 }),
  white: std({ color: 0xf6f2ea, roughness: 0.5 }),
};
const carsLib = createCars(THREE, VM);
// The player's car: chosen in the garage, remembered between visits. Starts on a procedural car and
// swaps to the detailed model as soon as it has loaded.
let player = null, carSpec = CARS[0], heroReady = false;
function installPlayer(rig) {
  const old = player;
  if (old) scene.remove(old.car);
  player = rig; scene.add(rig.car);
  WB = rig.wheelBase;
}
function chooseCar(id, paintHex) {
  const spec = CARS.find((c) => c.id === id) || CARS[0];
  carSpec = spec;
  VM.paint.color.setHex(paintHex ?? spec.color);
  if (spec.model) {
    if (!player) installPlayer(carsLib.buildProcedural(CARS[1]));
    return carsLib.buildModel(spec).then((rig) => { if (carSpec === spec) installPlayer(rig); heroReady = true; })
      .catch((e) => { console.warn('car model failed to load, using a procedural car', e); heroReady = true; if (carSpec === spec) installPlayer(carsLib.buildProcedural(CARS[1])); });
  }
  installPlayer(carsLib.buildProcedural(spec));
  heroReady = true;
  return Promise.resolve();
}
let WB = 2.8;

// Oncoming traffic: a pool of lower-detail versions of the procedural cars, reused
const TRAFFIC_COLORS = [0xf2c45a, 0x7fd1c7, 0xf4efe4, 0x8fb2f0, 0xe0533a, 0x2b2d33, 0xb8bcc4, 0x5a7a4a, 0xb0090f, 0x1f6fff];
const traffic = [];
const trafficPool = Array.from({ length: 12 }, (_, i) => {
  const paint = new THREE.MeshPhysicalMaterial({ color: TRAFFIC_COLORS[i % TRAFFIC_COLORS.length], metalness: 0.45, roughness: 0.32, clearcoat: 0.8, clearcoatRoughness: 0.08 });
  const rig = carsLib.buildProcedural(CARS[1 + (i % (CARS.length - 1))], { lod: true, paint });
  rig.car.remove(rig.beam, rig.beam.target);
  rig.car.visible = false; scene.add(rig.car);
  return rig.car;
});
const trafficRng = mulberry32(SEED ^ 0x7a1);

// ---------------------------------------------------------------------------
// Vehicle physics: fixed 120 Hz step, rendered with interpolation
// ---------------------------------------------------------------------------
const car = { x: 0, z: 0, y: 0, h: 0, vx: 0, vz: 0, yawRate: 0, steer: 0, pitch: 0, roll: 0, pv: 0, rv: 0, yv: 0, spin: 0, s: 0, lat: 0, d: 0, odo: 0, v: 0, vL: 0, comp: [0, 0, 0, 0] };
const prev = { x: 0, y: 0, z: 0, h: 0, pitch: 0, roll: 0, steer: 0, spin: 0 };
const input = { up: false, down: false, left: false, right: false, hand: false, axis: 0 }; // axis: analog steering from the touch pad (-1..1, + = left)
let autoDrive = true, throttle = 0, brake = 0, shake = 0, cruise = CA ? 24.6 : 20.1, wetTime = 0;
const PHYS_DT = 1 / 120;
let physAcc = 0, alpha = 0;
const _cq = world.Q();
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
function wallLimit(z, side, s) {
  return world.districtAt(z) === 'causeway' ? ROAD_EDGE - 0.6 : Infinity;
}
const spring = (x, v, target, w, zeta, dt) => { v += (w * w * (target - x) - 2 * zeta * w * v) * dt; return [x + v * dt, v]; };
function physicsStep(dt) {
  roadQuery(car.x, car.z, _cq);
  if (_cq.d !== Infinity) { car.s = _cq.s; car.lat = _cq.lat; car.d = _cq.d; } else car.d = 99;
  const manualSteer = clamp((input.left ? 1 : 0) - (input.right ? 1 : 0) + input.axis, -1, 1);
  if (Math.abs(manualSteer) > 0.08 && autoDrive) setAuto(false);
  const fx = Math.sin(car.h), fz = Math.cos(car.h), lx = Math.cos(car.h), lz = -Math.sin(car.h);
  let vF = car.vx * fx + car.vz * fz, vL = car.vx * lx + car.vz * lz;
  let thr = 0, brk = 0;
  if (autoDrive) {
    if (input.up) cruise = Math.min(cruise + dt * 6, 40);
    if (input.down) cruise = Math.max(cruise - dt * 8, 6);
    const la = 10 + Math.abs(vF) * 0.8;
    const tp = roadPoint(car.s + la, LANE);
    const al = wrapAngle(Math.atan2(tp.x - car.x, tp.z - car.z) - car.h);
    const steerTarget = clamp(Math.atan(2 * WB * Math.sin(al) / Math.hypot(tp.x - car.x, tp.z - car.z)), -0.55, 0.55);
    const c = curvatureAhead(car.s, 40 + vF * 2.5);
    let gapA = stopLineGap(car.s, 1, vF);
    for (const t of traffic) if (t.lane > 0) { const d = t.s - car.s; if (d > 0 && d < gapA) gapA = d; }
    const vt = Math.min(cruise, isCityAt(car.s) ? CITY_SPEED + Math.max(0, cruise - 24.6) : 99, Math.sqrt(2.8 / Math.max(c, 1e-4)), car.d > ROAD_EDGE ? 10 : 99, Math.sqrt(2 * 3.5 * Math.max(0, gapA - 8)));
    if (vF < vt - 0.3) thr = clamp((vt - vF) * 0.4, 0.12, 1);
    else if (vF > vt + 0.8) brk = clamp((vF - vt) * 0.18, 0, 1);
    car.steer += (steerTarget - car.steer) * (1 - Math.exp(-dt * 6));
  } else {
    const steerTarget = manualSteer * (0.55 / (1 + Math.abs(vF) / 13));
    if (input.up) thr = 1;
    if (input.down) brk = 1;
    const rate = input.axis !== 0 ? 3.2 : manualSteer === 0 ? 2.4 : 1.5; // analog pad follows the finger; keys ease in, return faster
    car.steer += clamp(steerTarget - car.steer, -rate * dt, rate * dt);
  }
  throttle += (thr - throttle) * (1 - Math.exp(-dt * 5));
  brake = brk;
  const onRoad = car.d < ROAD_EDGE + 0.3 || (world.citySide(car.z, 1) && world.baseH(car.x, car.z) > 0.8); // city streets & plazas count as paved
  const inWater = groundAt(car.x, car.z) < WATER - 0.3;
  const vmax = carSpec.vmax;
  let acc = throttle * carSpec.acc * Math.max(0, 1 - vF / vmax);
  if (brk > 0) { if (vF > 0.3) acc -= 11 * brk; else if (!autoDrive) acc -= 4 * brk; }
  if (input.hand) acc -= Math.sign(vF) * 5;
  acc -= 0.25 * Math.sign(vF) + 0.0011 * vF * Math.abs(vF);
  if (!onRoad) acc -= Math.sign(vF) * (1.2 + Math.abs(vF) * (inWater ? 0.45 : 0.05));
  acc -= 9.8 * Math.sin(-car.pitch) * 0.6;
  const vF0 = vF;
  vF += acc * dt;
  if (vF0 > 0 && vF < 0 && (autoDrive || !(brk > 0))) vF = 0;
  if (throttle < 0.01 && !(brk > 0) && Math.abs(vF) < 0.2) vF = 0;
  vF = clamp(vF, -8, vmax);
  // yaw: bicycle model with a lateral-grip limit; the handbrake lets the tail step out
  const maxLat = input.hand ? 14 : onRoad ? carSpec.grip : 6;
  const lim = maxLat / Math.max(Math.abs(vF), 1);
  const yawT = clamp((vF * Math.tan(car.steer)) / WB, -lim, lim) * (input.hand ? 1.45 : 1);
  car.yawRate += (yawT - car.yawRate) * (1 - Math.exp(-dt * (input.hand ? 4 : 11)));
  car.h += car.yawRate * dt;
  vL *= Math.exp(-(input.hand ? 1.6 : onRoad ? 13 : 7) * dt);
  const nfx = Math.sin(car.h), nfz = Math.cos(car.h), nlx = Math.cos(car.h), nlz = -Math.sin(car.h);
  car.vx = nfx * vF + nlx * vL; car.vz = nfz * vF + nlz * vL;
  car.x += car.vx * dt; car.z += car.vz * dt;
  car.v = vF; car.vL = vL;
  car.odo += Math.hypot(car.vx, car.vz) * dt;
  // walls: buildings line the sidewalks in the city; barriers on the causeways
  if (_cq.d !== Infinity) {
    const side = Math.sign(car.lat) || 1, wl = wallLimit(car.z, side, car.s);
    if (Math.abs(car.lat) > wl) {
      const rx = -_cq.dz, rz = _cq.dx, push = Math.abs(car.lat) - wl;
      car.x -= rx * side * push; car.z -= rz * side * push;
      const vOut = (car.vx * rx + car.vz * rz) * side;
      if (vOut > 0) {
        const fr = Math.exp(-dt * 1.5); // scraping along a wall costs a little speed, per second not per step
        car.vx = (car.vx - rx * side * vOut * 1.25) * fr; car.vz = (car.vz - rz * side * vOut * 1.25) * fr;
        if (vOut > 3) { shake = Math.min(1, vOut * 0.08); thud(vOut); }
      }
    }
  }
  collideBuildings();
  // suspension: each wheel finds the ground; the body rides on damped springs
  const hw = WB / 2, tr = player.track;
  const gFL = groundAt(car.x + nfx * hw + nlx * tr, car.z + nfz * hw + nlz * tr), gFR = groundAt(car.x + nfx * hw - nlx * tr, car.z + nfz * hw - nlz * tr);
  const gBL = groundAt(car.x - nfx * hw + nlx * tr, car.z - nfz * hw + nlz * tr), gBR = groundAt(car.x - nfx * hw - nlx * tr, car.z - nfz * hw - nlz * tr);
  const gy = (gFL + gFR + gBL + gBR) / 4;
  [car.y, car.yv] = spring(car.y, car.yv, gy, 16, 0.85, dt);
  if (car.y < gy - 0.04) { car.y = gy - 0.04; car.yv = Math.max(car.yv, 0); }
  const latAcc = vF * car.yawRate;
  const pT = -Math.atan2((gFL + gFR) / 2 - (gBL + gBR) / 2, WB) - clamp(acc * 0.0045, -0.04, 0.04);
  const rT = Math.atan2((gFL + gBL) / 2 - (gFR + gBR) / 2, tr * 2) - clamp(latAcc * 0.0065, -0.06, 0.06);
  [car.pitch, car.pv] = spring(car.pitch, car.pv, pT, 10, 0.7, dt);
  [car.roll, car.rv] = spring(car.roll, car.rv, rT, 9, 0.65, dt);
  const planeY = (px, pz) => car.y + pz * Math.sin(-car.pitch) + px * Math.sin(car.roll);
  car.comp = [gFL - planeY(tr, hw), gFR - planeY(-tr, hw), gBL - planeY(tr, -hw), gBR - planeY(-tr, -hw)];
  car.spin += (vF * dt) / player.R;
  wetTime = inWater ? wetTime + dt : 0; // drove into the sea? back to the road
  if (wetTime > 1.6) { returnToRoad(); toast('back on the road'); }
}
// Solid buildings: the car is two circles (front/back) tested against nearby oriented footprints.
const nearFoot = [];
function gatherFootprints() {
  nearFoot.length = 0;
  const add = (f) => {
    if (!f) return;
    for (let i = 0; i < f.length; i += 5) {
      const dx = f[i] - car.x, dz = f[i + 1] - car.z, r = Math.max(f[i + 3], f[i + 4]) + 45;
      if (dx * dx + dz * dz < r * r) nearFoot.push(f[i], f[i + 1], f[i + 2], f[i + 3], f[i + 4]);
    }
  };
  for (const c of chunks.values()) if (Math.abs((c.cx + 0.5) * CHUNK - car.x) < 110 && Math.abs((c.cz + 0.5) * CHUNK - car.z) < 110) add(c.foot);
  for (const sg of segments.values()) add(sg.foot);
}
function collideBuildings() {
  const fx = Math.sin(car.h), fz = Math.cos(car.h), RAD = 1.0;
  for (const off of [1.25, -1.25]) {
    const px = car.x + fx * off, pz = car.z + fz * off;
    for (let i = 0; i < nearFoot.length; i += 5) {
      const cs = Math.cos(nearFoot[i + 2]), sn = Math.sin(nearFoot[i + 2]), hx = nearFoot[i + 3], hz = nearFoot[i + 4];
      const dx = px - nearFoot[i], dz = pz - nearFoot[i + 1];
      const lx = dx * cs - dz * sn, lz = dx * sn + dz * cs;
      if (Math.abs(lx) > hx + RAD || Math.abs(lz) > hz + RAD) continue;
      let nx, nz, pen;
      const qx = clamp(lx, -hx, hx), qz = clamp(lz, -hz, hz), ox = lx - qx, oz = lz - qz, dist = Math.hypot(ox, oz);
      if (dist > 1e-4) { if (dist >= RAD) continue; nx = ox / dist; nz = oz / dist; pen = RAD - dist; }
      else if (hx - Math.abs(lx) < hz - Math.abs(lz)) { nx = Math.sign(lx) || 1; nz = 0; pen = hx - Math.abs(lx) + RAD; }
      else { nx = 0; nz = Math.sign(lz) || 1; pen = hz - Math.abs(lz) + RAD; }
      const wx = nx * cs + nz * sn, wz = -nx * sn + nz * cs; // back to world space
      car.x += wx * pen; car.z += wz * pen;
      const vn = car.vx * wx + car.vz * wz;
      if (vn < 0) {
        car.vx -= wx * vn * 1.3; car.vz -= wz * vn * 1.3;
        car.vx *= 0.9; car.vz *= 0.9;
        if (-vn > 3) { shake = Math.min(1, -vn * 0.07); thud(-vn); }
      }
    }
  }
}
function savePrev() { prev.x = car.x; prev.y = car.y; prev.z = car.z; prev.h = car.h; prev.pitch = car.pitch; prev.roll = car.roll; prev.steer = car.steer; prev.spin = car.spin; }
function stepPhysics(dt) {
  physAcc += dt;
  let n = 0;
  while (physAcc >= PHYS_DT && n < 12) { savePrev(); physicsStep(PHYS_DT); physAcc -= PHYS_DT; n++; }
  if (n === 12) physAcc = 0;
  alpha = physAcc / PHYS_DT;
}
const R = { x: 0, y: 0, z: 0, h: 0 }; // interpolated render pose
function applyCarPose() {
  const a = alpha;
  R.x = lerp(prev.x, car.x, a); R.y = lerp(prev.y, car.y, a); R.z = lerp(prev.z, car.z, a);
  R.h = prev.h + wrapAngle(car.h - prev.h) * a;
  const C = player.car;
  C.position.set(R.x, R.y, R.z);
  C.rotation.set(lerp(prev.pitch, car.pitch, a), R.h, lerp(prev.roll, car.roll, a), 'YXZ');
  const st = lerp(prev.steer, car.steer, a), sp = lerp(prev.spin, car.spin, a);
  player.wheels.forEach((w, i) => {
    w.spin.rotation.x = sp;
    if (w.front) w.pivot.rotation.y = st;
    w.pivot.position.y = player.R + clamp(car.comp[i], -0.12, 0.1);
  });
}
function returnToRoad() {
  const q = roadQuery(car.x, car.z, world.Q());
  const s = q.d !== Infinity ? q.s : car.s;
  const p = roadPoint(s, LANE);
  const spd = Math.min(Math.max(car.v, 0), 14);
  car.x = p.x; car.z = p.z; car.h = p.h; car.y = groundAt(p.x, p.z); car.yv = 0;
  car.vx = Math.sin(p.h) * spd; car.vz = Math.cos(p.h) * spd; car.yawRate = 0; car.steer = 0; car.pitch = 0; car.roll = 0; car.pv = 0; car.rv = 0;
  car.s = s; car.lat = LANE; car.d = LANE; savePrev(); camInit = false; wetTime = 0;
}
// ---------------------------------------------------------------------------
// The living city: signals, two-way traffic, pedestrians, police chases
// ---------------------------------------------------------------------------
const BLOCK = K.BLOCK, CITY_SPEED = 15.6; // 35 mph in town
const SIG_CYCLE = 26;
function signalState(m) { const t = (simT + m * 7.3 + 1000 * SIG_CYCLE) % SIG_CYCLE; return t < 15 ? 'g' : t < 18 ? 'y' : 'r'; }
const isCityAt = (s) => { const i = clamp(Math.floor(s / STEP), 0, road.nFinal - 1); return world.citySide(road.zs[i], 1); };
// distance (along travel direction `dir`) to the next stop line this car must respect, or Infinity
function stopLineGap(s, dir, v) {
  const m = dir > 0 ? Math.ceil((s + 9) / BLOCK) : Math.floor((s - 9) / BLOCK);
  const stopS = m * BLOCK - dir * 8.6, d = (stopS - s) * dir;
  if (d < 0.5 || d > 140 || !isCityAt(m * BLOCK)) return Infinity;
  const st = signalState(m);
  if (st === 'g' || (st === 'y' && d < v * 1.3)) return Infinity;
  return d;
}

// ---- signal lamps (instanced, recoloured every frame)
const lampGeo = new THREE.BoxGeometry(0.26, 0.26, 0.05);
const lamps = new THREE.InstancedMesh(lampGeo, new THREE.MeshBasicMaterial({ color: 0xffffff }), 96);
lamps.instanceMatrix.setUsage(THREE.DynamicDrawUsage); lamps.frustumCulled = false; lamps.count = 0;
scene.add(lamps);
const LAMP_ON = [new THREE.Color(6, 0.4, 0.3), new THREE.Color(6, 3.2, 0.3), new THREE.Color(0.4, 6, 1.4)], LAMP_OFF = new THREE.Color(0.06, 0.06, 0.06);
const _m4 = new THREE.Matrix4(), _q4 = new THREE.Quaternion(), _e4 = new THREE.Euler(), _v4 = new THREE.Vector3(), _s4 = new THREE.Vector3(1, 1, 1);
function updateSignals() {
  let n = 0;
  const m0 = Math.floor(car.s / BLOCK) - 2;
  for (let m = Math.max(1, m0); m < m0 + 7 && n < 90; m++) {
    const sb = m * BLOCK;
    if (sb / STEP >= road.nFinal - 4 || !isCityAt(sb)) continue;
    const st = signalState(m);
    for (const side of [1, -1]) {
      const hd = roadPoint(sb - side * 7.4, side * 1.8), lz = -side * 0.21, cs = Math.cos(hd.h), sn = Math.sin(hd.h);
      [['r', 0.82], ['y', 0.42], ['g', 0.02]].forEach(([k, dy], j) => {
        _v4.set(hd.x + lz * sn, hd.y + 0.17 + 4.7 + dy + 0.12, hd.z + lz * cs);
        _q4.setFromEuler(_e4.set(0, hd.h, 0));
        lamps.setMatrixAt(n, _m4.compose(_v4, _q4, _s4));
        lamps.setColorAt(n, st === k ? LAMP_ON[j] : LAMP_OFF);
        n++;
      });
    }
  }
  lamps.count = n;
  lamps.instanceMatrix.needsUpdate = true;
  if (lamps.instanceColor) lamps.instanceColor.needsUpdate = true;
}

// ---- two-way traffic: follows the car ahead, stops at red lights
function updateTraffic(dt) {
  const city = isCityAt(car.s);
  for (let i = traffic.length - 1; i >= 0; i--) {
    const t = traffic[i], dir = t.lane;
    const rel = t.s - car.s;
    if (rel < -160 || rel > 640 || t.s / STEP >= road.nFinal - 3 || t.s < 4) { t.mesh.visible = false; trafficPool.push(t.mesh); traffic.splice(i, 1); continue; }
    let gap = Infinity, leadV = 0;
    for (const o of traffic) if (o !== t && o.lane === t.lane) { const d = (o.s - t.s) * dir; if (d > 0 && d < gap) { gap = d; leadV = o.v; } }
    if (Math.abs(car.lat - dir * LANE) < 2 && car.d < ROAD_EDGE + 1) { const d = (car.s - t.s) * dir; if (d > 0 && d < gap) { gap = d; leadV = Math.max(0, car.v * dir); } }
    gap = Math.min(gap, stopLineGap(t.s, dir, t.v));
    const limit = isCityAt(t.s) ? Math.min(t.v0, CITY_SPEED) : t.v0;
    const want = Math.min(limit, Math.sqrt(2 * 4 * Math.max(0, gap - 7)), gap < 25 ? leadV + (gap - 9) * 0.4 : Infinity);
    t.v += clamp(want - t.v, -7 * dt, 2.4 * dt);
    t.v = Math.max(0, t.v);
    t.s += t.v * dir * dt;
    const p = roadPoint(t.s, dir * LANE);
    t.mesh.position.set(p.x, p.y + 0.02, p.z); t.mesh.rotation.y = p.h + (dir < 0 ? Math.PI : 0);
    t.x = p.x; t.z = p.z;
    const dx = t.x - car.x, dz = t.z - car.z;
    if (dx * dx + dz * dz < 7 && !t.hit) {
      t.hit = true; const imp = Math.hypot(car.vx, car.vz);
      car.vx *= 0.4; car.vz *= 0.4; t.v *= 0.3; shake = Math.min(1, 0.3 + imp * 0.03); thud(10 + imp); toast('bump');
    }
    if (t.hit && dx * dx + dz * dz > 40) t.hit = false;
  }
  // keep a few cars around in each lane; more in town
  for (const lane of [1, -1]) {
    const want = city ? 5 : 2;
    if (traffic.filter((t) => t.lane === lane).length >= want || !trafficPool.length || trafficRng() > dt * 2) continue;
    const s = lane > 0 ? car.s + (trafficRng() < 0.75 ? 160 + trafficRng() * 300 : -110 - trafficRng() * 40) : car.s + 220 + trafficRng() * 300;
    if (s / STEP >= road.nFinal - 4 || s < 10 || traffic.some((t) => t.lane === lane && Math.abs(t.s - s) < 30)) continue;
    const mesh = trafficPool.pop(); mesh.visible = true;
    const v0 = (city ? 14 : 20) + trafficRng() * 6;
    traffic.push({ s, lane, v: v0, v0, mesh, x: 0, z: 0, hit: false });
  }
}

// ---- pedestrians: instanced people on the sidewalks, crossing at crosswalks on red
const PED_MAX = MOBILE ? 40 : 120;
const pedBody = (() => {
  const legs = new THREE.BoxGeometry(0.3, 0.84, 0.2).translate(0, 0.42, 0);
  const torso = new THREE.CapsuleGeometry(0.2, 0.42, 3, 8).scale(1.1, 1, 0.7).translate(0, 1.14, 0);
  const g = new THREE.BufferGeometry();
  const parts = [legs.toNonIndexed(), torso.toNonIndexed()];
  const pos = [], nrm = [];
  for (const q of parts) { pos.push(...q.attributes.position.array); nrm.push(...q.attributes.normal.array); }
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setAttribute('normal', new THREE.Float32BufferAttribute(nrm, 3));
  return g;
})();
const peds = { body: new THREE.InstancedMesh(pedBody, std({ color: 0xffffff, roughness: 0.85 }), PED_MAX), head: new THREE.InstancedMesh(new THREE.SphereGeometry(0.12, 10, 8).translate(0, 1.62, 0), std({ color: 0xffffff, roughness: 0.7 }), PED_MAX), list: [] };
for (const m of [peds.body, peds.head]) { m.instanceMatrix.setUsage(THREE.DynamicDrawUsage); m.castShadow = true; m.frustumCulled = false; m.count = 0; scene.add(m); }
const CLOTHES = [0xf4f1ec, 0x2b2d33, 0x3a5fa8, 0xd9573f, 0xf2c45a, 0x5a8a4a, 0x8a5a9a, 0xe8a0b4, 0x6ac0c8, 0x9a7a5a].map((h) => new THREE.Color(h));
const SKIN = [0xf2d0b4, 0xd8a888, 0xb07a58, 0x7a4a30, 0x5a3420].map((h) => new THREE.Color(h));
const pedRng = mulberry32(SEED ^ 0x9ed);
function spawnPed(p, near) {
  const side = pedRng() < 0.5 ? -1 : 1;
  let s = car.s + (near ? (pedRng() - 0.4) * 300 : (pedRng() < 0.5 ? 200 : -150) + pedRng() * 60);
  if (world.intersectionDist(s) < 10) s += 12;
  p.s = s; p.side = side; p.lat = side * (ROAD_EDGE + 0.9 + pedRng() * 2.1); p.dir = pedRng() < 0.5 ? -1 : 1;
  p.speed = 1.0 + pedRng() * 0.7; p.phase = pedRng() * 6; p.cross = null; p.dodge = 0; p.alive = isCityAt(s) && world.citySide(roadPoint(s).z, side);
}
function updatePeds(dt) {
  if (!isCityAt(car.s) && !peds.list.some((p) => p.alive)) { peds.body.count = peds.head.count = 0; return; }
  while (peds.list.length < PED_MAX) {
    const p = { body: CLOTHES[(pedRng() * CLOTHES.length) | 0], skin: SKIN[(pedRng() * SKIN.length) | 0], scale: 0.92 + pedRng() * 0.16 };
    spawnPed(p, true); peds.list.push(p);
  }
  let n = 0;
  for (const p of peds.list) {
    if (!p.alive || Math.abs(p.s - car.s) > 260) { spawnPed(p, false); if (!p.alive) continue; }
    if (p.cross) { // crossing the road at a crosswalk
      const goal = p.cross.to, dl = goal - p.lat;
      p.lat += Math.sign(dl) * Math.min(Math.abs(dl), p.speed * 1.2 * dt);
      if (Math.abs(dl) < 0.05) { p.side = -p.side; p.cross = null; }
    } else {
      p.s += p.dir * p.speed * dt;
      const id = world.intersectionDist(p.s);
      if (id < 6.7 && id > 6.2 && signalState(Math.round(p.s / BLOCK)) === 'r' && pedRng() < 0.6) p.cross = { to: -p.side * (ROAD_EDGE + 1.4) };
      else if (id < 5.4) p.dir = -p.dir; // no sidewalk across the side street: turn around
    }
    if (p.dodge > 0) { p.dodge -= dt; p.lat += Math.sign(p.lat || 1) * 3.5 * dt; }
    const pt = roadPoint(p.s, p.lat), dx = pt.x - car.x, dz = pt.z - car.z;
    if (dx * dx + dz * dz < 16 && Math.hypot(car.vx, car.vz) > 3 && p.dodge <= 0) { p.dodge = 0.6; if (p.cross) { p.side = -p.side; p.cross = null; } }
    p.lat = clamp(p.lat, -(ROAD_EDGE + K.SIDEWALK - 0.3), ROAD_EDGE + K.SIDEWALK - 0.3);
    p.phase += dt * p.speed * 6;
    const bob = Math.abs(Math.sin(p.phase)) * 0.05, ground = groundAt(pt.x, pt.z);
    const face = p.cross ? pt.h + (p.cross.to > p.lat ? -Math.PI / 2 : Math.PI / 2) : pt.h + (p.dir > 0 ? 0 : Math.PI);
    _v4.set(pt.x, ground + bob, pt.z); _q4.setFromEuler(_e4.set(Math.sin(p.phase) * 0.04, face, 0)); _s4.setScalar(p.scale);
    _m4.compose(_v4, _q4, _s4);
    peds.body.setMatrixAt(n, _m4); peds.head.setMatrixAt(n, _m4);
    peds.body.setColorAt(n, p.body); peds.head.setColorAt(n, p.skin);
    n++;
  }
  _s4.set(1, 1, 1);
  peds.body.count = peds.head.count = n;
  for (const m of [peds.body, peds.head]) { m.instanceMatrix.needsUpdate = true; if (m.instanceColor) m.instanceColor.needsUpdate = true; }
}

// ---- police chase (K): cruisers pursue, ram and box you in; lose them to escape
const chase = { on: false, cops: [], escape: 0, busted: 0, spawnT: 0, slowmo: 0 };
const copPaint = new THREE.MeshPhysicalMaterial({ color: 0x14161a, metalness: 0.4, roughness: 0.35, clearcoat: 1, clearcoatRoughness: 0.08 });
const copRed = new THREE.MeshBasicMaterial({ color: new THREE.Color(6, 0.3, 0.2) }), copBlue = new THREE.MeshBasicMaterial({ color: new THREE.Color(0.3, 0.8, 7) });
const copPool = Array.from({ length: 4 }, () => {
  const rig = carsLib.buildProcedural(CARS.find((c) => c.id === 'gran'), { lod: true, paint: copPaint });
  rig.car.remove(rig.beam, rig.beam.target);
  const door = new THREE.Mesh(new THREE.BoxGeometry(1.98, 0.36, 1.6), new THREE.MeshStandardMaterial({ color: 0xf4f1ec, roughness: 0.4 })); door.position.set(0, 0.6, 0); rig.car.add(door);
  const r = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.12, 0.22), copRed), b = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.12, 0.22), copBlue);
  r.position.set(0.28, 1.36, -0.15); b.position.set(-0.28, 1.36, -0.15); rig.car.add(r, b);
  rig.car.visible = false; scene.add(rig.car);
  return { mesh: rig.car, red: r, blue: b };
});
const copLights = [new THREE.PointLight(0xff2020, 0, 26, 1.6), new THREE.PointLight(0x2050ff, 0, 26, 1.6)];
copLights.forEach((l) => scene.add(l));
function setChase(on) {
  if (on === chase.on) return;
  chase.on = on; chase.escape = 0; chase.busted = 0; chase.spawnT = 0;
  for (const c of chase.cops) c.rig.mesh.visible = false;
  chase.cops = [];
  if (on) { setAuto(false); spawnCop(); spawnCop(); toast('police chase'); }
  copLights.forEach((l) => (l.intensity = 0));
  $('chase').classList.toggle('hidden', !on);
}
function spawnCop() {
  const rig = copPool.find((r) => !chase.cops.some((c) => c.rig === r));
  if (!rig) return;
  const k = chase.cops.length, p = roadPoint(Math.max(20, car.s - 80 - k * 22), (k % 2 ? -1 : 1) * LANE);
  chase.cops.push({ rig, x: p.x, z: p.z, h: p.h, v: Math.max(18, Math.hypot(car.vx, car.vz)), hit: 0 });
  rig.mesh.visible = true;
}
function collideCircle(o, rad) { // push a moving body (x, z, v, h) out of building footprints
  for (let i = 0; i < nearFoot.length; i += 5) {
    const cs = Math.cos(nearFoot[i + 2]), sn = Math.sin(nearFoot[i + 2]), hx = nearFoot[i + 3], hz = nearFoot[i + 4];
    const dx = o.x - nearFoot[i], dz = o.z - nearFoot[i + 1], lx = dx * cs - dz * sn, lz = dx * sn + dz * cs;
    if (Math.abs(lx) > hx + rad || Math.abs(lz) > hz + rad) continue;
    const qx = clamp(lx, -hx, hx), qz = clamp(lz, -hz, hz), ox = lx - qx, oz = lz - qz, d = Math.hypot(ox, oz);
    if (d >= rad && d > 1e-4) continue;
    const nx = d > 1e-4 ? ox / d : Math.sign(lx) || 1, nz = d > 1e-4 ? oz / d : 0, pen = d > 1e-4 ? rad - d : hx - Math.abs(lx) + rad;
    o.x += (nx * cs + nz * sn) * pen; o.z += (-nx * sn + nz * cs) * pen; o.v *= 0.6;
  }
}
function updateChase(dt) {
  if (!chase.on) return;
  const pv = Math.hypot(car.vx, car.vz);
  chase.spawnT += dt;
  if (chase.spawnT > 25 && chase.cops.length < 4) { chase.spawnT = 0; spawnCop(); }
  let minD = Infinity, nearest = null;
  for (const c of chase.cops) {
    const ahead = Math.min(1.2, Math.hypot(car.x - c.x, car.z - c.z) / 40);
    const tx = car.x + car.vx * 0.5 * ahead, tz = car.z + car.vz * 0.5 * ahead;
    const dx = tx - c.x, dz = tz - c.z, dist = Math.hypot(dx, dz);
    const turn = wrapAngle(Math.atan2(dx, dz) - c.h), yawMax = 1.9 / (1 + c.v / 30);
    c.h += clamp(turn, -yawMax * dt, yawMax * dt);
    const want = dist > 30 ? Math.min(60, pv + 14) : Math.min(60, pv + 4);
    c.v += clamp(want - c.v, -10 * dt, 9 * dt);
    if (Math.abs(turn) > 1.2) c.v = Math.max(8, c.v - 12 * dt);
    c.x += Math.sin(c.h) * c.v * dt; c.z += Math.cos(c.h) * c.v * dt;
    collideCircle(c, 1.2);
    const gx = c.x - car.x, gz = c.z - car.z, gd = Math.hypot(gx, gz);
    if (gd < 3.0) { // contact: shove both apart
      const nx = gx / (gd || 1), nz = gz / (gd || 1), pen = 3.0 - gd;
      c.x += nx * pen * 0.5; c.z += nz * pen * 0.5; car.x -= nx * pen * 0.5; car.z -= nz * pen * 0.5;
      const rel = (car.vx - Math.sin(c.h) * c.v) * nx + (car.vz - Math.cos(c.h) * c.v) * nz;
      if (rel > 0) { car.vx -= nx * rel * 1.2; car.vz -= nz * rel * 1.2; }
      if (c.hit <= 0) { c.hit = 0.6; shake = 0.7; thud(14); }
    }
    c.hit -= dt;
    const y = groundAt(c.x, c.z);
    c.rig.mesh.position.set(c.x, y, c.z); c.rig.mesh.rotation.set(0, c.h, 0);
    const flash = Math.floor(simT * 6) % 2 === 0;
    c.rig.red.material = flash ? copRed : copBlue; c.rig.blue.material = flash ? copBlue : copRed;
    if (gd < minD) { minD = gd; nearest = c; }
  }
  if (nearest) {
    const f = Math.floor(simT * 6) % 2;
    copLights[0].position.set(nearest.x + 0.3, groundAt(nearest.x, nearest.z) + 2, nearest.z); copLights[0].intensity = f ? 30 : 4;
    copLights[1].position.set(nearest.x - 0.3, groundAt(nearest.x, nearest.z) + 2, nearest.z); copLights[1].intensity = f ? 4 : 30;
  }
  chase.minD = minD;
  if (minD > 180) chase.escape += dt; else chase.escape = Math.max(0, chase.escape - dt * 0.5);
  if (pv < 1.5 && minD < 7) chase.busted += dt; else chase.busted = Math.max(0, chase.busted - dt);
  $('chaseBar').style.width = Math.min(100, (chase.escape / 12) * 100) + '%';
  $('chaseMsg').textContent = minD > 180 ? 'Out of sight' : minD > 60 ? 'Pulling away' : 'Close behind';
  if (chase.escape >= 12) { setChase(false); bigMessage('Escaped'); }
  else if (chase.busted >= 3.5) { setChase(false); chase.slowmo = 2.2; bigMessage('Busted'); setTimeout(() => { returnToRoad(); car.vx = car.vz = 0; }, 2000); }
}
let bigTimer = 0;
function bigMessage(text) { const el = $('bigmsg'); el.textContent = text; el.classList.remove('hidden'); clearTimeout(bigTimer); bigTimer = setTimeout(() => el.classList.add('hidden'), 2600); }

// ---------------------------------------------------------------------------
// Time of day, seasons, weather → lighting
// ---------------------------------------------------------------------------
const PRESETS = CA ? [0.29, 0.45, 0.728, 0.752, 0.9] : [0.3, 0.5, 0.7, 0.756, 0.88];
const PRESET_NAMES = ['sunrise', 'midday', 'golden hour', 'sunset', 'night'];
let presetIdx = 2, timeOfDay = PRESETS[presetIdx], timeTarget = timeOfDay, dayCycle = false, night = 0;
const SEASONS = ['spring', 'summer', 'fall', 'winter'];
const WEATHER = CA
  ? [{ cover: 0.32, rain: 0 }, { cover: 0.1, rain: 0 }, { cover: 0.3, rain: 0 }, { cover: 0.62, rain: 1 }]
  : [{ cover: 0.3, rain: 0 }, { cover: 0.52, rain: 1 }, { cover: 0.42, rain: 0.5 }, { cover: 0.14, rain: 0 }];
const seasonFromDate = () => [3, 3, 0, 0, 0, 1, 1, 1, 2, 2, 2, 3][new Date().getMonth()];
let seasonIdx = seasonFromDate(), autoSeasons = false, seasonTimer = 0, weatherOverride = null, headlights = 'auto';
let cover = WEATHER[seasonIdx].cover, rain = 0;
const sunDir = new THREE.Vector3(), tmpV = new THREE.Vector3(), tmpC = new THREE.Color(), tmpC2 = new THREE.Color();
const KEYS = [
  { e: -0.35, zen: 0x040814, hor: 0x161e34, sun: 0x9fb4ff, sunI: 0.35, env: 0.35, exp: 1.05, cl: 0x2a3350, cs: 0x0e1426, water: 0x0a1a28, ridge: 0x0c1220, fog: 0x121a2c },
  { e: -0.08, zen: 0x1c2450, hor: 0xc9788a, sun: 0xff9a7a, sunI: 0.45, env: 0.5, exp: 1.15, cl: 0xe8889a, cs: 0x3a3058, water: 0x2a3050, ridge: 0x3a2f58, fog: 0x7a5a7a },
  { e: 0.03, zen: 0x3a5aa0, hor: 0xffa060, sun: 0xff8a40, sunI: 2.3, env: 0.7, exp: 1.0, cl: 0xffb070, cs: 0x8a5a78, water: 0x2a4a6a, ridge: 0x6a4a6a, fog: 0xe8a07a },
  { e: 0.18, zen: 0x4a7ed0, hor: 0xffd6a8, sun: 0xffd29a, sunI: 3.0, env: 0.9, exp: 0.95, cl: 0xfff0dc, cs: 0xb0a0b8, water: 0x2a5878, ridge: 0x9a8aa0, fog: 0xf0d6b8 },
  { e: 0.55, zen: 0x2f6fd8, hor: 0xc4dcf0, sun: 0xfff6ea, sunI: 3.4, env: 1.0, exp: 0.9, cl: 0xffffff, cs: 0xb8c4d8, water: 0x1f5f80, ridge: 0x8aa0c0, fog: 0xc8dcec },
];
const CF = ['zen', 'hor', 'sun', 'cl', 'cs', 'water', 'ridge', 'fog'];
for (const k of KEYS) for (const f of CF) k[f] = new THREE.Color(k[f]);
const PAL = { sunI: 1, env: 1, exp: 1 };
for (const f of CF) PAL[f] = new THREE.Color();
function samplePalette(e) {
  let a = KEYS[0], b = KEYS[KEYS.length - 1], t = 0;
  if (e <= a.e) b = a; else if (e >= b.e) a = b;
  else for (let i = 0; i < KEYS.length - 1; i++) if (e >= KEYS[i].e && e <= KEYS[i + 1].e) { a = KEYS[i]; b = KEYS[i + 1]; t = (e - a.e) / (b.e - a.e); break; }
  t = smooth(t);
  for (const f of CF) PAL[f].copy(a[f]).lerp(b[f], t);
  for (const f of ['sunI', 'env', 'exp']) PAL[f] = lerp(a[f], b[f], t);
}
const seasonTarget = new THREE.Vector4();
function setSeason(i, announce = true) {
  seasonIdx = ((i % 4) + 4) % 4; settings.season = seasonIdx; saveSettings();
  if (announce) toast(SEASONS[seasonIdx]);
  btn('season').querySelector('.v').textContent = SEASONS[seasonIdx];
}
const ENV_MATS = [...Object.values(MATS), ...Object.values(VM), waterMat].filter((m) => 'envMapIntensity' in m);
function updateSky(dt) {
  const ang = (timeOfDay - 0.25) * Math.PI * 2;
  sunDir.set(-Math.cos(ang) * 0.8 * (CA ? 1 : -1), Math.sin(ang), 0.5).normalize(); // sets over the Pacific; rises over the Atlantic
  const elev = sunDir.y;
  night = sstep(0.03, -0.16, elev);
  samplePalette(elev);
  // seasons & weather
  seasonTarget.set(seasonIdx === 0 ? 1 : 0, seasonIdx === 1 ? 1 : 0, seasonIdx === 2 ? 1 : 0, seasonIdx === 3 ? 1 : 0);
  seasonU.uSeason.value.lerp(seasonTarget, 1 - Math.exp(-dt * 1.2));
  const wx = WEATHER[seasonIdx];
  const shower = (Math.sin(simT / 70) + Math.sin(simT / 37 + 1.3)) > 0.2 ? 1 : 0;
  const rainT = weatherOverride === null ? wx.rain * shower : weatherOverride;
  rain += (rainT - rain) * (1 - Math.exp(-dt * 0.35));
  cover += (Math.min(1, wx.cover + rain * 0.45) - cover) * (1 - Math.exp(-dt * 0.3));
  const Ws = seasonU.uSeason.value;
  seasonU.uWet.value = clamp(rain * 1.4, 0, 1);
  seasonU.uHoliday.value = Ws.w * night * (SF ? 1 : 0.5);
  seasonU.uWind.value = 0.8 + rain * 1.6 + (SF ? Ws.z * 0.8 : 0);
  const gloom = 1 - rain * 0.5;
  skyU.zen.value.copy(PAL.zen).lerp(tmpC.setRGB(0.32, 0.36, 0.42), rain * 0.6 * (1 - night));
  skyU.hor.value.copy(PAL.hor).lerp(tmpC.setRGB(0.5, 0.53, 0.58), rain * 0.55 * (1 - night));
  skyU.sunCol.value.copy(PAL.sun);
  skyU.sunDir.value.copy(sunDir);
  skyU.moonDir.value.set(sunDir.x * -0.6, Math.max(-sunDir.y, 0.3), 0.6).normalize();
  skyU.cloudLit.value.copy(PAL.cl).lerp(tmpC.setRGB(0.55, 0.58, 0.62), rain * 0.6 * (1 - night));
  skyU.cloudShade.value.copy(PAL.cs).lerp(tmpC.setRGB(0.25, 0.27, 0.3), rain * 0.6 * (1 - night));
  skyU.night.value = night; skyU.cover.value = cover; skyU.time.value = simT;
  stars.material.opacity = night * (1 - cover) * 0.95;
  const lightDir = elev > -0.06 ? sunDir : tmpV.copy(skyU.moonDir.value);
  sun.color.copy(PAL.sun); sun.intensity = PAL.sunI * (1 - cover * 0.55) * gloom;
  sun.position.set(R.x + lightDir.x * 300, R.y + Math.max(lightDir.y, 0.12) * 300, R.z + lightDir.z * 300);
  sun.target.position.set(R.x, R.y, R.z);
  hemi.color.copy(PAL.zen); hemi.groundColor.copy(PAL.fog).multiplyScalar(0.4); hemi.intensity = 0.2 + night * 0.35;
  scene.fog.color.copy(PAL.fog).lerp(tmpC.setRGB(0.48, 0.5, 0.54), rain * 0.6 * (1 - night));
  scene.fog.near = 120 * (1 - rain * 0.6); scene.fog.far = (VIEW_M - 10) * (1 - rain * 0.35);
  horizonU.hor.value.copy(scene.fog.color); horizonU.ridge.value.copy(PAL.ridge).lerp(scene.fog.color, rain * 0.5);
  horizonU.night.value = night; horizonU.snow.value = Ws.w;
  waterMat.color.copy(PAL.water); waterMat.normalMap.offset.set(simT * 0.003, simT * 0.002);
  const nightGlow = Math.max(night, rain * 0.4);
  for (const m of FACADES) m.emissiveIntensity = nightGlow * 1.1;
  MATS.glass.emissiveIntensity = nightGlow * 0.22; // shop windows light up
  MATS.neon.color.setScalar(lerp(1.3, 2.6, nightGlow));
  MATS.sign.color.setScalar(lerp(0.8, 1.8, nightGlow));
  MATS.pool.emissiveIntensity = 0.15 + night * 1.2;
  MATS.road.roughness = lerp(0.88, 0.22, seasonU.uWet.value);
  MATS.sidewalk.roughness = lerp(0.9, 0.35, seasonU.uWet.value);
  const headOn = headlights === 'on' || (headlights === 'auto' && nightGlow > 0.25);
  player.beam.intensity = headOn ? 120 : 0;
  VM.head.emissiveIntensity = headOn ? 3 : 0.3;
  VM.tail.emissiveIntensity = brake > 0.05 || input.hand ? 6 : headOn ? 2.2 : 1.0;
  compU.exposure.value = PAL.exp * (1 + rain * 0.15);
  compU.bloom.value = lerp(0.3, 0.55, nightGlow);
  compU.shadowTint.value.copy(PAL.zen).lerp(tmpC.setRGB(0.2, 0.22, 0.35), 0.5).convertLinearToSRGB();
  compU.hiTint.value.setRGB(1, 1, 1).lerp(tmpC2.copy(PAL.sun).convertLinearToSRGB(), 0.35 * (1 - night));
  compU.sat.value = 1.1 - rain * 0.2;
  compU.ink.value.copy(PAL.zen).multiplyScalar(0.25);
  const envI = PAL.env * (1 - rain * 0.25);
  for (const m of ENV_MATS) m.envMapIntensity = envI;
  rainU.uRain.value = rain; rainU.uTime.value = simT; rainU.uCam.value.copy(camera.position); rainU.uWindX.value = 2 + seasonU.uWind.value * 2;
  updateEnv(false);
}

// Street lights near the camera light the road at night
const streetLights = Array.from({ length: 6 }, () => { const l = new THREE.PointLight(0xffc98a, 0, 30, 1.6); scene.add(l); return l; });
function updateStreetLights() {
  if (!streetLights.length) return;
  const cand = [], fx = Math.sin(R.h), fz = Math.cos(R.h);
  for (const s of segments.values()) for (let i = 0; i < s.lights.length; i += 3) {
    const dx = s.lights[i] - R.x, dz = s.lights[i + 2] - R.z, d2 = dx * dx + dz * dz;
    if (d2 < 130 * 130) cand.push([d2 * (dx * fx + dz * fz < -10 ? 4 : 1), i, s.lights]);
  }
  cand.sort((a, b) => a[0] - b[0]);
  const glow = Math.max(night, rain * 0.4);
  streetLights.forEach((l, k) => {
    if (k < cand.length) { const [, i, arr] = cand[k]; l.position.set(arr[i], arr[i + 1], arr[i + 2]); l.intensity = glow * 22; }
    else l.intensity = 0;
  });
}

// ---------------------------------------------------------------------------
// Camera
// ---------------------------------------------------------------------------
const CAM_MODES = ['chase', 'driver', 'cinematic'];
let camMode = 0, camYaw = 0, camInit = false, camFov = 62;
const look = { yaw: 0, pitch: 0, dragging: false, pointer: null, lastX: 0, lastY: 0, idle: 99 };
const cine = { x: 0, y: 0, z: 0, set: false, s: 0 };
const photo = { on: false, yaw: 0, pitch: 0.25, dist: 10, save: false };
const camPos = new THREE.Vector3(), camLook = new THREE.Vector3(), lookPos = new THREE.Vector3();
const ex = (rate, dt) => 1 - Math.exp(-rate * dt);
function updateCamera(dt) {
  if (!look.dragging) { look.idle += dt; if (look.idle > 1.5) { look.yaw *= Math.exp(-dt * 1.5); look.pitch *= Math.exp(-dt * 1.5); } }
  const mode = CAM_MODES[camMode], speed = Math.hypot(car.vx, car.vz);
  if (garageOpen) { photo.yaw += dt * 0.35; photo.pitch = 0.12; photo.dist = 6.4; }
  if (photo.on || garageOpen) {
    const cp = Math.cos(photo.pitch);
    camera.position.set(R.x + Math.sin(photo.yaw) * cp * photo.dist, R.y + 1 + Math.sin(photo.pitch) * photo.dist, R.z + Math.cos(photo.yaw) * cp * photo.dist);
    camera.position.y = Math.max(camera.position.y, groundAt(camera.position.x, camera.position.z) + 0.5);
    camera.lookAt(R.x, R.y + 0.9, R.z);
    camFov = lerp(camFov, 45, ex(4, dt) + 0.02);
  } else if (mode === 'chase') {
    const slip = clamp(car.yawRate * 0.18 - Math.atan2(car.vL, Math.max(speed, 3)) * 0.6, -0.35, 0.35);
    camYaw += wrapAngle(R.h - slip - camYaw) * ex(3.6, dt);
    const yaw = camYaw + look.yaw;
    const dist = 7.0 + speed * 0.045, up = 2.25 + look.pitch * 6;
    const tx = R.x - Math.sin(yaw) * dist, tz = R.z - Math.cos(yaw) * dist;
    const target = tmpV.set(tx, Math.max(R.y + up, groundAt(tx, tz) + 0.8), tz);
    if (!camInit) { camPos.copy(target); lookPos.set(R.x, R.y + 1.2, R.z); camYaw = R.h; camInit = true; }
    camPos.lerp(target, ex(9, dt));
    lookPos.lerp(camLook.set(R.x + Math.sin(yaw) * 6, R.y + 1.25, R.z + Math.cos(yaw) * 6), ex(14, dt));
    camera.position.copy(camPos);
    camera.lookAt(lookPos);
    camFov = lerp(camFov, 60 + speed * 0.28, ex(2, dt));
  } else if (mode === 'driver') {
    const C = player.car;
    C.updateMatrixWorld();
    camera.position.set(0.38, player.camH, -0.3).applyMatrix4(C.matrixWorld);
    camera.lookAt(camLook.set(0.38 + Math.sin(look.yaw) * 10, player.camH - 0.15 + look.pitch * 10, 10).applyMatrix4(C.matrixWorld));
    camFov = lerp(camFov, 72, ex(3, dt));
  } else {
    if (!cine.set || car.s > cine.s + 45 || Math.hypot(R.x - cine.x, R.z - cine.z) > 260) {
      const s = car.s + 110 + Math.random() * 90;
      if (s / STEP < road.nFinal - 2) {
        const side = Math.random() < 0.5 ? -1 : 1, lat = world.citySide(roadPoint(s).z, side) ? 4.3 : 10 + Math.random() * 18;
        const p = roadPoint(s, side * lat);
        cine.x = p.x; cine.z = p.z; cine.y = Math.max(groundAt(p.x, p.z), WATER) + 1.1 + Math.random() * (lat < 5 ? 1.6 : 5); cine.s = s; cine.set = true;
      }
    }
    camera.position.set(cine.x, cine.y, cine.z);
    camera.lookAt(camLook.set(R.x, R.y + 0.9, R.z));
    camFov = lerp(camFov, clamp(900 / Math.max(camera.position.distanceTo(camLook), 1), 18, 60), ex(3, dt));
  }
  if (shake > 0) { camera.position.x += (Math.random() - 0.5) * shake * 0.25; camera.position.y += (Math.random() - 0.5) * shake * 0.25; shake = Math.max(0, shake - dt * 1.8); }
  camera.fov = camFov;
  camera.updateProjectionMatrix();
  sky.position.copy(camera.position); stars.position.copy(camera.position);
  horizon.position.set(camera.position.x, 0, camera.position.z);
  water.position.x = Math.round(camera.position.x / 50) * 50; water.position.z = Math.round(camera.position.z / 50) * 50;
}

// ---------------------------------------------------------------------------
// Audio: engine, wind, rain, horn and the car radio
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
    this.filt = ctx.createBiquadFilter(); this.filt.type = 'lowpass'; this.filt.Q.value = 0.8;
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
    this.wf = ctx.createBiquadFilter(); this.wf.type = 'bandpass'; this.wf.Q.value = 0.4;
    this.wind = ctx.createGain(); this.wind.gain.value = 0;
    src.connect(this.wf); this.wf.connect(this.wind); this.wind.connect(this.master); src.start();
    const wbuf = ctx.createBuffer(1, len, ctx.sampleRate), wd = wbuf.getChannelData(0);
    for (let i = 0; i < len; i++) wd[i] = Math.random() * 2 - 1;
    const rs = ctx.createBufferSource(); rs.buffer = wbuf; rs.loop = true;
    const rf = ctx.createBiquadFilter(); rf.type = 'highpass'; rf.frequency.value = 1800;
    this.rainG = ctx.createGain(); this.rainG.gain.value = 0;
    rs.connect(rf); rf.connect(this.rainG); this.rainG.connect(this.master); rs.start();
    radio.init(ctx, this.master);
  },
  update(v, thr, offroad) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime, av = Math.abs(v), tops = [8, 15, 23, 32, 42, 60].map((x) => x * carSpec.vmax / 60);
    if (this.o1.type !== carSpec.sound[2]) this.o1.type = carSpec.sound[2];
    let g = 0; while (g < tops.length - 1 && av > tops[g]) g++;
    const lo = g ? tops[g - 1] * 0.6 : 0, rpm = clamp((av - lo) / (tops[g] - lo), 0, 1);
    const f = carSpec.sound[0] + rpm * carSpec.sound[1] + thr * 6;
    this.o1.frequency.setTargetAtTime(f, t, 0.08); this.o2.frequency.setTargetAtTime(f * 0.5, t, 0.08);
    this.filt.frequency.setTargetAtTime(220 + rpm * 400 + thr * 320, t, 0.1);
    this.eng.gain.setTargetAtTime((0.03 + thr * 0.035) * (radio.on ? 0.7 : 1), t, 0.15);
    this.wind.gain.setTargetAtTime(Math.min(0.55, (av / 45) ** 2 * (CA ? 0.55 : 0.32)) + (offroad ? Math.min(0.35, av / 40) : 0), t, 0.2);
    this.wf.frequency.setTargetAtTime(offroad ? 160 : 380 + av * 12, t, 0.2);
    this.rainG.gain.setTargetAtTime(rain * 0.08, t, 0.5);
  },
  horn() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    for (const f of [392, 494]) {
      const o = this.ctx.createOscillator(), g = this.ctx.createGain(), lp = this.ctx.createBiquadFilter();
      o.type = 'square'; o.frequency.value = f; lp.type = 'lowpass'; lp.frequency.value = 1600;
      g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(0.08, t + 0.02); g.gain.setTargetAtTime(0, t + 0.45, 0.04);
      o.connect(lp); lp.connect(g); g.connect(this.master); o.start(t); o.stop(t + 0.7);
    }
  },
  setOn(on) { this.on = on; if (this.ctx) this.master.gain.setTargetAtTime(on ? 0.6 : 0, this.ctx.currentTime, 0.1); },
};
function thud(v) {
  if (!audio.ctx) return;
  const ctx = audio.ctx, t = ctx.currentTime, o = ctx.createOscillator(), g = ctx.createGain();
  o.frequency.setValueAtTime(90, t); o.frequency.exponentialRampToValueAtTime(40, t + 0.15);
  g.gain.setValueAtTime(Math.min(0.5, v * 0.04), t); g.gain.exponentialRampToValueAtTime(0.001, t + 0.25);
  o.connect(g); g.connect(audio.master); o.start(t); o.stop(t + 0.3);
}
const STATION = CA ? {
  name: '101.9 Coastline FM', bpm: 74, swing: 0.16, style: 'lofi',
  chords: [[53, 57, 60, 64, 67], [52, 55, 59, 62, 66], [50, 53, 57, 60, 64], [48, 52, 55, 59, 62]], bass: [41, 40, 38, 36], prog: [0, 1, 2, 3], scale: [72, 74, 76, 79, 81, 84, 86],
} : {
  name: '104.3 Neon Coast', bpm: 104, swing: 0.08, style: 'neon',
  chords: [[57, 60, 64, 67, 71], [53, 57, 60, 64], [50, 53, 57, 60, 64], [52, 56, 59, 62]], bass: [45, 41, 38, 40], prog: [0, 1, 2, 3], scale: [69, 72, 74, 76, 79, 81, 84],
};
const radio = {
  on: true, ctx: null, step: 0, bar: 0, next: 0, prevNote: 3,
  init(ctx, dest) {
    this.ctx = ctx;
    this.out = ctx.createGain(); this.out.gain.value = this.on ? 0.5 : 0;
    const hp = ctx.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 70;
    const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = CA ? 3200 : 5200;
    this.out.connect(hp); hp.connect(lp); lp.connect(dest);
    this.pad = ctx.createBiquadFilter(); this.pad.type = 'lowpass'; this.pad.frequency.value = CA ? 1100 : 1600; this.pad.connect(this.out);
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
      this.next += six; this.step = (this.step + 1) % 16; if (this.step === 0) this.bar++;
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
  tone(freq, t, vol, decay, type = 'sine') {
    const o = this.ctx.createOscillator(), g = this.ctx.createGain();
    o.type = type; o.frequency.value = freq;
    g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.001, t + decay);
    o.connect(g); g.connect(this.out); o.start(t); o.stop(t + decay + 0.05);
  },
  play(step, t, six) {
    const S = STATION, ci = S.prog[this.bar % S.prog.length], chord = S.chords[ci], root = S.bass[ci], r = Math.random();
    if (S.style === 'lofi') {
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
    } else { // synth pads, a tumbao bass line, clave and congas
      if (step === 0) for (const n of chord) { this.voice('sawtooth', mtof(n), t, six * 15, 0.012, 0.4, 0.9, this.pad, -9); this.voice('sawtooth', mtof(n), t, six * 15, 0.012, 0.4, 0.9, this.pad, 9); }
      if ([3, 6, 11, 14].includes(step)) {
        const n = root + (step === 14 ? 7 : 0);
        this.voice('triangle', mtof(n), t, six * 2, 0.2, 0.005, 0.15); this.voice('sine', mtof(n - 12), t, six * 2, 0.12, 0.005, 0.15);
      }
      if (step === 0 || step === 8) this.kick(t, 0.45);
      if ((this.bar % 2 === 0 ? [0, 6, 12] : [4, 8]).includes(step)) this.tone(2600, t, 0.07, 0.05, 'triangle');
      if (step === 7 || step === 14 || step === 15) this.tone(step === 15 ? 330 : 240, t, 0.12, 0.18);
      if (step % 2 === 1) this.noiseHit(t, 0.025, 'highpass', 8000, 0.03);
      if (step === 4 || step === 12) this.noiseHit(t, 0.1, 'bandpass', 1800, 0.12);
      if (r < 0.5) this.voice('square', mtof(chord[(step * 3) % chord.length] + 12), t, six * 0.6, 0.012, 0.003, 0.12);
    }
  },
};

// ---------------------------------------------------------------------------
// Route map
// ---------------------------------------------------------------------------
const mapCv = document.getElementById('map'), mapCtx = mapCv.getContext('2d');
const MAP_THEME = CA ? { bg: '#f3e2c4', sea: '#5a86c8', ink: '#2a1830', behind: 'rgba(42,24,48,.35)', car: '#ff6b57', grid: 'rgba(42,24,48,.12)' }
  : { bg: '#ece6dc', sea: '#3fa7c8', ink: '#1b1d2a', behind: 'rgba(27,29,42,.35)', car: '#ff3d9a', grid: 'rgba(27,29,42,.12)' };
let mapTimer = 0;
function drawMap() {
  const dpr = Math.min(devicePixelRatio || 1, 2), S = mapCv.clientWidth || 168;
  if (mapCv.width !== Math.round(S * dpr)) mapCv.width = mapCv.height = Math.round(S * dpr);
  const g = mapCtx, Rm = S / 2, scale = (Rm - 8) / 520;
  g.setTransform(dpr, 0, 0, dpr, 0, 0); g.clearRect(0, 0, S, S);
  g.save(); g.beginPath(); g.arc(Rm, Rm, Rm - 2, 0, Math.PI * 2); g.clip();
  g.fillStyle = MAP_THEME.bg; g.fillRect(0, 0, S, S);
  const fx = Math.sin(R.h), fz = Math.cos(R.h), rx = -Math.cos(R.h), rz = Math.sin(R.h);
  const P = (x, z) => { const dx = x - R.x, dz = z - R.z; return [Rm + (dx * rx + dz * rz) * scale, Rm - (dx * fx + dz * fz) * scale]; };
  const ci = clamp(Math.floor(car.s / STEP), 0, road.nFinal - 1), i0 = Math.max(0, ci - 300), i1 = Math.min(road.nFinal - 1, ci + 320);
  if (world.citySide(R.z, 1)) {
    g.strokeStyle = MAP_THEME.grid; g.lineWidth = 1;
    const x0 = Math.floor((R.x - 560) / CHUNK) * CHUNK, z0 = Math.floor((R.z - 560) / CHUNK) * CHUNK;
    for (let x = x0; x < R.x + 560; x += CHUNK) { const [a, b] = P(x, R.z - 560), [c, d] = P(x, R.z + 560); g.beginPath(); g.moveTo(a, b); g.lineTo(c, d); g.stroke(); }
    for (let z = z0; z < R.z + 560; z += CHUNK) { const [a, b] = P(R.x - 560, z), [c, d] = P(R.x + 560, z); g.beginPath(); g.moveTo(a, b); g.lineTo(c, d); g.stroke(); }
  }
  g.fillStyle = MAP_THEME.sea; g.beginPath();
  for (let i = i0; i <= i1; i += 6) { const [x, y] = P(road.xs[i] + world.coastDist(road.zs[i]) * world.OCEAN_SIDE, road.zs[i]); i === i0 ? g.moveTo(x, y) : g.lineTo(x, y); }
  { const [a, b] = P(road.xs[i1] + 3000 * world.OCEAN_SIDE, road.zs[i1]), [c, d] = P(road.xs[i0] + 3000 * world.OCEAN_SIDE, road.zs[i0]); g.lineTo(a, b); g.lineTo(c, d); }
  g.closePath(); g.fill();
  if (SF) for (let a = -10; a <= 10; a++) for (let b = -10; b <= 10; b++) {
    const wx = Math.round(R.x / 50) * 50 + a * 50, wz = Math.round(R.z / 50) * 50 + b * 50;
    if (world.causewayK(wz) > 0.4 && world.baseH(wx, wz) < 0) { const [x, y] = P(wx, wz); g.beginPath(); g.arc(x, y, 50 * scale * 0.78, 0, Math.PI * 2); g.fill(); }
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
  g.beginPath(); g.moveTo(Rm, Rm - 9); g.lineTo(Rm + 6, Rm + 6); g.lineTo(Rm, Rm + 3); g.lineTo(Rm - 6, Rm + 6); g.closePath(); g.fill(); g.stroke();
  g.strokeStyle = MAP_THEME.ink; g.lineWidth = 2; g.beginPath(); g.arc(Rm, Rm, Rm - 2, 0, Math.PI * 2); g.stroke();
  const lx = Rm + Math.sin(R.h) * (Rm - 14), ly = Rm - Math.cos(R.h) * (Rm - 14);
  g.fillStyle = MAP_THEME.ink; g.beginPath(); g.arc(lx, ly, 9, 0, 7); g.fill();
  g.fillStyle = MAP_THEME.bg; g.font = '600 10px "JetBrains Mono", ui-monospace, monospace'; g.textAlign = 'center'; g.textBaseline = 'middle';
  g.fillText('N', lx, ly + 0.5);
}

// ---------------------------------------------------------------------------
// UI, settings, input
// ---------------------------------------------------------------------------
const $ = (id) => document.getElementById(id);
const ui = { hud: $('hud'), buttons: $('buttons'), help: $('help'), title: $('title'), spd: $('spd'), dist: $('dist'), mode: $('mode'), paused: $('paused'),
  station: $('station'), region: $('regionName'), toast: $('toast'), coords: $('coords'), clock: $('clock'), seasonName: $('seasonName'), photobar: $('photobar'), mapWrap: $('mapwrap'), menuBtn: $('menuBtn'), place: $('place'), touchpad: $('touchpad') };
const LS_KEY = 'twolanes.settings.v3';
const settings = { look: 0, radio: true, sound: true, map: true, cam: 0, season: null, autoSeasons: false, car: 'rosso', paint: null };
try { Object.assign(settings, JSON.parse(localStorage.getItem(LS_KEY) || '{}')); } catch (e) { /* storage unavailable */ }
function saveSettings() { try { localStorage.setItem(LS_KEY, JSON.stringify(settings)); } catch (e) { /* ignore */ } }
let started = false, paused = false, uiHidden = false, ready = false, simT = 0;
let TOUCH = matchMedia('(pointer: coarse)').matches || 'ontouchstart' in window;
document.body.classList.toggle('touch', TOUCH);
const btn = (a) => ui.buttons.querySelector(`[data-act="${a}"]`);
document.body.classList.add('region-' + REGION_ID);
ui.region.textContent = CA ? 'California' : 'South Florida';
ui.station.textContent = STATION.name;
$('seedLabel').textContent = 'SEED ' + String(SEED).padStart(9, '0');
for (const b of document.querySelectorAll('.region')) b.classList.toggle('current', b.dataset.region === REGION_ID);
let toastTimer = 0;
function toast(msg) { ui.toast.textContent = msg; ui.toast.classList.remove('hidden'); clearTimeout(toastTimer); toastTimer = setTimeout(() => ui.toast.classList.add('hidden'), 1500); }
function setAuto(on) { autoDrive = on; btn('auto').classList.toggle('on', on); $('autoBtn').classList.toggle('on', on); }
function setCam(i) { camMode = ((i % CAM_MODES.length) + CAM_MODES.length) % CAM_MODES.length; cine.set = false; settings.cam = camMode; saveSettings(); btn('cam').querySelector('.v').textContent = CAM_MODES[camMode]; }
function setLook(i) { settings.look = ((i % LOOKS.length) + LOOKS.length) % LOOKS.length; saveSettings(); compU.look.value = settings.look; btn('look').querySelector('.v').textContent = LOOKS[settings.look]; }
function nextTime() { presetIdx = (presetIdx + 1) % PRESETS.length; timeTarget = PRESETS[presetIdx]; dayCycle = false; toast(PRESET_NAMES[presetIdx]); btn('time').querySelector('.v').textContent = PRESET_NAMES[presetIdx]; }
function setSound(on) { settings.sound = on; saveSettings(); audio.setOn(on); btn('sound').classList.toggle('on', on); }
function setRadio(on) { settings.radio = on; saveSettings(); radio.setOn(on); btn('radio').classList.toggle('on', on); if (on) flashStation(); }
let stationTimer = 0;
function flashStation() { ui.station.classList.add('show'); clearTimeout(stationTimer); stationTimer = setTimeout(() => ui.station.classList.remove('show'), 5000); }
function setMap(on) { settings.map = on; saveSettings(); btn('map').classList.toggle('on', on); applyChrome(); }
function setAutoSeasons(on) { autoSeasons = on; settings.autoSeasons = on; saveSettings(); seasonTimer = 0; toast(on ? 'seasons cycle on' : 'seasons cycle off'); }
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
const gotoRegion = (id) => navigate(id, 0);
const newRoad = () => navigate(REGION_ID, ((Math.random() * 1e9) | 0) >>> 0);
function toggleHelp() { ui.help.classList.toggle('hidden'); btn('help').classList.toggle('on', !ui.help.classList.contains('hidden')); }
function applyChrome() {
  const hide = uiHidden || photo.on || garageOpen || !started;
  ui.hud.classList.toggle('hidden', hide); ui.buttons.classList.toggle('hidden', hide || !menuOpen); ui.menuBtn.classList.toggle('hidden', hide || menuOpen);
  ui.mapWrap.classList.toggle('hidden', hide || !settings.map); ui.photobar.classList.toggle('hidden', !photo.on);
  ui.touchpad.classList.toggle('hidden', hide || !TOUCH || menuOpen);
  if (hide) ui.help.classList.add('hidden');
}
function toggleUI() { uiHidden = !uiHidden; applyChrome(); }
function togglePause() { if (photo.on) return; paused = !paused; ui.paused.classList.toggle('hidden', !paused); }
let menuOpen = false;
function setMenu(on) {
  menuOpen = on; paused = on; ui.paused.classList.toggle('hidden', !on);
  if (!on) ui.help.classList.add('hidden');
  applyChrome();
}
function setPhoto(on) { photo.on = on; if (on) { photo.yaw = R.h + Math.PI + 0.7; photo.pitch = 0.18; photo.dist = 9; } applyChrome(); }
// ---- the garage: pick a car and paint while the car turns slowly in the world
let garageOpen = false;
function setGarage(on) {
  garageOpen = on;
  $('garage').classList.toggle('hidden', !on);
  if (on) { photo.yaw = R.h + Math.PI * 0.8; showCarInfo(); }
  applyChrome();
}
function showCarInfo() {
  const c = carSpec;
  $('gName').textContent = c.name; $('gClass').textContent = c.klass;
  const top = Math.round(c.vmax * 2.237), zero = (26.8 / c.acc).toFixed(1), g = (c.grip / 9.81).toFixed(2);
  $('gTop').textContent = top + ' mph'; $('gAcc').textContent = zero + ' s'; $('gGrip').textContent = g + ' g';
  $('gTopBar').style.width = Math.min(100, (top / 185) * 100) + '%';
  $('gAccBar').style.width = Math.min(100, (c.acc / 13) * 100) + '%';
  $('gGripBar').style.width = Math.min(100, (c.grip / 13.5) * 100) + '%';
  $('gCredit').textContent = c.credit || 'Original design';
  for (const b of $('gList').children) b.classList.toggle('on', b.dataset.id === c.id);
  for (const b of $('gPaint').children) b.classList.toggle('on', +b.dataset.hex === VM.paint.color.getHex());
}
function buildGarage() {
  const list = $('gList'), sw = $('gPaint');
  CARS.forEach((c, i) => {
    const b = document.createElement('button'); b.dataset.id = c.id;
    b.innerHTML = `<span class="n">${String(i + 1).padStart(2, '0')}</span><b>${c.name}</b><span class="k">${c.klass}</span>`;
    b.addEventListener('click', (e) => { e.stopPropagation(); settings.car = c.id; settings.paint = null; saveSettings(); chooseCar(c.id).then(showCarInfo); showCarInfo(); });
    list.appendChild(b);
  });
  for (const hex of PAINT_SWATCHES) {
    const b = document.createElement('button'); b.dataset.hex = hex; b.style.setProperty('--c', '#' + hex.toString(16).padStart(6, '0'));
    b.addEventListener('click', (e) => { e.stopPropagation(); VM.paint.color.setHex(hex); settings.paint = hex; saveSettings(); showCarInfo(); });
    sw.appendChild(b);
  }
  $('gDrive').addEventListener('click', (e) => { e.stopPropagation(); setGarage(false); });
  $('garage').addEventListener('pointerdown', (e) => e.stopPropagation());
}
function cycleHeadlights() { headlights = headlights === 'auto' ? 'on' : headlights === 'on' ? 'off' : 'auto'; toast('headlights · ' + headlights); }

ui.buttons.addEventListener('click', (e) => {
  const a = e.target.closest('button')?.dataset.act;
  if (!a) return;
  e.stopPropagation();
  ({ chase: () => { setMenu(false); setChase(!chase.on); }, resume: () => setMenu(false), auto: () => setAuto(!autoDrive), cam: () => setCam(camMode + 1), time: nextTime, look: () => setLook(settings.look + 1), season: () => setSeason(seasonIdx + 1),
     photo: () => { setMenu(false); setPhoto(true); }, radio: () => setRadio(!radio.on), sound: () => setSound(!audio.on), map: () => setMap(!settings.map),
     reset: () => { setMenu(false); returnToRoad(); toast('back on the road'); }, garage: () => { setMenu(false); setGarage(true); }, region: () => gotoRegion(CA ? 'sf' : 'ca'), new: newRoad, help: toggleHelp })[a]();
  e.target.blur();
});
ui.buttons.addEventListener('pointerdown', (e) => e.stopPropagation());
ui.menuBtn.addEventListener('click', (e) => { e.stopPropagation(); setMenu(true); });
ui.menuBtn.addEventListener('pointerdown', (e) => e.stopPropagation());
ui.photobar.addEventListener('pointerdown', (e) => e.stopPropagation());
ui.photobar.addEventListener('click', (e) => {
  const a = e.target.closest('button')?.dataset.act;
  if (a === 'shoot') photo.save = true; else if (a === 'exit') setPhoto(false); else if (a === 'look') setLook(settings.look + 1); else if (a === 'time') nextTime(); else if (a === 'season') setSeason(seasonIdx + 1);
});
setAuto(true); setLook(settings.look); setCam(settings.cam);
if (settings.season !== null && settings.season !== undefined) seasonIdx = settings.season;
autoSeasons = !!settings.autoSeasons;
btn('season').querySelector('.v').textContent = SEASONS[seasonIdx];
btn('time').querySelector('.v').textContent = PRESET_NAMES[presetIdx];
seasonU.uSeason.value.set(seasonIdx === 0 ? 1 : 0, seasonIdx === 1 ? 1 : 0, seasonIdx === 2 ? 1 : 0, seasonIdx === 3 ? 1 : 0);
cover = WEATHER[seasonIdx].cover;
btn('sound').classList.toggle('on', settings.sound); btn('radio').classList.toggle('on', settings.radio); btn('map').classList.toggle('on', settings.map);
audio.on = settings.sound; radio.on = settings.radio; ui.station.classList.toggle('off', !settings.radio);

function wakeAudio() { audio.init(); if (audio.ctx && audio.ctx.state === 'suspended') audio.ctx.resume(); }
function start() { if (started || !ready) return; started = true; ui.title.classList.add('hidden'); clearInterval(postcardTimer); applyChrome(); wakeAudio(); if (radio.on) flashStation(); }
for (const b of document.querySelectorAll('.region')) b.addEventListener('click', (e) => { e.stopPropagation(); if (b.dataset.region === REGION_ID) start(); else gotoRegion(b.dataset.region); });
ui.title.addEventListener('click', start);
addEventListener('pointerdown', wakeAudio);

const KEYMAP = { ArrowUp: 'up', KeyW: 'up', ArrowDown: 'down', KeyS: 'down', ArrowLeft: 'left', KeyA: 'left', ArrowRight: 'right', KeyD: 'right', Space: 'hand' };
addEventListener('keydown', (e) => {
  wakeAudio();
  if (!started) { if (e.code === 'Digit1') gotoRegion('ca'); else if (e.code === 'Digit2') gotoRegion('sf'); else start(); return; }
  const k = KEYMAP[e.code];
  if (k && !photo.on) { input[k] = true; e.preventDefault(); if (k === 'hand' && autoDrive) setAuto(false); return; }
  if (e.repeat) return;
  if (garageOpen) { if (e.code === 'KeyV' || e.code === 'Escape' || e.code === 'Enter') setGarage(false); return; }
  if (menuOpen && e.code !== 'Escape' && e.code !== 'KeyH') return;
  if (photo.on) {
    if (e.code === 'Enter' || e.code === 'Space') { photo.save = true; e.preventDefault(); }
    else if (e.code === 'KeyF' || e.code === 'Escape') setPhoto(false);
    else if (e.code === 'KeyX') setLook(settings.look + 1);
    else if (e.code === 'KeyT') nextTime();
    else if (e.code === 'KeyZ') setSeason(seasonIdx + 1);
    return;
  }
  switch (e.code) {
    case 'KeyR': returnToRoad(); toast('back on the road'); break;
    case 'KeyE': setAuto(!autoDrive); break;
    case 'KeyC': setCam(camMode + 1); toast('camera · ' + CAM_MODES[camMode]); break;
    case 'KeyT': nextTime(); break;
    case 'KeyY': dayCycle = !dayCycle; toast(dayCycle ? 'day cycle on' : 'day cycle off'); break;
    case 'KeyZ': if (e.shiftKey) setAutoSeasons(!autoSeasons); else setSeason(seasonIdx + 1); break;
    case 'KeyX': setLook(settings.look + 1); toast('look · ' + LOOKS[settings.look]); break;
    case 'KeyF': setPhoto(true); break;
    case 'KeyQ': setRadio(!radio.on); toast(radio.on ? STATION.name : 'radio off'); break;
    case 'KeyV': if (e.shiftKey) { setSound(!audio.on); toast(audio.on ? 'sound on' : 'muted'); } else setGarage(!garageOpen); break;
    case 'KeyM': setMap(!settings.map); break;
    case 'KeyL': cycleHeadlights(); break;
    case 'KeyK': setChase(!chase.on); break;
    case 'KeyJ': audio.horn(); break;
    case 'KeyH': toggleHelp(); break;
    case 'KeyU': toggleUI(); break;
    case 'KeyN': newRoad(); break;
    case 'KeyG': gotoRegion(CA ? 'sf' : 'ca'); break;
    case 'KeyP': togglePause(); break;
    case 'Escape': setMenu(!menuOpen); break;
  }
});
addEventListener('keyup', (e) => { const k = KEYMAP[e.code]; if (k) input[k] = false; });
addEventListener('blur', () => { for (const k in input) input[k] = false; });
canvas.addEventListener('pointerdown', (e) => {
  if (!started) { start(); return; }
  if (e.pointerType === 'touch' && !TOUCH) { TOUCH = true; document.body.classList.add('touch'); applyChrome(); }
  look.dragging = true; look.pointer = e.pointerId; look.lastX = e.clientX; look.lastY = e.clientY;
  try { canvas.setPointerCapture(e.pointerId); } catch (err) { /* synthetic */ }
});
canvas.addEventListener('pointermove', (e) => {
  if (!look.dragging || e.pointerId !== look.pointer) return;
  const dx = e.clientX - look.lastX, dy = e.clientY - look.lastY;
  if (photo.on) { photo.yaw -= dx * 0.008; photo.pitch = clamp(photo.pitch + dy * 0.005, -0.05, 1.3); }
  else { look.yaw = clamp(look.yaw - dx * 0.006, -Math.PI, Math.PI); look.pitch = clamp(look.pitch + dy * 0.004, -0.3, 0.8); }
  look.lastX = e.clientX; look.lastY = e.clientY; look.idle = 0;
});
const endPointer = (e) => { if (e.pointerId === look.pointer) { look.dragging = false; look.idle = 0; } };
canvas.addEventListener('pointerup', endPointer); canvas.addEventListener('pointercancel', endPointer);
canvas.addEventListener('wheel', (e) => { if (photo.on) { photo.dist = clamp(photo.dist * (1 + e.deltaY * 0.001), 4, 60); e.preventDefault(); } }, { passive: false });

// ---- touch controls: an analog steering pad and pedal buttons, each tracking its own finger
{
  const pad = $('steerZone'), knob = $('steerKnob'), RANGE = 70;
  let sid = null, sx = 0;
  const setKnob = (dx) => { knob.style.transform = `translateX(${dx}px)`; };
  pad.addEventListener('pointerdown', (e) => {
    e.preventDefault(); e.stopPropagation();
    if (sid !== null) return;
    sid = e.pointerId; sx = e.clientX;
    try { pad.setPointerCapture(e.pointerId); } catch (err) { /* synthetic */ }
    pad.classList.add('active');
  });
  pad.addEventListener('pointermove', (e) => {
    if (e.pointerId !== sid) return;
    const dx = clamp(e.clientX - sx, -RANGE, RANGE);
    const a = dx / RANGE;
    input.axis = -Math.sign(a) * Math.pow(Math.abs(a), 1.4); // finer control near the centre
    setKnob(dx);
  });
  const endSteer = (e) => { if (e.pointerId !== sid) return; sid = null; input.axis = 0; setKnob(0); pad.classList.remove('active'); };
  pad.addEventListener('pointerup', endSteer); pad.addEventListener('pointercancel', endSteer);
  const hold = (id, key) => {
    const el = $(id), ids = new Set();
    const on = (e) => { e.preventDefault(); e.stopPropagation(); ids.add(e.pointerId); try { el.setPointerCapture(e.pointerId); } catch (err) { /* synthetic */ } input[key] = true; el.classList.add('active'); if ((key === 'hand' || key === 'down') && autoDrive) setAuto(false); };
    const off = (e) => { ids.delete(e.pointerId); if (!ids.size) { input[key] = false; el.classList.remove('active'); } };
    el.addEventListener('pointerdown', on); el.addEventListener('pointerup', off); el.addEventListener('pointercancel', off);
  };
  hold('gasBtn', 'up'); hold('brakeBtn', 'down'); hold('handBtn', 'hand');
  const tap = (id, fn) => $(id).addEventListener('pointerdown', (e) => { e.preventDefault(); e.stopPropagation(); fn(); });
  tap('autoBtn', () => setAuto(!autoDrive));
  tap('resetBtn', () => { returnToRoad(); toast('back on the road'); });
  tap('chaseBtn', () => setChase(!chase.on));
  $('touchpad').addEventListener('contextmenu', (e) => e.preventDefault());
}
addEventListener('resize', resize);

let lastPlace = '', placeTimer = 0;
const BASE_LL = CA ? [34.0195, -118.4912] : [25.7907, -80.13];
const PLACE = CA ? { downtown: 'Downtown LA', beach: 'LA beach cities', resid: 'Los Angeles', coast: 'Pacific coast' }
  : { downtown: 'Downtown', deco: 'Art deco strip', resid: 'South Florida', causeway: 'Causeway' };
const fmtCoord = (v, pos, neg) => Math.abs(v).toFixed(4) + '°' + (v >= 0 ? pos : neg);
function updateHud() {
  ui.spd.textContent = String(Math.round(Math.hypot(car.vx, car.vz) * 2.23694));
  ui.dist.textContent = (car.odo / 1609.34).toFixed(1) + ' mi';
  ui.mode.textContent = autoDrive ? 'Auto ' + Math.round(cruise * 2.23694) : input.hand ? 'Handbrake' : 'Manual';
  const lat = BASE_LL[0] + car.z / 111320, lon = BASE_LL[1] - car.x / (111320 * Math.cos(lat * Math.PI / 180));
  ui.coords.textContent = fmtCoord(lat, 'N', 'S') + '  ' + fmtCoord(lon, 'E', 'W');
  const mins = Math.floor(timeOfDay * 24 * 60);
  ui.clock.textContent = String(Math.floor(mins / 60)).padStart(2, '0') + ':' + String(mins % 60).padStart(2, '0');
  ui.seasonName.textContent = SEASONS[seasonIdx] + (rain > 0.3 ? ' · rain' : '');
  const place = PLACE[world.districtAt(car.z)] || (CA ? 'California' : 'South Florida');
  if (place !== lastPlace) { lastPlace = place; ui.region.textContent = place; ui.place.classList.remove('hidden'); clearTimeout(placeTimer); placeTimer = setTimeout(() => ui.place.classList.add('hidden'), 4000); }
}

// ---------------------------------------------------------------------------
// Boot & main loop
// ---------------------------------------------------------------------------
chooseCar(settings.car || 'rosso', settings.paint);
buildGarage();
{
  world.ensureRoadIndex(400);
  const p = roadPoint(500, LANE);
  car.x = p.x; car.z = p.z; car.h = p.h; car.s = 500; car.lat = LANE; car.d = LANE; camYaw = p.h; car.y = groundAt(p.x, p.z);
  car.vx = Math.sin(p.h) * 16; car.vz = Math.cos(p.h) * 16;
  savePrev(); applyCarPose();
}
let last = performance.now(), bootFrames = 0, frameEma = 1 / 60, resTimer = 0, loadPct = 0;
function renderFrame() {
  compU.time.value = simT % 1000; compU.near.value = camera.near; compU.far.value = camera.far;
  renderer.setRenderTarget(rtHDR);
  renderer.render(scene, camera);
  compU.tBloom.value = renderBloom().texture;
  pass(compMat, null);
}
// Loading screen: rotating tips while the world builds, then three postcards shot in the real world.
const TIPS = ['Press K to start a police chase.', 'V opens the garage: ten cars to choose from.', 'R puts you back on the road.', 'Shift+Z lets the seasons cycle on their own.',
  'F opens photo mode.', 'Space is the handbrake. Slide it.', 'Side streets are open: turn off the main road and explore.', 'T changes the time of day.'];
let tipIdx = Math.floor(Math.random() * TIPS.length);
const showTip = () => { const el = $('tip'); el.style.opacity = 0; setTimeout(() => { el.textContent = TIPS[tipIdx++ % TIPS.length]; el.style.opacity = 0.85; }, 400); };
showTip();
const tipTimer = setInterval(showTip, 3600);
function capturePostcards() {
  const keep = { t: timeOfDay, tt: timeTarget };
  const figs = document.querySelectorAll('#title .pc');
  const clock = (t) => { const m = Math.floor(t * 1440); return String(Math.floor(m / 60)).padStart(2, '0') + ':' + String(m % 60).padStart(2, '0'); };
  const shots = [
    { s: car.s + 8.5, lat: -2.6, up: 0.9, look: -8.5, t: PRESETS[2], aim: 0.55 }, // hero shot of the car, golden hour
    { s: car.s + 40, lat: 0, up: 46, look: 190, t: PRESETS[1], aim: 0 },          // over the road, midday
    { s: car.s + 150, lat: 4.4, up: 1.6, look: 70, t: PRESETS[3], aim: 3.0 },    // the street at sunset
  ];
  shots.forEach((sh, i) => {
    timeOfDay = timeTarget = sh.t; updateSky(0); updateEnv(true);
    const p = roadPoint(sh.s, sh.lat), q = roadPoint(sh.s + sh.look, sh.look < 0 ? LANE : 0);
    camera.position.set(p.x, Math.max(groundAt(p.x, p.z), WATER) + sh.up, p.z);
    camera.lookAt(q.x, q.y + sh.aim, q.z);
    camera.fov = sh.up > 10 ? 55 : 46; camera.updateProjectionMatrix();
    updateStreetLights();
    renderFrame();
    const cv = figs[i].querySelector('canvas'), g = cv.getContext('2d');
    const W = canvas.width, H = canvas.height, ar = cv.width / cv.height;
    let sw = W, shh = W / ar; if (shh > H) { shh = H; sw = H * ar; }
    g.drawImage(canvas, (W - sw) / 2, (H - shh) / 2, sw, shh, 0, 0, cv.width, cv.height);
    figs[i].querySelector('figcaption').textContent = `${PLACE[world.districtAt(p.z)] || ''} · ${clock(sh.t)}`;
  });
  timeOfDay = keep.t; timeTarget = keep.tt; updateSky(0); updateEnv(true); camInit = false;
  document.body.classList.add('shots');
  let front = 0;
  postcardTimer = setInterval(() => { figs.forEach((f, k) => f.classList.toggle('front', k === front)); front = (front + 1) % figs.length; }, 3200);
}
let postcardTimer = 0;
const stats = { frames: 0 };
function frame(now) {
  const rawDt = (now - last) / 1000;
  if (chase.slowmo > 0) chase.slowmo -= rawDt;
  const dt = Math.min(0.1, rawDt) * (chase.slowmo > 0 ? 0.3 : 1);
  last = now; stats.frames++;
  if (!ready) {
    const left = streamWorld(30, 6);
    const pct = Math.max(loadPct, Math.min(99, Math.round(100 * (1 - left / (Math.PI * QUALITY.view * QUALITY.view + 12)))));
    loadPct = pct; $('loadfill').style.width = pct + '%'; $('loadpct').textContent = pct + '%';
    bootFrames++;
    if ((left === 0 && heroReady && bootFrames > 10) || bootFrames > 2400) {
      ready = true; document.body.classList.add('ready'); $('start').textContent = 'Choose where to drive';
      clearInterval(tipTimer);
      if (!AUTOGO) capturePostcards();
      updateEnv(true);
      if (AUTOGO) start();
    }
  } else {
    streamWorld(4, 2);
    frameEma = lerp(frameEma, rawDt, 0.05); resTimer += rawDt;
    if (started && DYNRES && resTimer > 3) {
      resTimer = 0;
      if (frameEma > 1 / 36 && prScale > 0.55) { prScale = Math.max(0.55, prScale - 0.12); resize(); }
      else if (frameEma < 1 / 58 && prScale < 1) { prScale = Math.min(1, prScale + 0.08); resize(); }
    }
  }
  const frozen = paused || photo.on || garageOpen;
  if (!paused) {
    simT += dt;
    seasonU.uTime.value = simT;
    if (dayCycle) timeTarget = (timeTarget + dt / 720) % 1;
    let dT = timeTarget - timeOfDay; if (dT < -0.5) dT += 1; if (dT > 0.5) dT -= 1;
    timeOfDay = (timeOfDay + dT * Math.min(1, dt * (dayCycle ? 10 : 1.4)) + 1) % 1;
    if (autoSeasons) { seasonTimer += dt; if (seasonTimer > 90) { seasonTimer = 0; setSeason(seasonIdx + 1); } }
    if (ready && !frozen) { gatherFootprints(); stepPhysics(dt); updateTraffic(dt); updatePeds(dt); updateChase(dt); }
  }
  applyCarPose();
  updateSky(paused ? 0 : dt);
  updateCamera(paused ? 0 : Math.min(dt, 0.05));
  updateStreetLights();
  if (ready) updateSignals();
  audio.update(frozen ? 0 : car.v, frozen ? 0 : throttle, car.d > ROAD_EDGE + 0.3);
  if (started) { updateHud(); mapTimer -= dt; if (settings.map && mapTimer <= 0 && !photo.on && !uiHidden) { mapTimer = 0.1; drawMap(); } }
  renderFrame();
  if (photo.save) {
    photo.save = false;
    const a = document.createElement('a');
    a.href = canvas.toDataURL('image/png'); a.download = `two-lanes-${REGION_ID}-${SEED}-${Date.now()}.png`; a.click();
    toast('photo saved');
  }
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

// Hooks for the automated tests (tests/smoke.cjs)
window.__game = {
  car, road, chunks, segments, traffic, stats, SEED, REGION_ID, ROAD_EDGE, world,
  isReady: () => ready, start, returnToRoad, setGarage, CARS, setChase, signalState, chaseState: () => chase, setSeason: (i) => setSeason(i, false), setWeather: (v) => { weatherOverride = v; },
  setTime: (t) => { timeOfDay = timeTarget = t; }, setCam, setLook, setPhoto, setMap,
  state: () => ({ chase: chase.on, cops: chase.cops.length, copDist: chase.minD, peds: peds.body.count, traffic: traffic.length, car: carSpec.id, garage: garageOpen, heroReady, autoDrive, camMode, look: settings.look, photo: photo.on, map: settings.map, paused, started, prScale, cruise, steer: car.steer, axis: input.axis, season: seasonIdx, rain, worker: !!workerReady, fallback: !!fallbackGen, pending: pending.size }),
};
