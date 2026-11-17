// App screens for the promo (demo data). Needs the dev server: npm run dev (port 5173).
// Writes build/shots/*.png and build/shots/meta.js (tap positions in CSS px of the 390×844 page).
// PROMO_LANG=zh → Chinese UI and data in build/shots-zh/.
import { chromium } from 'playwright-core';
import fs from 'node:fs';
const ZH = process.env.PROMO_LANG === 'zh';
const out = new URL(ZH ? './build/shots-zh/' : './build/shots/', import.meta.url).pathname;
const ZH_TITLES = {
  'Morning run, 5 km': '晨跑 5 公里', 'Learn 30 new words': '背 30 个单词', 'Weekly product sync': '产品周会', "Bring this week's progress": '带上本周进度',
  'Submit quarterly expenses': '提交季度报销', 'Review design mockups': '评审设计稿', 'Gym: back + shoulders': '健身：背 + 肩', 'Read a chapter of CS:APP': '读一章《深入理解计算机系统》',
  'Write weekly report': '写周报', 'Buy coffee beans': '买咖啡豆', 'Book a dentist appointment': '预约牙医', "Draft next quarter's OKRs": '起草下季度 OKR', 'Call Mom': '给妈妈打电话',
  'Ship v1.0': '发布 v1.0', 'Team lunch': '团队午餐', 'Renew the domain': '续费域名', 'Learn some Rust': '学点 Rust', 'Tidy the bookshelf': '整理书架',
  'Reply to emails': '回复邮件', 'Pay rent': '交房租', 'Call the client': '给客户打电话',
};
const L = (s) => (ZH && ZH_TITLES[s]) || s;
fs.mkdirSync(out, { recursive: true });
const URL_ = process.env.URL || 'http://localhost:5173/';
const fmt = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const day = (n) => { const d = new Date(); d.setDate(d.getDate() + n); return fmt(d); };
let i = 0;
const T = (title, o = {}) => ({ id: 't' + ++i, title: L(title), note: '', date: day(0), time: '', important: false, urgent: false, done: false, dropped: false, createdAt: Date.now() - i * 1000, doneAt: null, repeat: '', doneDates: [], skipDates: [], remind: null, parentId: '', ...o, note: L(o.note || '') });
const tasks = [
  T('Morning run, 5 km', { time: '07:00', repeat: 'd1', date: day(-20), doneDates: Array.from({ length: 9 }, (_, k) => day(-k - 1)), important: true }),
  T('Learn 30 new words', { time: '08:30', repeat: 'd1', date: day(-30), doneDates: Array.from({ length: 14 }, (_, k) => day(-k - 1)) }),
  T('Weekly product sync', { time: '10:00', important: true, urgent: true, note: "Bring this week's progress" }),
  T('Submit quarterly expenses', { time: '12:00', urgent: true }),
  T('Review design mockups', { time: '15:30', important: true }),
  T('Gym: back + shoulders', { time: '19:30', repeat: 'w1:135', date: day(-14), doneDates: [day(-2), day(-4), day(-7)] }),
  T('Read a chapter of CS:APP', { time: '22:00', repeat: 'w1:12345', date: day(-14), doneDates: [day(-1), day(-2), day(-3)] }),
  T('Write weekly report', { done: true, doneAt: Date.now() - 3600e3 }),
  T('Buy coffee beans', { done: true, doneAt: Date.now() - 7200e3 }),
  T('Book a dentist appointment', { date: day(1), time: '14:00', urgent: true }),
  T("Draft next quarter's OKRs", { date: day(2), important: true }),
  T('Call Mom', { date: day(2), time: '20:00', important: true }),
  T('Ship v1.0', { date: day(3), time: '11:00', important: true, urgent: true }),
  T('Team lunch', { date: day(3), time: '12:30' }),
  T('Renew the domain', { date: day(-1), urgent: true }),
  T('Learn some Rust', { date: '', important: true }),
  T('Tidy the bookshelf', { date: day(4) }),
  T('Reply to emails', { urgent: true }),
  T('Pay rent', { date: day(-10), repeat: 'm1', time: '09:00' }),
];
const agentTask = T('Call the client', { date: day(1), time: '09:00', important: true, urgent: true, createdAt: Date.now() });

