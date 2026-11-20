// Web Worker: builds terrain chunks and road segments off the main thread.
import { createGen } from './gen.js';

let gen = null;
const queue = [];
self.onmessage = async (e) => {
  const m = e.data;
  if (m.type === 'init') {
    const THREE = await import(m.threeUrl);
    gen = createGen(THREE, m.seed, m.region);
    self.postMessage({ type: 'ready' });
    pump();
    return;
  }
  if (m.type === 'cancel') { const i = queue.findIndex((q) => q.key === m.key); if (i >= 0) queue.splice(i, 1); return; }
  queue.push(m);
  pump();
};
let busy = false;
function pump() {
  if (busy || !gen || !queue.length) return;
  busy = true;
  const m = queue.shift();
  try {
    const r = m.type === 'chunk' ? gen.chunk(m.cx, m.cz) : gen.segment(m.k);
    self.postMessage(r.msg, r.transfer);
  } catch (err) {
    self.postMessage({ type: 'error', key: m.key, message: String((err && err.stack) || err) });
  }
  busy = false;
  if (queue.length) setTimeout(pump, 0); // yield so cancels and new requests get in
}
