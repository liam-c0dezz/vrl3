// The car collection: one detailed glTF model (the hero) plus nine original procedural supercars.
// No real brands, badges or replicas. Every car exposes the same rig: { car, wheels, beam, R, camH, wheelBase, track }.
import { GLTFLoader } from './vendor/jsm/loaders/GLTFLoader.js';
import { MeshoptDecoder } from './vendor/jsm/libs/meshopt_decoder.module.js';
import { toCreasedNormals } from './vendor/jsm/utils/BufferGeometryUtils.js';

// vmax in m/s, acc in m/s², grip = lateral g budget (m/s²), sound = [base Hz, range Hz, wave]
export const CARS = [
  { id: 'rosso', name: 'Rosso Dodici', klass: 'Mid-engine V12 · Italian-style', model: 'assets/cars/hero.glb', color: 0xb0090f,
    vmax: 72, acc: 9.6, grip: 11, sound: [46, 96, 'sawtooth'], camH: 1.08, credit: 'Concept car model by Eric Chadwick (CC-BY 4.0), from a public-domain original' },
  { id: 'apex', name: 'Apex HX', klass: 'Hypercar', color: 0x1f6fff, vmax: 82, acc: 11.5, grip: 12.5, sound: [52, 120, 'sawtooth'], camH: 1.0,
    L: 4.6, W: 2.02, wb: 2.75, track: 0.92, R: 0.36, Wd: 0.34, clr: 0.22,
    top: [[-2.3, 0.5], [-2.36, 0.88], [-2.0, 0.96], [-1.2, 0.98], [0.9, 0.9], [2.15, 0.62], [2.32, 0.42]],
    glass: [[-1.25, 0.95], [-0.6, 1.16], [0.25, 1.19], [0.95, 0.9]], roof: [[-0.62, 1.14], [-0.55, 1.18], [0.26, 1.21], [0.3, 1.17]],
    wing: 'high', lights: 'strip', intakes: true, splitter: true, diffuser: true, exhaust: 'center', rim: 'turbine' },
  { id: 'vector', name: 'Vector 84', klass: "'80s wedge", color: 0xf4f1ec, vmax: 64, acc: 8.4, grip: 9.5, sound: [42, 80, 'sawtooth'], camH: 1.12,
    L: 4.5, W: 1.92, wb: 2.74, track: 0.88, R: 0.34, Wd: 0.3, clr: 0.26,
    top: [[-2.22, 0.5], [-2.26, 0.84], [-1.95, 0.95], [-0.95, 0.97], [1.0, 0.95], [2.15, 0.72], [2.28, 0.5]],
    glass: [[-1.0, 0.95], [-0.52, 1.22], [0.36, 1.25], [1.08, 0.95]], roof: [[-0.6, 1.21], [-0.52, 1.245], [0.36, 1.275], [0.42, 1.24]],
    wing: 'lip', lights: 'pop', louvres: true, exhaust: 'twin', rim: 'star' },
  { id: 'gran', name: 'Gran Corsa GT', klass: 'Grand tourer', color: 0x1a3b2e, vmax: 70, acc: 8.8, grip: 10, sound: [38, 82, 'sawtooth'], camH: 1.15,
    L: 4.8, W: 1.95, wb: 2.9, track: 0.9, R: 0.37, Wd: 0.3, clr: 0.24,
    top: [[-2.4, 0.5], [-2.42, 0.82], [-2.1, 0.9], [-1.2, 0.95], [0.4, 0.95], [1.9, 0.86], [2.38, 0.66], [2.42, 0.45]],
    glass: [[-1.5, 0.93], [-0.7, 1.24], [0.15, 1.27], [0.75, 0.94]], roof: [[-0.8, 1.21], [-0.7, 1.26], [0.15, 1.29], [0.22, 1.25]],
    wing: 'duck', lights: 'quad', exhaust: 'quad', rim: 'mesh', chrome: true },
  { id: 'spyder', name: 'Brezza Spyder', klass: 'Open roadster', color: 0xf2c45a, vmax: 62, acc: 8.6, grip: 10.5, sound: [48, 90, 'sawtooth'], camH: 1.05,
    L: 4.2, W: 1.88, wb: 2.5, track: 0.86, R: 0.34, Wd: 0.28, clr: 0.24, open: true,
    top: [[-2.1, 0.5], [-2.14, 0.84], [-1.8, 0.93], [-0.9, 0.95], [0.35, 0.92], [1.85, 0.78], [2.12, 0.6], [2.16, 0.42]],
    wing: 'none', lights: 'round', rollbars: true, exhaust: 'twin', rim: 'classic' },
  { id: 'circuit', name: 'Circuit R', klass: 'Track car', color: 0xff6a00, vmax: 70, acc: 10.4, grip: 13.5, sound: [58, 130, 'square'], camH: 0.98,
    L: 4.55, W: 2.05, wb: 2.7, track: 0.95, R: 0.35, Wd: 0.36, clr: 0.18,
    top: [[-2.3, 0.45], [-2.32, 0.86], [-2.0, 0.92], [-1.0, 0.95], [0.8, 0.86], [2.2, 0.55], [2.3, 0.36]],
    glass: [[-1.0, 0.93], [-0.45, 1.13], [0.3, 1.15], [0.9, 0.86]], roof: [[-0.5, 1.1], [-0.45, 1.14], [0.3, 1.17], [0.34, 1.13]],
    wing: 'gt', lights: 'strip', intakes: true, splitter: true, canards: true, diffuser: true, exhaust: 'side', rim: 'center', stripes: true },
  { id: 'liberty', name: 'Liberty V8', klass: 'American muscle super', color: 0x2b2d33, vmax: 66, acc: 9.8, grip: 9, sound: [32, 70, 'sawtooth'], camH: 1.18,
    L: 4.7, W: 1.98, wb: 2.8, track: 0.92, R: 0.37, Wd: 0.34, clr: 0.25,
    top: [[-2.35, 0.5], [-2.38, 0.9], [-2.05, 0.98], [-1.1, 1.0], [0.3, 0.99], [2.2, 0.86], [2.35, 0.55]],
    glass: [[-1.2, 0.98], [-0.6, 1.27], [0.2, 1.29], [0.75, 0.98]], roof: [[-0.66, 1.25], [-0.6, 1.28], [0.2, 1.31], [0.24, 1.27]],
    wing: 'duck', lights: 'quad', scoop: true, stripes: true, exhaust: 'quad', rim: 'star' },
  { id: 'volt', name: 'Volta E', klass: 'Electric hyper', color: 0xe8ecef, vmax: 76, acc: 13, grip: 11.5, sound: [120, 260, 'sine'], camH: 1.06,
    L: 4.65, W: 1.98, wb: 2.85, track: 0.9, R: 0.36, Wd: 0.31, clr: 0.22,
    top: [[-2.32, 0.5], [-2.34, 0.86], [-2.0, 0.97], [-1.1, 1.0], [0.8, 0.92], [2.1, 0.66], [2.32, 0.45]],
    glass: [[-1.6, 0.97], [-0.8, 1.2], [0.3, 1.22], [1.0, 0.91]], roof: [[-0.9, 1.18], [-0.8, 1.21], [0.3, 1.24], [0.36, 1.2]],
    wing: 'none', lights: 'bar', diffuser: true, exhaust: 'none', rim: 'aero' },
  { id: 'targa', name: 'Sole Targa', klass: 'Targa', color: 0x8fd3c7, vmax: 64, acc: 8.7, grip: 10, sound: [44, 88, 'sawtooth'], camH: 1.1,
    L: 4.4, W: 1.9, wb: 2.6, track: 0.88, R: 0.35, Wd: 0.3, clr: 0.25, targa: true,
    top: [[-2.2, 0.5], [-2.22, 0.86], [-1.9, 0.95], [-1.0, 0.98], [0.4, 0.96], [1.95, 0.8], [2.2, 0.6], [2.24, 0.44]],
    glass: [[-1.25, 0.96], [-0.75, 1.2], [0.3, 1.22], [0.95, 0.95]], roof: [[-0.85, 1.18], [-0.75, 1.21], [-0.35, 1.22], [-0.32, 1.18]],
    wing: 'lip', lights: 'round', exhaust: 'twin', rim: 'classic' },
  { id: 'brake', name: 'Viaggio Shooting Brake', klass: 'Shooting brake', color: 0x7a1f3d, vmax: 64, acc: 8.2, grip: 9.5, sound: [36, 78, 'sawtooth'], camH: 1.16,
    L: 4.85, W: 1.96, wb: 2.92, track: 0.9, R: 0.37, Wd: 0.3, clr: 0.25,
    top: [[-2.42, 0.5], [-2.44, 0.92], [-2.3, 0.98], [-1.0, 0.98], [0.4, 0.96], [1.95, 0.86], [2.4, 0.64], [2.44, 0.45]],
    glass: [[-2.3, 0.97], [-2.22, 1.26], [0.15, 1.3], [0.85, 0.96]], roof: [[-2.28, 1.24], [-2.2, 1.29], [0.15, 1.33], [0.22, 1.28]],
    wing: 'none', lights: 'quad', exhaust: 'quad', rim: 'mesh', chrome: true },
];
export const PAINT_SWATCHES = [0xb0090f, 0xf4f1ec, 0x14161a, 0x1f6fff, 0xf2c45a, 0x2f8f6a, 0xff6a00, 0x8fd3c7, 0x7a1f3d, 0xb8bcc4];

