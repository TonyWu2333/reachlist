// node cover.mjs → out/cover-{en,zh}.png (1920×1080) and ../docs/promo/video-{en,zh}.jpg (README thumbnails with a play button)
// Needs build/shots and build/shots-zh.
import { chromium } from 'playwright-core';
import fs from 'node:fs';
fs.mkdirSync(new URL('./out/', import.meta.url).pathname, { recursive: true });
const b = await chromium.launch(process.env.EXE ? { executablePath: process.env.EXE } : {});
fs.mkdirSync(new URL('../docs/promo/', import.meta.url).pathname, { recursive: true });
const shots = [];
for (const lang of ['en', 'zh']) {
  shots.push([`?lang=${lang}`, `./out/cover-${lang}.png`, {}]);
  shots.push([`?lang=${lang}&play`, `../docs/promo/video-${lang}.jpg`, { type: 'jpeg', quality: 82 }]);
}
for (const [q, out, opt] of shots) {
  const p = await b.newPage({ viewport: { width: 1920, height: 1080 } });
  await p.goto('file://' + new URL('./cover.html', import.meta.url).pathname + q);
  for (let i = 0; i < 100 && !(await p.evaluate(() => !!window.READY)); i++) await p.waitForTimeout(100);
  await p.screenshot({ path: new URL(out, import.meta.url).pathname, ...opt });
  await p.close();
}
await b.close();
console.log('wrote out/cover-*.png, docs/promo/video-*.jpg');
