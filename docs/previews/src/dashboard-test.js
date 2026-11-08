// End-to-end test of easybid-dashboard.html against a simulated Supabase backend.
// Usage: node dashboard-test.js [screenshot-dir]
const { chromium, devices } = require('playwright');
const path = require('path');
const FILE = 'file://' + path.resolve(__dirname, '..', 'easybid-dashboard.html');
const HOST = 'https://tuykoxmpnmrawrknjikr.supabase.co';
const out = process.argv[2];

const now = new Date();
const iso = (monthsAgo, day = 5) => new Date(now.getFullYear(), now.getMonth() - monthsAgo, day, 12).toISOString();
const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
const TOKEN = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ sub: 'user-1', exp: Math.floor(Date.now() / 1000) + 3600, role: 'authenticated' })}.sig`;
const USER = { id: 'user-1', aud: 'authenticated', role: 'authenticated', email: 'pro@example.com', app_metadata: {}, user_metadata: {}, created_at: iso(6) };

function backend(opts = {}) {
  const db = {
    organization_members: [{ organization_id: 'org-1', user_id: 'user-1' }],
    projects: [{ id: 'p1', title: 'Kitchen refresh', project_number: 'PRJ-11111', status: 'Sent', address: '12 Oak St', created_at: iso(1) }],
    estimates: [{ id: 'e1', project_id: 'p1', title: 'Kitchen refresh', estimate_number: 'EST-1', total: 18400, status: 'Sent', created_at: iso(1) }],
    invoices: [
      { id: 'i1', project_id: 'p1', client_id: 'c1', invoice_number: '1001', title: 'Kitchen deposit', status: 'Sent', discount_amount: 0, tax_percent: 0, created_at: iso(0, 2), due_at: iso(0, 1) },
      { id: 'i2', project_id: 'p1', client_id: 'c1', invoice_number: '1000', title: 'Design', status: 'Paid', discount_amount: 100, tax_percent: 10, created_at: iso(1), due_at: null },
    ],
    invoice_items: [{ invoice_id: 'i1', quantity: 1, unit_price: 5000 }, { invoice_id: 'i2', quantity: 2, unit_price: 600 }],
    payments: [{ id: 'pay1', project_id: 'p1', invoice_id: 'i2', amount: 1200, received_at: iso(1, 10) }, { id: 'pay2', project_id: 'p1', invoice_id: null, amount: 1500, received_at: iso(0, 3) }],
    clients: [{ id: 'c1', name: 'Laura Chen' }],
    ai_consents: [],
    estimate_items: [],
  };
  const log = { estimatorCalls: [], inserts: [], consent: [] };
  let estimatorReplies = opts.estimatorReplies || [{ status: 409, body: { code: 'request_in_progress', error: 'busy' } }, { status: 200, body: { estimate_id: 'e-new' } }];
  return { db, log, async handle(route) {
    const req = route.request(); const url = new URL(req.url()); const method = req.method();
    const json = (body, status = 200) => route.fulfill({ status, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(body) });
    if (method === 'OPTIONS') return route.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' } });
    if (url.pathname === '/auth/v1/token') {
      const body = JSON.parse(req.postData() || '{}');
      if (body.password !== 'correct-horse') return json({ error: 'invalid_grant', error_description: 'Invalid login credentials', msg: 'Invalid login credentials', code: 400 }, 400);
      return json({ access_token: TOKEN, token_type: 'bearer', expires_in: 3600, expires_at: Math.floor(Date.now() / 1000) + 3600, refresh_token: 'r1', user: USER });
    }
    if (url.pathname === '/auth/v1/logout') return route.fulfill({ status: 204, headers: { 'access-control-allow-origin': '*' } });
    if (url.pathname === '/functions/v1/smart-service-v7') {
      const h = req.headers(); const body = JSON.parse(req.postData());
      log.estimatorCalls.push({ auth: h['authorization'], apikey: h['apikey'], body });
      const reply = estimatorReplies.shift() || { status: 200, body: { estimate_id: 'e-new' } };
      if (reply.body.estimate_id === 'e-new') {
        db.estimates.unshift({ id: 'e-new', project_id: body.project_id, title: 'Walk-in shower conversion', estimate_number: 'EST-2', total: 14275.5, subtotal: 12500, markup_pct: 10, markup_amount: 1250, contingency_pct: 4, contingency_amount: 525.5, status: 'Draft', exclusions: ['Permits'], created_at: new Date().toISOString() });
        db.estimate_items.push({ estimate_id: 'e-new', category: 'Demolition', name: 'Remove tub and surround', quantity: 1, unit_label: 'job', unit_price: 950, total: 950 },
          { estimate_id: 'e-new', category: 'Tile', name: 'Porcelain wall tile', quantity: 180, unit_label: 'sq ft', unit_price: 14.5, total: 2610 });
      }
      return json(reply.body, reply.status);
    }
    if (url.pathname === '/rest/v1/rpc/set_ai_consent') { const b = JSON.parse(req.postData()); log.consent.push(b); db.ai_consents = [{ is_granted: true, consent_version: b.p_consent_version }]; return json({ user_id: 'user-1', is_granted: true, consent_version: b.p_consent_version }); }
    const table = url.pathname.replace('/rest/v1/', '');
    if (method === 'POST') { const b = JSON.parse(req.postData()); log.inserts.push({ table, row: b, auth: req.headers()['authorization'] }); db[table].unshift({ ...b, created_at: new Date().toISOString() }); return route.fulfill({ status: 201, headers: { 'access-control-allow-origin': '*' } }); }
    let rows = db[table] || [];
    for (const [k, v] of url.searchParams) if (v.startsWith('eq.')) rows = rows.filter(r => String(r[k]) === v.slice(3));
    if ((req.headers()['accept'] || '').includes('vnd.pgrst.object')) return json(rows[0] ?? null);
    return json(rows);
  } };
}

(async () => {
  const browser = await chromium.launch();
  const results = []; const check = (name, ok, detail = '') => results.push({ name, ok, detail });

  // ---- Run 1: phone, full flow ----
  {
    const be = backend();
    const ctx = await browser.newContext({ ...devices['iPhone 13'] });
    const page = await ctx.newPage(); const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    const external = [];
    page.on('request', r => { const u = r.url(); if (!u.startsWith('file:') && !u.startsWith('data:') && !u.startsWith(HOST)) external.push(u); });
    await page.route(HOST + '/**', r => be.handle(r));
    await page.goto(FILE);
    await page.waitForSelector('#authForm');
    if (out) await page.screenshot({ path: out + '/dash-signin.png' });
    await page.fill('#email', 'pro@example.com'); await page.fill('#password', 'wrong');
    await page.click('#authBtn'); await page.waitForTimeout(500);
    const bad = await page.textContent('#authErr');
    check('wrong password shows a clear message', /don't match/.test(bad), bad);
    await page.fill('#password', 'correct-horse'); await page.click('#authBtn');
    await page.waitForSelector('#newEstimate');
    await page.waitForTimeout(1800);
    if (out) await page.screenshot({ path: out + '/dash-home.png' });
    const amt = await page.textContent('#amt');
    check('collected this month comes from payments', amt === '$1,500', amt);
    const stats = await page.$$eval('.st b', els => els.map(e => e.textContent));
    check('outstanding / overdue / pipeline computed from invoices and estimates', stats.join('|') === '$5,000|$5,000|$18,400', stats.join(' | '));
    const est = await page.$$eval('[data-estimate]', els => els.length);
    check('estimates list shows the account\'s estimates', est === 1, `${est} row(s)`);
    const act = await page.$$eval('.row .nm b', els => els.map(e => e.textContent));
    check('activity uses client names', act.includes('Laura Chen'), act.join(', '));
    // New estimate with a new project and first-time AI permission.
    await page.click('#newEstimate'); await page.waitForSelector('#desc');
    await page.click('#mNew'); await page.fill('#pNewTitle', 'Hall bath'); await page.fill('#pNewAddr', '9 Elm St');
    await page.fill('#desc', 'Replace the tub with a walk-in shower and tile to the ceiling.');
    await page.click('#eGo'); await page.waitForTimeout(200);
    check('AI permission is required before sending', (await page.textContent('#eErr')).includes('Allow AI'), await page.textContent('#eErr'));
    await page.check('#consent');
    await page.click('#eGo');
    await page.waitForSelector('text=Building your estimate', { timeout: 8000 }).catch(async e => { console.log('form error:', await page.textContent('#eErr').catch(() => '?'), JSON.stringify(be.log)); throw e; });
    if (out) await page.screenshot({ path: out + '/dash-building.png' });
    await page.waitForSelector('text=Saved to your account', { timeout: 15000 });
    if (out) await page.screenshot({ path: out + '/dash-result.png' });
    const proj = be.log.inserts.find(i => i.table === 'projects');
    check('new project row matches the app (org, PRJ number, Draft)', proj && proj.row.organization_id === 'org-1' && /^PRJ-\d{5}$/.test(proj.row.project_number) && proj.row.status === 'Draft' && proj.row.title === 'Hall bath', JSON.stringify(proj?.row));
    check('AI permission saved with the app\'s consent version', be.log.consent[0]?.p_consent_version === '2026-07-31' && be.log.consent[0]?.p_granted === true, JSON.stringify(be.log.consent[0]));
    const calls = be.log.estimatorCalls;
    check('estimator called with the signed-in token and public key', calls.length === 2 && calls.every(c => c.auth === 'Bearer ' + TOKEN && c.apikey.startsWith('sb_publishable_')), `${calls.length} call(s)`);
    check('request matches the app format (project, messages, request id)', calls[0].body.project_id === proj.row.id && calls[0].body.messages[0].content.startsWith('Replace the tub') && calls[0].body.operation === 'generate', JSON.stringify(calls[0].body).slice(0, 160));
    check('"in progress" reply is retried with the same request id (no duplicate estimate)', calls[0].body.request_id === calls[1].body.request_id, calls.map(c => c.body.request_id.slice(0, 8)).join(' / '));
    const total = await page.$eval('.totals .t span:last-child', e => e.textContent);
    check('result shows the saved estimate and its line items', total === '$14,275.50' && (await page.$$('.item')).length === 2, total);
    await page.click('#sheetX'); await page.waitForTimeout(300);
    check('dashboard refreshes with the new estimate', (await page.$$('[data-estimate]')).length === 2);
    const scrollW = await page.evaluate(() => document.documentElement.scrollWidth);
    check('fits the phone width', scrollW <= 390, `scrollWidth ${scrollW}`);
    await page.click('#signout'); await page.waitForSelector('#authForm');
    check('sign out returns to sign in', true);
    check('no requests to anything but your Supabase project', external.length === 0, external.join(', ') || 'none');
    check('no page errors (phone)', errors.length === 0, errors.join(' | ') || 'none');
    await ctx.close();
  }

  // ---- Run 2: desktop, error handling and empty account ----
  {
    const be = backend({ estimatorReplies: [{ status: 429, body: { code: 'ai_quota_exceeded', error: 'Your AI usage limit has been reached.' } }] });
    for (const t of ['projects', 'estimates', 'invoices', 'invoice_items', 'payments', 'clients']) be.db[t] = [];
    be.db.ai_consents = [{ user_id: 'user-1', is_granted: true, consent_version: '2026-07-31' }];
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 860 } });
    const page = await ctx.newPage(); const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.route(HOST + '/**', r => be.handle(r));
    await page.goto(FILE);
    await page.fill('#email', 'pro@example.com'); await page.fill('#password', 'correct-horse'); await page.click('#authBtn');
    await page.waitForSelector('#newEstimate'); await page.waitForTimeout(800);
    const empty = await page.$$eval('.empty b', els => els.map(e => e.textContent));
    check('empty account shows empty states, no sample data', empty.includes('No estimates yet') && empty.includes('No activity yet') && (await page.textContent('#amt')) === '$0', empty.join(', '));
    if (out) await page.screenshot({ path: out + '/dash-empty-desktop.png' });
    await page.click('#newEstimate'); await page.waitForSelector('#desc');
    check('without projects the form starts on New project, no consent box when already allowed', (await page.$('#mExisting')) === null && (await page.$('#consent')) === null);
    await page.fill('#pNewTitle', 'Deck'); await page.fill('#desc', 'Rebuild a 12 by 16 ft deck with composite boards.');
    await page.click('#eGo');
    await page.waitForSelector('text=Estimate not finished', { timeout: 15000 });
    const msg = await page.textContent('.sheet .err');
    check('service errors are explained in plain words', msg.includes('AI estimate limit'), msg);
    check('reloading keeps you signed in', await (async () => { await page.reload(); await page.waitForSelector('#newEstimate', { timeout: 5000 }); return true; })().catch(() => false));
    check('no page errors (desktop)', errors.length === 0, errors.join(' | ') || 'none');
    await ctx.close();
  }

  await browser.close();
  const failed = results.filter(r => !r.ok);
  console.log(`${results.length - failed.length}/${results.length} passed`);
  for (const r of results) console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.name}${r.detail ? ' — ' + r.detail : ''}`);
  process.exit(failed.length ? 1 : 0);
})();