export function createCars(THREE, VM) {
  const std = (o) => new THREE.MeshStandardMaterial(o);
  const black = std({ color: 0x0c0c0e, roughness: 0.55 });
  const carbon = std({ color: 0x15161a, roughness: 0.35, metalness: 0.4 });
  const caliper = std({ color: 0xe0b020, roughness: 0.4, metalness: 0.2 });
  const disc = std({ color: 0x7a7c80, roughness: 0.35, metalness: 0.9 });
  const stripeMat = std({ color: 0xf4f1ec, roughness: 0.3 });

  // Catmull-Rom through the profile points, so silhouettes curve instead of kinking
  function smoothPts(pts, per = 6) {
    const out = [];
    for (let i = 0; i < pts.length - 1; i++) {
      const p0 = pts[Math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[Math.min(pts.length - 1, i + 2)];
      for (let k = 0; k < per; k++) {
        const t = k / per, t2 = t * t, t3 = t2 * t;
        out.push([0, 1].map((j) => 0.5 * (2 * p1[j] + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2 + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3)));
      }
    }
    out.push(pts[pts.length - 1]);
    return out;
  }
  // Sculpt an extruded side profile into a body: narrower toward the roof (tumblehome), tapered at nose and
  // tail in plan view, tucked under at the sills; then smooth normals except across real creases.
  const sculptF = (y, z, o) => {
    const ty = Math.min(1, Math.max(0, (y - o.belt) / Math.max(0.05, o.top - o.belt)));
    const tz = Math.min(1, Math.abs(z) / o.half);
    let f = 1 - o.tumble * ty * ty * (3 - 2 * ty);
    f *= 1 - o.plan * Math.pow(tz, 2.6);
    const tail = Math.min(1, Math.max(0, (Math.abs(z) / o.half - 0.82) / 0.18)); // round off the corners at nose and tail
    f *= 1 - 0.12 * tail * tail;
    if (y < 0.4) f *= 0.965 + 0.035 * (y / 0.4);
    return f;
  };
  function sculpt(geo, W, opts = {}) {
    const p = geo.attributes.position;
    const o = { belt: 0.72, top: 1.3, half: 2.3, tumble: 0.3, plan: 0.2, ...opts };
    for (let i = 0; i < p.count; i++) p.setX(i, p.getX(i) * sculptF(p.getY(i), p.getZ(i), o));
    geo.deleteAttribute('normal'); geo.deleteAttribute('uv');
    return toCreasedNormals(geo, opts.crease ?? 0.75);
  }
  function sideShape(top, bottomY, arches, xr, xf) {
    const pts = [...smoothPts(top), [xf, bottomY]];
    for (const [cx, r, cy] of arches) {
      pts.push([cx + r, bottomY]);
      for (let i = 0; i <= 14; i++) { const a = (i / 14) * Math.PI; pts.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]); }
      pts.push([cx - r, bottomY]);
    }
    pts.push([xr, bottomY]);
    return polyShape(pts);
  }
  function polyShape(pts) { const s = new THREE.Shape(); pts.forEach(([x, y], i) => (i ? s.lineTo(x, y) : s.moveTo(x, y))); s.closePath(); return s; }
  function extrudeSide(shape, width, bevel = 0.07, segs = 5, steps = 1) {
    const g = new THREE.ExtrudeGeometry(shape, { depth: width - 2 * bevel, bevelEnabled: true, bevelThickness: bevel, bevelSize: bevel, bevelSegments: segs, curveSegments: 10, steps });
    g.rotateY(-Math.PI / 2); g.translate((width - 2 * bevel) / 2, 0, 0);
    return g;
  }
  function wheel(R, Wd, rim = 'star', lod = false) {
    const grp = new THREE.Group();
    const prof = [[R * 0.66, -Wd / 2], [R * 0.9, -Wd / 2], [R * 0.985, -Wd * 0.36], [R, 0], [R * 0.985, Wd * 0.36], [R * 0.9, Wd / 2], [R * 0.66, Wd / 2]].map(([a, b]) => new THREE.Vector2(a, b));
    const tyre = new THREE.Mesh(new THREE.LatheGeometry(prof, lod ? 12 : 30).rotateZ(Math.PI / 2), VM.rubber); tyre.castShadow = true; grp.add(tyre);
    grp.add(new THREE.Mesh(new THREE.CylinderGeometry(R * 0.66, R * 0.66, Wd * 0.7, lod ? 10 : 28).rotateZ(Math.PI / 2), black));
    if (lod) return grp;
    const face = rim === 'aero' ? VM.white : VM.chrome;
    const nSp = rim === 'mesh' ? 12 : rim === 'turbine' ? 9 : rim === 'center' ? 6 : 5;
    for (let k = 0; k < nSp; k++) {
      const sp = new THREE.Mesh(new THREE.BoxGeometry(Wd * 0.16, R * (rim === 'mesh' ? 0.05 : 0.11), R * 1.24), face);
      sp.position.x = Wd * 0.3; sp.rotation.x = (k / nSp) * Math.PI * 2;
      if (rim === 'turbine') sp.rotation.y = 0.35;
      grp.add(sp);
    }
    if (rim === 'aero') { const d = new THREE.Mesh(new THREE.CylinderGeometry(R * 0.6, R * 0.6, 0.02, 28).rotateZ(Math.PI / 2), VM.white); d.position.x = Wd * 0.36; grp.add(d); }
    const lip = new THREE.Mesh(new THREE.TorusGeometry(R * 0.64, 0.012, 6, 30).rotateY(Math.PI / 2), VM.chrome); lip.position.x = Wd * 0.34; grp.add(lip);
    const hub = new THREE.Mesh(new THREE.CylinderGeometry(R * 0.13, R * 0.13, Wd * 0.8, 12).rotateZ(Math.PI / 2), VM.chrome); grp.add(hub);
    const d2 = new THREE.Mesh(new THREE.CylinderGeometry(R * 0.5, R * 0.5, 0.03, 24).rotateZ(Math.PI / 2), disc); d2.position.x = -Wd * 0.05; grp.add(d2);
    return grp;
  }

  // ---- procedural supercar
  function buildProcedural(spec, opts = {}) {
    const lod = !!opts.lod;
    const paint = opts.paint || VM.paint;
    const carG = new THREE.Group(), body = new THREE.Group(); carG.add(body);
    const add = (geo, mat, x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0) => {
      const m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); m.rotation.set(rx, ry, rz);
      m.castShadow = !lod; m.receiveShadow = !lod; body.add(m); return m;
    };
    const { L, W, wb, track, R, Wd, clr } = spec;
    const fz = wb / 2, rz = -wb / 2, ar = R + 0.06;
    const arches = [[fz, ar, R], [rz, ar, R]];
    const yTop = Math.max(...(spec.roof || spec.top).map((q) => q[1])), belt = Math.max(...spec.top.map((q) => q[1])) - 0.12;
    const so = { belt, top: yTop + 0.05, half: L / 2 + 0.05, tumble: 0.16, plan: 0.24 };
    const onSkin = (x, y, z) => x * sculptF(y, z, so); // place details on the sculpted surface
    add(sculpt(extrudeSide(sideShape(spec.top, clr, arches, spec.top[0][0], spec.top[spec.top.length - 1][0]), W, lod ? 0.05 : 0.12, lod ? 2 : 6, lod ? 1 : 4), W, so), paint);
    if (spec.glass && !spec.open) add(sculpt(extrudeSide(polyShape(smoothPts(spec.glass, 4)), W - 0.18, 0.06, lod ? 1 : 3, lod ? 1 : 3), W, { ...so, tumble: 0.34, crease: 0.9 }), VM.glass);
    if (spec.roof && !spec.open) add(sculpt(extrudeSide(polyShape(spec.roof), W - 0.3, 0.04, 2, 3), W, { ...so, tumble: 0.34, crease: 0.9 }), spec.targa ? black : paint);
    if (spec.open || spec.targa) { // windscreen + cockpit
      const gz = spec.glass ? spec.glass[3][0] - 0.1 : 0.4;
      const ws = add(new THREE.BoxGeometry(W - 0.32, 0.42, 0.03), VM.glass, 0, (spec.top[4] ? spec.top[4][1] : 0.95) + 0.16, gz); ws.rotation.x = -0.55;
      if (!lod) {
        add(new THREE.BoxGeometry(W - 0.5, 0.06, 1.5), VM.seat, 0, 0.9, -0.5);
        for (const x of [-0.38, 0.38]) add(new THREE.BoxGeometry(0.5, 0.55, 0.14), VM.seat, x, 1.14, -0.95, -0.15);
        if (spec.rollbars) for (const x of [-0.38, 0.38]) add(new THREE.CapsuleGeometry(0.16, 0.12, 4, 10), paint, x, 1.18, -1.15);
      }
    }
    if (lod) {
      for (const x of [0.55, -0.55]) add(new THREE.BoxGeometry(0.36, 0.08, 0.05), VM.head, x * (W / 1.9), 0.68, spec.top[spec.top.length - 1][0] - 0.06);
    } else {
      const front = spec.top[spec.top.length - 1][0], rear = spec.top[0][0];
      const noseY = spec.top[spec.top.length - 2][1];
      // lights
      if (spec.lights === 'strip' || spec.lights === 'bar') {
        for (const x of [1, -1]) add(new THREE.BoxGeometry(0.5, 0.05, 0.12), VM.head, onSkin(x * (W / 2 - 0.42), noseY - 0.06, front - 0.18), noseY - 0.06, front - 0.18, -0.2);
        if (spec.lights === 'bar') add(new THREE.BoxGeometry(onSkin(W - 0.6, noseY, front - 0.1), 0.025, 0.04), VM.head, 0, noseY - 0.02, front - 0.1);
      } else if (spec.lights === 'round') {
        for (const x of [1, -1]) { add(new THREE.CylinderGeometry(0.13, 0.13, 0.08, 20).rotateX(Math.PI / 2 - 0.4), VM.chrome, x * (W / 2 - 0.36), noseY - 0.02, front - 0.24); add(new THREE.CylinderGeometry(0.105, 0.105, 0.09, 20).rotateX(Math.PI / 2 - 0.4), VM.head, x * (W / 2 - 0.36), noseY - 0.01, front - 0.22); }
      } else if (spec.lights === 'quad') {
        for (const x of [1, -1]) for (const dx of [0, 0.22]) add(new THREE.CylinderGeometry(0.075, 0.075, 0.06, 16).rotateX(Math.PI / 2), VM.head, x * (W / 2 - 0.3 - dx), 0.62, front - 0.04);
      } else { // pop-ups (shown open)
        for (const x of [1, -1]) { add(new THREE.BoxGeometry(0.42, 0.14, 0.24), paint, x * (W / 2 - 0.38), noseY + 0.06, front - 0.55); add(new THREE.BoxGeometry(0.36, 0.1, 0.02), VM.head, x * (W / 2 - 0.38), noseY + 0.06, front - 0.42); }
      }
      const ty = spec.top[1][1] - 0.1;
      if (spec.lights === 'bar' || spec.lights === 'strip') add(new THREE.BoxGeometry(onSkin(W - 0.2, ty, rear), 0.05, 0.05), VM.tail, 0, ty, rear - 0.015);
      else for (const x of [1, -1]) for (const dx of [0, 0.22]) add(new THREE.CylinderGeometry(0.075, 0.075, 0.05, 18).rotateX(Math.PI / 2), VM.tail, onSkin(x * (W / 2 - 0.32 - dx), ty, rear), ty, rear - 0.01);
      // aero
      if (spec.splitter) add(new THREE.BoxGeometry(W - 0.1, 0.04, 0.35), carbon, 0, clr + 0.02, front - 0.12);
      if (spec.canards) for (const x of [1, -1]) add(new THREE.BoxGeometry(0.06, 0.03, 0.3), carbon, x * (W / 2 - 0.02), clr + 0.22, front - 0.3, 0, 0, x * 0.4);
      if (spec.diffuser) for (let k = -2; k <= 2; k++) add(new THREE.BoxGeometry(0.02, 0.16, 0.4), carbon, k * 0.25, clr + 0.05, rear + 0.2, 0.3);
      if (spec.intakes) for (const x of [1, -1]) add(new THREE.BoxGeometry(0.04, 0.22, 0.6), black, x * (W / 2 + 0.005), clr + 0.32, rz + 0.7, 0, 0, 0);
      if (spec.louvres) for (let k = 0; k < 5; k++) add(new THREE.BoxGeometry(W - 0.5, 0.02, 0.05), black, 0, spec.top[2][1] + 0.015, rear + 0.3 + k * 0.1);
      if (spec.scoop) add(new THREE.BoxGeometry(0.6, 0.1, 0.7), black, 0, noseY + 0.2, front - 1.2);
      const wingY = spec.top[1][1] + (spec.wing === 'high' ? 0.42 : spec.wing === 'gt' ? 0.36 : 0.08);
      if (spec.wing === 'high' || spec.wing === 'gt') {
        add(new THREE.BoxGeometry(W - 0.2, 0.04, 0.34), carbon, 0, wingY, rear + 0.25, -0.08);
        for (const x of [0.5, -0.5]) add(new THREE.BoxGeometry(0.03, wingY - spec.top[1][1], 0.12), carbon, x, spec.top[1][1] + (wingY - spec.top[1][1]) / 2, rear + 0.3);
        for (const x of [1, -1]) add(new THREE.BoxGeometry(0.02, 0.16, 0.38), carbon, x * (W / 2 - 0.1), wingY, rear + 0.25);
      } else if (spec.wing === 'lip' || spec.wing === 'duck') add(new THREE.BoxGeometry(W - 0.4, 0.04, spec.wing === 'duck' ? 0.2 : 0.12), spec.wing === 'duck' ? paint : black, 0, wingY - 0.03, rear + 0.12, -0.25);
      // exhausts
      const ex = { center: [0], twin: [0.35, -0.35], quad: [0.5, 0.36, -0.36, -0.5], side: [], none: [] }[spec.exhaust || 'twin'];
      for (const x of ex) add(new THREE.CylinderGeometry(0.05, 0.05, 0.2, 14).rotateX(Math.PI / 2), VM.chrome, x, clr + 0.08, rear + 0.04);
      if (spec.exhaust === 'side') for (const x of [1, -1]) add(new THREE.CylinderGeometry(0.05, 0.05, 0.3, 14).rotateZ(Math.PI / 2), VM.chrome, x * (W / 2 + 0.05), clr + 0.08, rz + 0.55);
      // details: mirrors, door seams, grille, plate holder, chrome trim
      for (const x of [1, -1]) {
        add(new THREE.BoxGeometry(0.16, 0.08, 0.2), paint, x * (W / 2 + 0.03), (spec.top[3][1] || 0.95) + 0.03, (spec.glass ? spec.glass[3][0] : 0.5) - 0.15);
        add(new THREE.BoxGeometry(0.005, 0.5, 0.012), black, x * (W / 2 + 0.003), 0.66, 0.05);
        add(new THREE.BoxGeometry(0.005, 0.012, 1.0), black, x * (W / 2 + 0.003), 0.62, -0.4);
        if (spec.chrome) add(new THREE.BoxGeometry(0.01, 0.02, L * 0.6), VM.chrome, x * (W / 2 + 0.004), clr + 0.28, 0);
      }
      add(new THREE.BoxGeometry(W * 0.45, 0.12, 0.03), black, 0, clr + 0.18, front - 0.02);
      add(new THREE.BoxGeometry(0.5, 0.11, 0.02), VM.plate, 0, clr + 0.22, rear - 0.01);
      // racing stripes along the top
      if (spec.stripes) {
        const pts = spec.top;
        for (let i = 0; i < pts.length - 1; i++) {
          const [z0, y0] = pts[i], [z1, y1] = pts[i + 1], len = Math.hypot(z1 - z0, y1 - y0);
          if (i === 0) continue;
          for (const x of [0.17, -0.17]) add(new THREE.BoxGeometry(0.2, 0.006, len), stripeMat, x, (y0 + y1) / 2 + 0.004, (z0 + z1) / 2, -Math.atan2(y1 - y0, z1 - z0));
        }
      }
      // brake calipers behind the spokes
      for (const [x, z] of [[track, fz], [-track, fz], [track, rz], [-track, rz]]) add(new THREE.BoxGeometry(0.06, 0.16, 0.22), caliper, x * 0.92, R + 0.12, z - 0.08);
    }
    add(new THREE.BoxGeometry(W - 0.2, 0.06, L * 0.85), black, 0, clr + 0.02, 0);
    const wheels = [[track, fz], [-track, fz], [track, rz], [-track, rz]].map(([x, z]) => {
      const pivot = new THREE.Group(); pivot.position.set(x, R, z);
      const w = wheel(R, Wd, spec.rim, lod);
      if (x < 0) w.rotation.y = Math.PI; // rim faces outward on both sides
      const spin = new THREE.Group(); spin.add(w); pivot.add(spin); carG.add(pivot);
      return { pivot, spin, front: z > 0 };
    });
    return finish(carG, body, wheels, spec, R, wb, track);
  }
  function finish(carG, body, wheels, spec, R, wb, track) {
    const beam = new THREE.SpotLight(0xfff1d8, 0, 110, 0.5, 0.55, 1.3);
    beam.position.set(0, 0.75, 2.1); beam.target.position.set(0, -1.2, 24);
    carG.add(beam, beam.target);
    return { car: carG, body, wheels, beam, R, camH: spec.camH || 1.1, wheelBase: wb, track, spec };
  }

  // ---- the glTF hero
  const loader = new GLTFLoader();
  loader.setMeshoptDecoder(MeshoptDecoder);
  const modelCache = new Map();
  function loadModel(url) {
    if (!modelCache.has(url)) modelCache.set(url, new Promise((res, rej) => loader.load(url, (g) => res(g.scene), undefined, rej)));
    return modelCache.get(url);
  }
  async function buildModel(spec, paintMat) {
    const src = await loadModel(spec.model);
    const scene = src.clone(true);
    const carG = new THREE.Group(), body = new THREE.Group(); carG.add(body); body.add(scene);
    scene.updateMatrixWorld(true);
    const paint = paintMat || VM.paint;
    scene.traverse((o) => {
      if (!o.isMesh) return;
      o.castShadow = true; o.receiveShadow = true;
      const n = (o.material && o.material.name) || '';
      if (/^Paint 1/.test(n)) o.material = paint;
      else if (/^Glass/.test(n)) o.material = VM.glass;
      else if (/Headlight/.test(n)) o.material = VM.head;
      else if (/Brakelight|Signallight/.test(n)) o.material = VM.tail;
      else if (o.material && o.material.transmission) o.material = VM.glass;
    });
    const wheels = [];
    const nodes = [];
    scene.traverse((o) => { if (/^Wheel(Front|Rear)[LR]$/.test(o.name)) nodes.push(o); });
    let R = 0.38;
    for (const node of nodes) {
      const p = new THREE.Vector3(); node.getWorldPosition(p);
      R = p.y;
      const pivot = new THREE.Group(); pivot.position.copy(p);
      const spin = new THREE.Group(); pivot.add(spin); carG.add(pivot);
      pivot.updateMatrixWorld(true);
      spin.attach(node);
      wheels.push({ pivot, spin, front: p.z > 0 });
    }
    const fzs = wheels.filter((w) => w.front).map((w) => w.pivot.position.z), rzs = wheels.filter((w) => !w.front).map((w) => w.pivot.position.z);
    const wb = (fzs[0] || 1.4) - (rzs[0] || -1.4);
    const track = Math.abs(wheels[0] ? wheels[0].pivot.position.x : 0.95);
    // centre the car between its axles so it pivots like the procedural ones
    const mid = ((fzs[0] || 1.4) + (rzs[0] || -1.4)) / 2;
    body.position.z = -mid; for (const w of wheels) w.pivot.position.z -= mid;
    return finish(carG, body, wheels, spec, R, wb, track);
  }

  return { CARS, buildProcedural, buildModel, loadModel, wheel, extrudeSide, sideShape, polyShape };
}
