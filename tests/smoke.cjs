// Smoke test for Two Lanes: runs both regions (California, South Florida) on a desktop and a
// mobile viewport in headless Chromium, exercises the main features and saves screenshots.
//
//   node tests/smoke.cjs            # full matrix
//   node tests/smoke.cjs ca         # one region
//
// Needs Playwright (require('playwright')). Screenshots land in tests/output/.
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(__dirname, 'output');
fs.mkdirSync(OUT, { recursive: true });
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png' };

function serve() {
  const server = http.createServer((req, res) => {
    const p = path.join(ROOT, decodeURIComponent(new URL(req.url, 'http://x').pathname));
    if (!p.startsWith(ROOT)) { res.writeHead(403); return res.end(); }
    const file = fs.existsSync(p) && fs.statSync(p).isDirectory() ? path.join(p, 'index.html') : p;
    fs.readFile(file, (err, data) => {
      if (err) { res.writeHead(404); return res.end(); }
      res.writeHead(200, { 'content-type': TYPES[path.extname(file)] || 'application/octet-stream' });
      res.end(data);
    });
  });
  return new Promise((r) => server.listen(0, () => r(server)));
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// Game time advances at most 0.05 s per frame, so slow (software) rendering needs frame-based waits.
async function waitFrames(page, n) {
  const f0 = await page.evaluate(() => window.__game.stats.frames);
  await page.waitForFunction((t) => window.__game.stats.frames >= t, f0 + n, { timeout: 900000 });
}
const results = [];
function check(name, ok, detail = '') { results.push({ name, ok, detail }); console.log(`${ok ? '  ✓' : '  ✗'} ${name}${detail ? '  — ' + detail : ''}`); }

async function run(browser, base, region, device) {
  const mobile = device === 'mobile';
  const ctx = await browser.newContext(mobile
    ? { viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 1 }
    : { viewport: { width: 960, height: 540 }, deviceScaleFactor: 1 });
  const page = await ctx.newPage();
  page.setDefaultTimeout(600000); // software rendering can take tens of seconds per frame
  const errors = [];
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  page.on('console', (m) => { if (m.type() === 'error' && !/fonts\.g|ERR_|net::/.test(m.text())) errors.push(m.text()); });
  const tag = `${region}-${device}`;
  console.log(`\n[${tag}]`);

  await page.goto(`${base}/?region=${region}&seed=4242&view=4&dynres=0`);
  await page.waitForFunction(() => window.__game && window.__game.isReady(), null, { timeout: 600000 });
  check(`${tag}: world generates`, true);
  check(`${tag}: world builds in a background worker`, await page.evaluate(() => window.__game.state().worker));
  await page.screenshot({ path: path.join(OUT, `${tag}-title.png`) });
  const titleVisible = await page.evaluate(() => getComputedStyle(document.getElementById('title')).opacity === '1');
  check(`${tag}: title poster shows`, titleVisible);

  // start by clicking the current region card
  await page.click(`.region[data-region="${region}"]`);
  await sleep(400);
  const st0 = await page.evaluate(() => window.__game.state());
  check(`${tag}: starts on region click`, st0.started);

  // auto-drive for a while: should stay on the road and keep moving
  const p0 = await page.evaluate(() => ({ ...window.__game.car }));
  await waitFrames(page, 60); // 3 s of game time
  const p1 = await page.evaluate(() => ({ ...window.__game.car, edge: window.__game.ROAD_EDGE }));
  check(`${tag}: auto-drive moves`, p1.odo - p0.odo > 15, `${(p1.odo - p0.odo).toFixed(1)} m`);
  check(`${tag}: auto-drive stays on road`, p1.d < p1.edge, `${p1.d.toFixed(2)} m from centre`);
  check(`${tag}: stays in right lane`, p1.lat > 0.3 && p1.lat < 3.6, `lat ${p1.lat.toFixed(2)}`);
  await page.screenshot({ path: path.join(OUT, `${tag}-drive.png`) });

  // the city is alive: traffic, pedestrians, cycling signals
  const life = await page.evaluate(() => ({ s: window.__game.state(), sig: [0, 1, 2, 3].map((m) => window.__game.signalState(m)) }));
  check(`${tag}: traffic is on the road`, life.s.traffic > 0, `${life.s.traffic} cars`);
  check(`${tag}: pedestrians on the sidewalks`, life.s.peds > 0, `${life.s.peds} people`);
  check(`${tag}: signals have a state`, life.sig.every((x) => 'gyr'.includes(x)), life.sig.join(''));
  // route map draws something
  const mapInk = await page.evaluate(() => {
    const c = document.getElementById('map'); const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
    let n = 0; for (let i = 3; i < d.length; i += 4) if (d[i] > 0) n++; return n / (d.length / 4);
  });
  check(`${tag}: route map renders`, mapInk > 0.5, `${(mapInk * 100).toFixed(0)}% filled`);

  if (!mobile) {
    // looks
    for (const [i, name] of ['cinematic', 'poster', 'riso'].entries()) {
      await page.evaluate((i) => window.__game.setLook(i), i);
      await sleep(600);
      await page.screenshot({ path: path.join(OUT, `${tag}-look-${name}.png`) });
    }
    await page.evaluate(() => window.__game.setLook(0));
    const lk = await page.evaluate(() => window.__game.state().look);
    check(`${tag}: look switching`, lk === 0);
    // cameras
    for (const [i, name] of ['chase', 'driver', 'cinematic'].entries()) {
      await page.evaluate((i) => window.__game.setCam(i), i);
      await sleep(1200);
      await page.screenshot({ path: path.join(OUT, `${tag}-cam-${name}.png`) });
    }
    await page.evaluate(() => window.__game.setCam(0));
    // time of day
    for (const [t, name] of [[0.5, 'noon'], [0.9, 'night']]) {
      await page.evaluate((t) => window.__game.setTime(t), t);
      await sleep(900);
      await page.screenshot({ path: path.join(OUT, `${tag}-time-${name}.png`) });
    }
    await page.evaluate(() => window.__game.setTime(0.728));

    // keyboard: W in auto-drive raises cruise speed instead of disengaging
    const c0 = await page.evaluate(() => window.__game.state().cruise);
    await page.keyboard.down('KeyW'); await sleep(700); await page.keyboard.up('KeyW');
    const s1 = await page.evaluate(() => window.__game.state());
    check(`${tag}: W raises cruise in auto-drive`, s1.autoDrive && s1.cruise > c0, `${c0.toFixed(1)} → ${s1.cruise.toFixed(1)} m/s`);

    // manual steering takes over and turns the car
    const h0 = await page.evaluate(() => window.__game.car.h);
    await page.keyboard.down('ArrowLeft'); await sleep(500); await page.keyboard.up('ArrowLeft');
    const s2 = await page.evaluate(() => ({ st: window.__game.state(), h: window.__game.car.h }));
    check(`${tag}: steering takes over from auto-drive`, !s2.st.autoDrive);
    check(`${tag}: steering left turns the car left`, s2.h > h0, `heading +${(s2.h - h0).toFixed(3)} rad`);
    // braking slows down
    const v0 = await page.evaluate(() => window.__game.car.v);
    await page.keyboard.down('KeyS'); await waitFrames(page, 25); await page.keyboard.up('KeyS');
    const v1 = await page.evaluate(() => window.__game.car.v);
    check(`${tag}: brake slows the car`, v1 < v0 - 3, `${v0.toFixed(1)} → ${v1.toFixed(1)} m/s`);
    await page.keyboard.press('KeyE');
    check(`${tag}: E re-engages auto-drive`, (await page.evaluate(() => window.__game.state().autoDrive)));

    // R puts the car back in its lane after wandering off
    await page.keyboard.down('ArrowLeft'); await waitFrames(page, 30); await page.keyboard.up('ArrowLeft');
    const off = await page.evaluate(() => ({ lat: window.__game.car.lat, d: window.__game.car.d }));
    await page.keyboard.press('KeyR'); await waitFrames(page, 3);
    const back = await page.evaluate(() => ({ lat: window.__game.car.lat, d: window.__game.car.d }));
    check(`${tag}: R returns to the road`, Math.abs(back.lat - 1.8) < 0.4 && back.d < 2.5, `lat ${off.lat.toFixed(1)} → ${back.lat.toFixed(2)}`);
    // handbrake scrubs speed
    await page.keyboard.down('KeyW'); await waitFrames(page, 40); await page.keyboard.up('KeyW'); // get some speed up first
    const hv0 = await page.evaluate(() => window.__game.car.v);
    await page.keyboard.down('Space'); await waitFrames(page, 20); await page.keyboard.up('Space');
    const hv1 = await page.evaluate(() => window.__game.car.v);
    check(`${tag}: handbrake slows the car`, hv1 < hv0 - 1, `${hv0.toFixed(1)} → ${hv1.toFixed(1)} m/s`);
    await page.keyboard.press('KeyE');
    // seasons: Z steps through spring → summer → fall → winter
    const s0 = await page.evaluate(() => window.__game.state().season);
    const seen = [];
    for (let i = 0; i < 4; i++) {
      await page.keyboard.press('KeyZ'); await waitFrames(page, 8);
      seen.push(await page.evaluate(() => window.__game.state().season));
      await page.screenshot({ path: path.join(OUT, `${tag}-season-${seen[i]}.png`) });
    }
    check(`${tag}: Z cycles all four seasons`, new Set(seen).size === 4 && seen[3] === s0, seen.join(','));
    const nan = await page.evaluate(() => Object.values(window.__game.car).some((v) => typeof v === 'number' && !Number.isFinite(v)));
    check(`${tag}: physics state stays finite`, !nan);

    // pause menu
    await page.keyboard.press('Escape');
    await page.waitForTimeout(500); // let the 0.2s fade finish
    const mo = await page.evaluate(() => { const b = document.getElementById('buttons'); return { st: window.__game.state(), shown: !b.classList.contains('hidden') && getComputedStyle(b).visibility !== 'hidden' }; });
    check(`${tag}: Esc opens the pause menu`, mo.st.paused && mo.shown);
    await page.keyboard.press('Escape');
    check(`${tag}: Esc closes it again`, !(await page.evaluate(() => window.__game.state().paused)));
    // garage: ten cars, switching works
    await page.keyboard.press('KeyV');
    const g = await page.evaluate(() => ({ n: document.querySelectorAll('#gList button').length, open: window.__game.state().garage }));
    check(`${tag}: garage lists ten cars`, g.open && g.n === 10, `${g.n} cars`);
    await page.evaluate(() => document.querySelector('#gList button[data-id="apex"]').click());
    await waitFrames(page, 4);
    check(`${tag}: picking a car swaps it`, (await page.evaluate(() => window.__game.state().car)) === 'apex');
    await page.screenshot({ path: path.join(OUT, `${tag}-garage.png`) });
    await page.keyboard.press('KeyV');
    // police chase
    await page.keyboard.press('KeyK'); await waitFrames(page, 20);
    const ch = await page.evaluate(() => window.__game.state());
    check(`${tag}: K starts a police chase`, ch.chase && ch.cops >= 2, `${ch.cops} cruisers, nearest ${ch.copDist ? ch.copDist.toFixed(0) : '?'} m`);
    await page.screenshot({ path: path.join(OUT, `${tag}-chase.png`) });
    await page.keyboard.press('KeyK');
    check(`${tag}: K ends the chase`, !(await page.evaluate(() => window.__game.state().chase)));
    await page.keyboard.press('KeyF');
    const a = await page.evaluate(() => window.__game.car.odo);
    await sleep(1000);
    const b = await page.evaluate(() => ({ odo: window.__game.car.odo, st: window.__game.state(), hud: getComputedStyle(document.getElementById('hud')).opacity }));
    check(`${tag}: photo mode freezes the drive`, b.st.photo && Math.abs(b.odo - a) < 0.01);
    check(`${tag}: photo mode hides the HUD`, b.hud === '0');
    await page.mouse.move(640, 360); await page.mouse.down(); await page.mouse.move(800, 330, { steps: 6 }); await page.mouse.up();
    await sleep(300);
    await page.screenshot({ path: path.join(OUT, `${tag}-photo.png`) });
    const dl = page.waitForEvent('download', { timeout: 180000 }).catch(() => null);
    await page.keyboard.press('Enter');
    const download = await dl;
    check(`${tag}: photo mode saves a PNG`, !!download && /\.png$/.test(download.suggestedFilename()), download ? download.suggestedFilename() : 'no download');
    await page.keyboard.press('KeyF');
    check(`${tag}: photo mode exits`, !(await page.evaluate(() => window.__game.state().photo)));

    // settings persist across reloads
    await page.keyboard.press('KeyX'); // -> riso
    await page.reload();
    await page.waitForFunction(() => window.__game && window.__game.isReady(), null, { timeout: 600000 });
    check(`${tag}: look setting persists`, (await page.evaluate(() => window.__game.state().look)) === 1);
    check(`${tag}: chosen car persists`, (await page.evaluate(() => window.__game.state().car)) === 'apex');
    await page.evaluate(() => { localStorage.clear(); });
    await page.evaluate(() => window.__game.setLook(0));
  } else {
    // on-screen touch controls are shown and usable
    const pad = await page.evaluate(() => {
      const vis = (id) => { const r = document.getElementById(id).getBoundingClientRect(); return r.width > 0 && r.left >= 0 && r.right <= innerWidth && r.bottom <= innerHeight; };
      return { shown: getComputedStyle(document.getElementById('touchpad')).opacity === '1', steer: vis('steerZone'), gas: vis('gasBtn'), brake: vis('brakeBtn') };
    });
    check(`${tag}: touch controls are on screen`, pad.shown && pad.steer && pad.gas && pad.brake, JSON.stringify(pad));
    const fire = (id, type, x, pid = 7) => page.evaluate(([id, type, x, pid]) => {
      const el = document.getElementById(id), r = el.getBoundingClientRect();
      el.dispatchEvent(new PointerEvent(type, { pointerId: pid, pointerType: 'touch', clientX: r.left + r.width / 2 + x, clientY: r.top + r.height / 2, bubbles: true, cancelable: true }));
    }, [id, type, x, pid]);
    // drag the steering pad left: analog steer, takes over from auto-drive, turns left
    const h0 = await page.evaluate(() => window.__game.car.h);
    await fire('steerZone', 'pointerdown', 0); await fire('steerZone', 'pointermove', -40);
    const axis = await page.evaluate(() => window.__game.state().axis);
    await waitFrames(page, 12);
    await fire('steerZone', 'pointerup', -40);
    const s = await page.evaluate(() => ({ st: window.__game.state(), h: window.__game.car.h }));
    check(`${tag}: steering pad is analog`, axis > 0.2 && axis < 0.95, `axis ${axis.toFixed(2)} at 40px`);
    check(`${tag}: steering pad takes over`, !s.st.autoDrive);
    check(`${tag}: dragging left turns left`, s.h > h0, `heading +${(s.h - h0).toFixed(3)} rad`);
    check(`${tag}: releasing the pad centres it`, s.st.axis === 0);
    await fire('resetBtn', 'pointerdown', 0, 10); await waitFrames(page, 2);
    const back = await page.evaluate(() => window.__game.car.lat);
    check(`${tag}: reset button returns to the lane`, Math.abs(back - 1.8) < 0.4, `lat ${back.toFixed(2)}`);
    // gas, then brake (two fingers at once must not interfere)
    const v0 = await page.evaluate(() => window.__game.car.v);
    await fire('gasBtn', 'pointerdown', 0, 8); await waitFrames(page, 30);
    const v1 = await page.evaluate(() => window.__game.car.v);
    await fire('gasBtn', 'pointerup', 0, 8);
    check(`${tag}: gas pedal accelerates`, v1 > v0 + 1, `${v0.toFixed(1)} → ${v1.toFixed(1)} m/s`);
    await fire('brakeBtn', 'pointerdown', 0, 9); await waitFrames(page, 20); await fire('brakeBtn', 'pointerup', 0, 9);
    const v2 = await page.evaluate(() => window.__game.car.v);
    check(`${tag}: brake pedal slows down`, v2 < v1 - 2, `${v1.toFixed(1)} → ${v2.toFixed(1)} m/s`);
    await fire('chaseBtn', 'pointerdown', 0, 12); await waitFrames(page, 4);
    check(`${tag}: chase button starts a chase`, await page.evaluate(() => window.__game.state().chase));
    await fire('chaseBtn', 'pointerdown', 0, 13);
    await fire('autoBtn', 'pointerdown', 0, 11);
    check(`${tag}: auto button re-engages auto-drive`, await page.evaluate(() => window.__game.state().autoDrive));
    const overlap = await page.evaluate(() => {
      const a = document.getElementById('hud').getBoundingClientRect(), b = document.getElementById('steerZone').getBoundingClientRect();
      return !(a.right < b.left || a.left > b.right || a.bottom < b.top || a.top > b.bottom);
    });
    check(`${tag}: HUD clears the touch controls`, !overlap);
    // buttons fit on screen
    const overflow = await page.evaluate(() => [...document.querySelectorAll('#buttons button')].some((b) => b.getBoundingClientRect().right > innerWidth + 1));
    check(`${tag}: buttons fit the screen`, !overflow);
    await page.screenshot({ path: path.join(OUT, `${tag}-touch.png`) });
  }

  const fps = await page.evaluate(async () => { const f0 = window.__game.stats.frames; await new Promise((r) => setTimeout(r, 2000)); return (window.__game.stats.frames - f0) / 2; });
  console.log(`  · ${fps.toFixed(1)} fps in headless software rendering (not representative of a real GPU)`);
  check(`${tag}: no page errors`, errors.length === 0, errors.slice(0, 3).join(' | '));
  await ctx.close();
}

(async () => {
  const only = process.argv[2];
  const regions = only ? [only] : ['ca', 'sf'];
  const server = await serve();
  const base = `http://localhost:${server.address().port}`;
  const browser = await chromium.launch();
  try {
    for (const region of regions) for (const device of (process.argv[3] ? [process.argv[3]] : ['desktop', 'mobile'])) await run(browser, base, region, device);
  } finally {
    await browser.close();
    server.close();
  }
  const failed = results.filter((r) => !r.ok);
  console.log(`\n${results.length - failed.length}/${results.length} checks passed${failed.length ? ' — FAILED: ' + failed.map((f) => f.name).join(', ') : ''}`);
  process.exit(failed.length ? 1 : 0);
})();
