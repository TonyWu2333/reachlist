// node render.mjs <frames_dir> [workers] [fps] — renders index.html frame by frame (JPEG)
import { chromium } from 'playwright-core';
import fs from 'node:fs';
const [out = 'build/frames', W = 4, FPS = 30] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const b = await chromium.launch(process.env.EXE ? { executablePath: process.env.EXE } : {});
let total = 0, done = 0;
async function worker(w, n) {
  const p = await b.newPage({ viewport: { width: 1920, height: 1080 } });
  await p.goto('file://' + new URL('./index.html', import.meta.url).pathname + (process.env.PROMO_LANG ? '?lang=' + process.env.PROMO_LANG : ''));
  for (let i = 0; i < 200 && !(await p.evaluate(() => !!window.READY)); i++) await p.waitForTimeout(100);
  total = Math.ceil((await p.evaluate(() => window.DURATION)) * FPS);
  for (let f = w; f < total; f += n) {
    if (f / FPS < +(process.env.FROM || 0)) continue; // FROM=27 re-renders only from 27 s on
    await p.evaluate((t) => window.seekTo(t), f / FPS);
    await p.screenshot({ path: `${out}/${String(f).padStart(5, '0')}.jpg`, type: 'jpeg', quality: 92 });
    if (++done % 200 === 0) console.log(`${done}/${total}`);
  }
}
await Promise.all(Array.from({ length: +W }, (_, w) => worker(w, +W)));
await b.close();
console.log('done', total, 'frames');
