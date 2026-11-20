// Smoke test for Two Lanes: runs both regions (California, North Florida) on a desktop and a
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
  await page.waitForFunction((t) => window.__game.stats.frames >= t, f0 + n, { timeout: 120000 });
}
const results = [];
function check(name, ok, detail = '') { results.push({ name, ok, detail }); console.log(`${ok ? '  ✓' : '  ✗'} ${name}${detail ? '  — ' + detail : ''}`); }

async function run(browser, base, region, device) {
  const mobile = device === 'mobile';
  const ctx = await browser.newContext(mobile
    ? { viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 1 }
    : { viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1 });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  page.on('console', (m) => { if (m.type() === 'error' && !/fonts\.g|ERR_|net::/.test(m.text())) errors.push(m.text()); });
  const tag = `${region}-${device}`;
  console.log(`\n[${tag}]`);

  await page.goto(`${base}/?region=${region}&seed=4242&view=5&dynres=0`);
  await page.waitForFunction(() => window.__game && window.__game.isReady(), null, { timeout: 240000 });
  check(`${tag}: world generates`, true);
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
  check(`${tag}: auto-drive moves`, p1.odo - p0.odo > 30, `${(p1.odo - p0.odo).toFixed(1)} m`);
  check(`${tag}: auto-drive stays on road`, p1.d < p1.edge, `${p1.d.toFixed(2)} m from centre`);
  check(`${tag}: stays in right lane`, p1.lat > 0.3 && p1.lat < 3.6, `lat ${p1.lat.toFixed(2)}`);
  await page.screenshot({ path: path.join(OUT, `${tag}-drive.png`) });

  // route map draws something
  const mapInk = await page.evaluate(() => {
    const c = document.getElementById('map'); const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
    let n = 0; for (let i = 3; i < d.length; i += 4) if (d[i] > 0) n++; return n / (d.length / 4);
  });
  check(`${tag}: route map renders`, mapInk > 0.5, `${(mapInk * 100).toFixed(0)}% filled`);

  if (!mobile) {
    // looks
    for (const [i, name] of ['poster', 'riso', 'clean'].entries()) {
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

    // photo mode freezes the car and hides the HUD
    await page.keyboard.press('KeyF');
    const a = await page.evaluate(() => window.__game.car.odo);
    await sleep(1000);
    const b = await page.evaluate(() => ({ odo: window.__game.car.odo, st: window.__game.state(), hud: getComputedStyle(document.getElementById('hud')).opacity }));
    check(`${tag}: photo mode freezes the drive`, b.st.photo && Math.abs(b.odo - a) < 0.01);
    check(`${tag}: photo mode hides the HUD`, b.hud === '0');
    await page.mouse.move(640, 360); await page.mouse.down(); await page.mouse.move(800, 330, { steps: 6 }); await page.mouse.up();
    await sleep(300);
    await page.screenshot({ path: path.join(OUT, `${tag}-photo.png`) });
    const dl = page.waitForEvent('download', { timeout: 5000 }).catch(() => null);
    await page.keyboard.press('Enter');
    const download = await dl;
    check(`${tag}: photo mode saves a PNG`, !!download && /\.png$/.test(download.suggestedFilename()), download ? download.suggestedFilename() : 'no download');
    await page.keyboard.press('KeyF');
    check(`${tag}: photo mode exits`, !(await page.evaluate(() => window.__game.state().photo)));

    // settings persist across reloads
    await page.keyboard.press('KeyX'); // -> riso
    await page.reload();
    await page.waitForFunction(() => window.__game && window.__game.isReady(), null, { timeout: 240000 });
    check(`${tag}: look setting persists`, (await page.evaluate(() => window.__game.state().look)) === 1);
    await page.evaluate(() => window.__game.setLook(0));
  } else {
    // touch steering on the left half disengages auto-drive and turns left
    const h0 = await page.evaluate(() => window.__game.car.h);
    await page.evaluate(() => {
      const c = document.getElementById('game');
      c.dispatchEvent(new PointerEvent('pointerdown', { pointerId: 7, pointerType: 'touch', clientX: 60, clientY: 500, bubbles: true }));
    });
    await sleep(600);
    await page.evaluate(() => {
      const c = document.getElementById('game');
      c.dispatchEvent(new PointerEvent('pointerup', { pointerId: 7, pointerType: 'touch', clientX: 60, clientY: 500, bubbles: true }));
    });
    const s = await page.evaluate(() => ({ st: window.__game.state(), h: window.__game.car.h, v: window.__game.car.v }));
    check(`${tag}: touch steering takes over`, !s.st.autoDrive);
    check(`${tag}: touch left turns left`, s.h > h0, `heading +${(s.h - h0).toFixed(3)} rad`);
    check(`${tag}: touch keeps cruising`, s.v > 5, `${s.v.toFixed(1)} m/s`);
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
  const regions = only ? [only] : ['ca', 'fl'];
  const server = await serve();
  const base = `http://localhost:${server.address().port}`;
  const browser = await chromium.launch();
  try {
    for (const region of regions) for (const device of ['desktop', 'mobile']) await run(browser, base, region, device);
  } finally {
    await browser.close();
    server.close();
  }
  const failed = results.filter((r) => !r.ok);
  console.log(`\n${results.length - failed.length}/${results.length} checks passed${failed.length ? ' — FAILED: ' + failed.map((f) => f.name).join(', ') : ''}`);
  process.exit(failed.length ? 1 : 0);
})();
