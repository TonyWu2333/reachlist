// node preview.mjs t1 t2 … → build/preview/<t>.jpg (for checking keyframes)
import { chromium } from 'playwright-core';
import fs from 'node:fs';
const dir = new URL('./build/preview/', import.meta.url).pathname;
fs.mkdirSync(dir, { recursive: true });
const b = await chromium.launch(process.env.EXE ? { executablePath: process.env.EXE } : {});
const p = await b.newPage({ viewport: { width: 1920, height: 1080 } });
p.on('pageerror', (e) => console.log('pageerror', e.message));
await p.goto('file://' + new URL('./index.html', import.meta.url).pathname + (process.env.PROMO_LANG ? '?lang=' + process.env.PROMO_LANG : ''));
for (let i = 0; i < 200 && !(await p.evaluate(() => !!window.READY)); i++) await p.waitForTimeout(100);
for (const t of process.argv.slice(2)) { await p.evaluate((t) => window.seekTo(t), +t); await p.screenshot({ path: `${dir}${t}.jpg`, type: 'jpeg', quality: 85 }); }
await b.close();
console.log('ok');
