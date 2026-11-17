// node cover.mjs → out/cover-en.png, out/cover-zh.png (1920×1080; needs build/shots and build/shots-zh)
import { chromium } from 'playwright-core';
import fs from 'node:fs';
fs.mkdirSync(new URL('./out/', import.meta.url).pathname, { recursive: true });
const b = await chromium.launch(process.env.EXE ? { executablePath: process.env.EXE } : {});
for (const lang of ['en', 'zh']) {
  const p = await b.newPage({ viewport: { width: 1920, height: 1080 } });
  await p.goto('file://' + new URL('./cover.html', import.meta.url).pathname + '?lang=' + lang);
  for (let i = 0; i < 100 && !(await p.evaluate(() => !!window.READY)); i++) await p.waitForTimeout(100);
  await p.screenshot({ path: new URL(`./out/cover-${lang}.png`, import.meta.url).pathname });
  await p.close();
}
await b.close();
console.log('wrote out/cover-en.png, out/cover-zh.png');
