// Three checks of the touch / cursor gradient. Usage: node glow_test.js <run-number>
const { chromium, devices } = require('playwright');
const { PNG } = (() => { try { return require('pngjs'); } catch { return {}; } })();
const FILE = 'file:///home/user/vrl3/docs/previews/easybid-onboarding-preview.html';
const run = process.argv[2] || '1';
const results = [];
const check = (name, ok, detail) => { results.push({ name, ok, detail }); };

async function openPage(browser, opts = {}) {
  const ctx = await browser.newContext(opts);
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  await page.goto(FILE);
  await page.waitForTimeout(300);
  await page.evaluate(() => document.getElementById('intro')?.click());
  await page.waitForTimeout(1600);
  return { ctx, page, errors };
}

const settle = page => page.waitForFunction(() => {
  const g = window.touchGlow; return Math.abs(g.tx - g.x) < 1e-3 && Math.abs(g.ty - g.y) < 1e-3 && Math.abs(g.ta - g.a) < 3e-3;
}, null, { timeout: 4000 });

// Brightest spot of (glow frame - baseline frame), in page pixels.
async function glowCentroid(page, clip) {
  // Freeze everything else that moves (carousel, shimmer, sheen) so only the glow differs.
  await page.addStyleTag({ content: '*,*::before,*::after{animation-play-state:paused!important}' });
  await page.waitForTimeout(100);
  const base = await page.evaluate(() => { const d = document.getElementById('dev'); const prev = d.style.getPropertyValue('--ga'); d.style.setProperty('--ga', '0'); return prev; });
  const a = await page.screenshot({ clip });
  await page.evaluate(v => document.getElementById('dev').style.setProperty('--ga', v), base);
  const b = await page.screenshot({ clip });
  return await page.evaluate(async ([a, b]) => {
    const load = src => new Promise(r => { const i = new Image(); i.onload = () => r(i); i.src = src; });
    const [ia, ib] = await Promise.all([load(a), load(b)]);
    const c = document.createElement('canvas'); c.width = ia.width; c.height = ia.height; const x = c.getContext('2d');
    x.drawImage(ia, 0, 0); const da = x.getImageData(0, 0, c.width, c.height).data;
    x.drawImage(ib, 0, 0); const db = x.getImageData(0, 0, c.width, c.height).data;
    // Strongest point of the glow: the largest colour change, averaged over a
    // 31 x 31 px window so text and card edges don't decide it.
    const W = c.width, H = c.height, gain = new Float32Array(W * H);
    for (let i = 0; i < W * H; i++) gain[i] = Math.abs(db[i*4] - da[i*4]) + Math.abs(db[i*4+1] - da[i*4+1]) + Math.abs(db[i*4+2] - da[i*4+2]);
    let best = -1, bx = 0, by = 0; const R = 15;
    for (let y = R; y < H - R; y += 4) for (let X = R; X < W - R; X += 4) {
      let sum = 0; for (let yy = -R; yy <= R; yy += 3) for (let xx = -R; xx <= R; xx += 3) sum += gain[(y + yy) * W + X + xx];
      if (sum > best) { best = sum; bx = X; by = y; }
    }
    return best > 0 ? { x: bx, y: by, weight: best } : null;
  }, ['data:image/png;base64,' + a.toString('base64'), 'data:image/png;base64,' + b.toString('base64')]);
}