const meta = {};
const browser = await chromium.launch(process.env.EXE ? { executablePath: process.env.EXE } : {});
async function page(list) {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, locale: ZH ? 'zh-CN' : 'en-US' });
  await ctx.addInitScript((d) => {
    localStorage.setItem('CapacitorStorage.planner-data', JSON.stringify(d.data));
    localStorage.setItem('CapacitorStorage.planner-settings', JSON.stringify({ lang: d.lang, showLunar: false, showHoliday: false, remindOn: true, defaultRemind: 0 }));
  }, { data: { version: 1, tasks: list }, lang: ZH ? 'zh' : 'en' });
  const p = await ctx.newPage();
  await p.goto(URL_);
  await p.waitForTimeout(1500);
  return p;
}
const shot = (p, name) => p.screenshot({ path: `${out}${name}.png` });
const center = async (loc) => { const b = await loc.boundingBox(); return [Math.round(b.x + b.width / 2), Math.round(b.y + b.height / 2)]; };
const tab = async (p, i) => { await p.locator('.tab').nth(i).click(); await p.waitForTimeout(900); };
async function cellAfterToday(p, n) {
  const cells = p.locator('.view.active .mcell');
  const count = await cells.count();
  for (let k = 0; k < count; k++) if (await cells.nth(k).evaluate((e) => e.classList.contains('today'))) return cells.nth(k + n);
}
async function tapCell(p, n, name) {
  const c = await cellAfterToday(p, n);
  meta[name] = await center(c);
  await c.click(); await p.waitForTimeout(800);
  await shot(p, name);
}

let p = await page(tasks);
await shot(p, 'cal_0');
await tapCell(p, 1, 'cal_1');
await tapCell(p, 2, 'cal_2');
await tapCell(p, 3, 'cal_3');

// quick add, one frame per typed character
await p.goto(URL_); await p.waitForTimeout(1300);
meta.fab = await center(p.locator('.view.active .fab'));
await p.click('.view.active .fab'); await p.waitForTimeout(900);
const text = ZH ? '整理本周复盘笔记' : 'Weekly review';
await shot(p, 'quick_0');
for (let k = 1; k <= text.length; k++) { await p.keyboard.type(text[k - 1]); await p.waitForTimeout(120); await shot(p, `quick_${k}`); }
meta.quickFrames = text.length;

await p.goto(URL_); await p.waitForTimeout(1300);
await tab(p, 1); await shot(p, 'quad_all');
for (const [label, name] of [[ZH ? '今天' : 'Today', 'quad_today'], [ZH ? '本周' : 'This week', 'quad_week']]) {
  const b = p.locator('.view.active .seg button', { hasText: new RegExp(`^${label}$`) });
  meta[name] = await center(b);
  await b.click(); await p.waitForTimeout(800); await shot(p, name);
}

await tab(p, 2); await shot(p, 'routine_before');
const chk = p.locator('.view.active .trow', { hasText: L('Learn 30 new words') }).locator('.check').first();
meta.routine_after = await center(chk);
await chk.click(); await p.waitForTimeout(1200); await shot(p, 'routine_after');

await tab(p, 0);
const c1 = await cellAfterToday(p, 1);
await c1.click(); await p.waitForTimeout(800); await shot(p, 'agent_before');
await p.context().close();

p = await page([...tasks, agentTask]);
await (await cellAfterToday(p, 1)).click(); await p.waitForTimeout(800);
meta.agentRow = await center(p.locator('.view.active .trow', { hasText: L('Call the client') }).first());
await shot(p, 'agent_after');
await browser.close();

meta.tomorrow = day(1);
fs.writeFileSync(`${out}meta.js`, 'window.META = ' + JSON.stringify(meta) + ';\n');
console.log('shots:', fs.readdirSync(out).length, meta);
