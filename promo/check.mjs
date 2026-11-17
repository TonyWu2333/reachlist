// Flicker check: render state must not depend on seek order, and intro/scene text must be hidden outside its scene.
// node check.mjs   (uses EXE like render.mjs)
import { chromium } from 'playwright-core';
const FPS = 30, W = 6;
const SEL = ['#logo', '#title', '#subtitle', '#tagline', '#repo', '#phone', '#calendar', '#quick', '#matrix', '#routine', '#agent', '#term', '#hl', '#finger', '#packet'];
const b = await chromium.launch(process.env.EXE ? { executablePath: process.env.EXE } : {});
async function pass(frames) {
  const p = await b.newPage({ viewport: { width: 1920, height: 1080 } });
  await p.goto('file://' + new URL('./index.html', import.meta.url).pathname + (process.env.PROMO_LANG ? '?lang=' + process.env.PROMO_LANG : ''));
  for (let i = 0; i < 200 && !(await p.evaluate(() => !!window.READY)); i++) await p.waitForTimeout(100);
  const res = await p.evaluate(({ frames, SEL, FPS }) => {
    const op = (el) => { let o = 1; for (; el && el !== document.body; el = el.parentElement) o *= +getComputedStyle(el).opacity; return o; };
    const els = SEL.map((s) => document.querySelector(s));
    return frames.map((f) => { window.seekTo(f / FPS); return [f, els.map((e) => Math.round(op(e) * 100) / 100)]; });
  }, { frames, SEL, FPS });
  await p.close();
  return res;
}
const total = await (async () => { const p = await b.newPage(); await p.goto('file://' + new URL('./index.html', import.meta.url).pathname + (process.env.PROMO_LANG ? '?lang=' + process.env.PROMO_LANG : '')); for (let i = 0; i < 200 && !(await p.evaluate(() => !!window.READY)); i++) await p.waitForTimeout(100); const T = await p.evaluate(() => ({ n: Math.ceil(window.DURATION * 30), scenes: window.TIMING.scenes })); await p.close(); return T; })();
const all = Array.from({ length: total.n }, (_, i) => i);
const seq = new Map((await pass(all)).map(([f, v]) => [f, v]));
const strided = new Map((await Promise.all(Array.from({ length: W }, (_, w) => pass(all.filter((f) => f % W === w))))).flat().map(([f, v]) => [f, v]));
let diffs = 0;
for (const f of all) {
  const a = seq.get(f), c = strided.get(f);
  a.forEach((v, i) => { if (Math.abs(v - c[i]) > 0.02) { if (diffs++ < 10) console.log(`order-dependent: ${SEL[i]} at ${(f / FPS).toFixed(2)}s  seq ${v} vs strided ${c[i]}`); } });
}
// visible outside its window?
const S = Object.fromEntries(total.scenes.map((s) => [s.id, s]));
const windows = { '#subtitle': [0, S.calendar.start], '#calendar': [S.calendar.start, S.quick.start + 0.4], '#quick': [S.quick.start, S.matrix.start + 0.4],
  '#matrix': [S.matrix.start, S.routine.start + 0.4], '#routine': [S.routine.start, S.agent.start + 0.4], '#agent': [S.agent.start, S.outro.start + 0.4], '#tagline': [S.outro.start, 1e9] };
let leaks = 0;
for (const [sel, [t0, t1]] of Object.entries(windows)) {
  const i = SEL.indexOf(sel);
  for (const f of all) { const t = f / FPS; if ((t < t0 || t > t1) && seq.get(f)[i] > 0.02) { if (leaks++ < 10) console.log(`leak: ${sel} visible (${seq.get(f)[i]}) at ${t.toFixed(2)}s, window ${t0.toFixed(2)}–${t1.toFixed(2)}`); } }
}
console.log(`${total.n} frames: ${diffs} order-dependent values, ${leaks} out-of-window frames`);
await b.close();
process.exit(diffs || leaks ? 1 : 0);