(async () => {
  const browser = await chromium.launch();

  // ---- 1. Cursor: tracking accuracy, first-contact placement, smoothness ----
  {
    const { ctx, page, errors } = await openPage(browser, { viewport: { width: 560, height: 1040 } });
    const box = await page.locator('#dev').boundingBox();
    const P = (fx, fy) => [box.x + box.width * fx, box.y + box.height * fy];
    await page.mouse.move(...P(0.3, 0.35));
    const first = await page.evaluate(() => ({ ...window.touchGlow }));
    check('cursor: glow appears where the pointer enters (no slide from centre)', Math.abs(first.x - 0.3) < 0.02 && Math.abs(first.y - 0.35) < 0.02, `x=${first.x.toFixed(3)} y=${first.y.toFixed(3)}`);
    // Sweep and sample every frame.
    await page.evaluate(() => { window.__samples = []; const s = () => { window.__samples.push([window.touchGlow.x, window.touchGlow.y]); if (window.__samples.length < 90) requestAnimationFrame(s); }; requestAnimationFrame(s); });
    await page.mouse.move(...P(0.75, 0.6), { steps: 25 });
    await settle(page);
    const samples = await page.evaluate(() => window.__samples);
    let overshoot = 0, maxStep = 0;
    for (let i = 1; i < samples.length; i++) { overshoot = Math.max(overshoot, samples[i][0] - 0.75, samples[i][1] - 0.6); maxStep = Math.max(maxStep, Math.hypot(samples[i][0] - samples[i - 1][0], samples[i][1] - samples[i - 1][1])); }
    check('cursor: no overshoot or wobble past the pointer', overshoot < 0.003, `overshoot=${overshoot.toFixed(4)}`);
    check('cursor: no jumps between frames (smooth trail)', maxStep < 0.06, `largest step per frame=${maxStep.toFixed(4)} of the screen`);
    const g = await page.evaluate(() => ({ ...window.touchGlow }));
    check('cursor: settles exactly on the pointer', Math.abs(g.x - 0.75) < 0.002 && Math.abs(g.y - 0.6) < 0.002 && g.a > 0.99, `x=${g.x.toFixed(3)} y=${g.y.toFixed(3)} a=${g.a.toFixed(2)}`);
    const c = await glowCentroid(page, { x: box.x, y: box.y, width: box.width, height: box.height });
    const [px, py] = P(0.75, 0.6);
    const off = c ? Math.hypot(c.x + box.x - px, c.y + box.y - py) : Infinity;
    check('cursor: the brightest part of the glow is under the pointer', off < 40, c ? `${off.toFixed(1)} px from the pointer` : 'no glow found');
    await page.mouse.move(box.x - 30, box.y + 100);
    await settle(page);
    const out = await page.evaluate(() => ({ ...window.touchGlow }));
    check('cursor: leaving fades the glow in place', out.a < 0.01 && Math.abs(out.x - 0.75) < 0.01, `a=${out.a.toFixed(3)} x=${out.x.toFixed(3)}`);
    check('cursor: no errors', errors.length === 0, errors.join(' | ') || 'none');
    await ctx.close();
  }

  // ---- 2. Touch: real touch events on a phone-sized screen ----
  {
    const { ctx, page, errors } = await openPage(browser, { ...devices['iPhone 13'] });
    const cdp = await ctx.newCDPSession(page);
    const box = await page.locator('#dev').boundingBox();
    const T = (fx, fy) => ({ x: box.x + box.width * fx, y: box.y + box.height * fy });
    const touch = (type, p) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: p ? [p] : [] });
    await touch('touchStart', T(0.25, 0.3));
    await page.waitForTimeout(60);
    const start = await page.evaluate(() => ({ ...window.touchGlow }));
    check('touch: glow appears under the finger on touch-down', Math.abs(start.x - 0.25) < 0.02 && Math.abs(start.y - 0.3) < 0.02 && start.ta === 1, `x=${start.x.toFixed(3)} y=${start.y.toFixed(3)}`);
    for (let i = 1; i <= 12; i++) { await touch('touchMove', T(0.25 + 0.04 * i, 0.3 + 0.025 * i)); await page.waitForTimeout(16); }
    await settle(page);
    const moved = await page.evaluate(() => ({ ...window.touchGlow }));
    check('touch: follows a dragging finger', Math.abs(moved.x - 0.73) < 0.01 && Math.abs(moved.y - 0.6) < 0.01, `x=${moved.x.toFixed(3)} y=${moved.y.toFixed(3)}`);
    await touch('touchEnd');
    await settle(page);
    const lifted = await page.evaluate(() => ({ ...window.touchGlow }));
    check('touch: lifting the finger fades the glow where it was', lifted.a < 0.01 && Math.abs(lifted.x - 0.73) < 0.01, `a=${lifted.a.toFixed(3)} x=${lifted.x.toFixed(3)}`);
    await page.tap('.capbtn.white');
    await page.waitForTimeout(300);
    const ob = await page.evaluate(() => S.ob);
    check('touch: buttons still respond to taps', ob === 1, `page after tapping Continue with Apple = ${ob}`);
    const scrollW = await page.evaluate(() => document.documentElement.scrollWidth);
    check('touch: no sideways scrolling at phone width', scrollW <= 390, `scrollWidth=${scrollW}`);
    check('touch: no errors', errors.length === 0, errors.join(' | ') || 'none');
    await ctx.close();
  }

  // ---- 3. States: question page, estimator loading page, idle, Reduce Motion ----
  {
    const { ctx, page, errors } = await openPage(browser, { viewport: { width: 560, height: 1040 } });
    const box = await page.locator('#dev').boundingBox();
    await page.click('#strip [data-jump="6"]'); await page.waitForTimeout(1200);
    await page.mouse.move(box.x + box.width * 0.6, box.y + box.height * 0.3);
    await settle(page);
    const q = await glowCentroid(page, { x: box.x, y: box.y, width: box.width, height: box.height });
    check('states: question page glows under the pointer', q && Math.hypot(q.x - box.width * 0.6, q.y - box.height * 0.3) < 45, q ? `${Math.hypot(q.x - box.width * 0.6, q.y - box.height * 0.3).toFixed(1)} px off` : 'no glow');
    await page.click('#strip [data-jump="10"]'); await page.waitForTimeout(800);
    await page.mouse.move(box.x + box.width * 0.5, box.y + box.height * 0.25);
    await settle(page);
    const shown = await page.evaluate(() => { const g = document.querySelector('.grad.nobg'); return g ? getComputedStyle(g, '::before').display : 'missing'; });
    check('states: estimator loading page has no glow', shown === 'none', `::before display=${shown}`);
    await page.waitForTimeout(1000);
    const f1 = await page.evaluate(() => window.touchGlow.frames); await page.waitForTimeout(500);
    const f2 = await page.evaluate(() => window.touchGlow.frames);
    check('states: animation goes idle when nothing moves', f2 === f1, `frames during 0.5 s idle = ${f2 - f1}`);
    check('states: no errors', errors.length === 0, errors.join(' | ') || 'none');
    await ctx.close();

    const rm = await openPage(browser, { viewport: { width: 560, height: 1040 }, reducedMotion: 'reduce' });
    const b2 = await rm.page.locator('#dev').boundingBox();
    await rm.page.mouse.move(b2.x + b2.width * 0.4, b2.y + b2.height * 0.4, { steps: 5 });
    await rm.page.waitForTimeout(300);
    const a = await rm.page.evaluate(() => window.touchGlow.a);
    check('states: Reduce Motion keeps the glow off', a === 0, `a=${a}`);
    await rm.ctx.close();
  }

  await browser.close();
  const failed = results.filter(r => !r.ok);
  console.log(`Run ${run}: ${results.length - failed.length}/${results.length} passed`);
  for (const r of results) console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.name} — ${r.detail}`);
  process.exit(failed.length ? 1 : 0);
})();
