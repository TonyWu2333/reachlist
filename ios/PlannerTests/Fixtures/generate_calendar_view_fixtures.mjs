#!/usr/bin/env node
// T-15 / M-10 日历与日程列表契约夹具生成器。
//
// oracle：
// · 真实源码 src/lib/date.js / repeat.js / quadrant.js / i18n-en/calendar.js
//   （直接 import，不复制、不改写；语言用 i18n.lang 切换）
// · CalendarView.vue / MonthGrid.vue / store.js 里的 computed 因依赖 Vue 响应式与 DOM，
//   在下方按源码逐行复刻（每段标注源文件行号），函数体与上游保持一致。
//
// 用法：node ios/PlannerTests/Fixtures/generate_calendar_view_fixtures.mjs
// 输出：ios/PlannerTests/Fixtures/calendar_view_fixtures.json
// 所有日期显式注入（TODAY），不读系统当前时间。

import { writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../../..');
const importFromRoot = (p) => import(pathToFileURL(resolve(root, p)).href);

const date = await importFromRoot('src/lib/date.js');
const rep = await importFromRoot('src/lib/repeat.js');
const quad = await importFromRoot('src/lib/quadrant.js');
const enCalendar = (await importFromRoot('src/lib/i18n-en/calendar.js')).default;
const { i18n } = await importFromRoot('src/lib/i18n.js');

const BASELINE = '97a7c4c17602327a42d30110806a6a1e6fa0e798';
const TODAY = '2026-11-13';
const ROW_H = 54;

const mkTask = (o = {}) => ({
  id: 't1', title: '示例任务', note: '', date: '', time: '',
  important: false, urgent: false, done: false, dropped: false,
  createdAt: 1700000000000, doneAt: null, repeat: '',
  doneDates: [], skipDates: [], remind: null, parentId: '', updatedAt: 1700000000000,
  ...o,
});

const TASKS = [
  mkTask({ id: 'open-am', title: '晨会', date: '2026-11-13', time: '09:00', important: true, urgent: true }),
  mkTask({ id: 'open-no-time', title: '整理资料', date: '2026-11-13', important: true }),
  mkTask({ id: 'done-am', date: '2026-11-13', time: '08:00', done: true, doneAt: 1700000001000 }),
  mkTask({ id: 'dropped', date: '2026-11-13', done: true, dropped: true }),
  mkTask({ id: 'overdue-1', date: '2026-11-10', time: '08:00', urgent: true }),
  mkTask({ id: 'overdue-2', date: '2026-11-08' }),
  mkTask({ id: 'future', date: '2026-11-20', time: '10:00' }),
  mkTask({ id: 'daily', date: '2026-11-01', repeat: 'd1', time: '07:30', doneDates: ['2026-11-13'] }),
  mkTask({ id: 'weekly', date: '2026-11-01', repeat: 'w1:135', time: '18:00' }),
  mkTask({ id: 'monthly', date: '2026-01-31', repeat: 'm1' }),
  mkTask({ id: 'child', date: '2026-11-13', parentId: 'open-am' }),
  mkTask({ id: 'no-date' }),
];

// ---- CalendarView.vue:28-40 geom（用 date.js 真实函数） ----
const geom = (d) => {
  const p = date.parseYmd(d);
  const y = p.getFullYear(), m = p.getMonth();
  const offset = (new Date(y, m, 1).getDay() + 6) % 7;
  return {
    date: d, year: y, month0: m,
    rows: Math.ceil((offset + new Date(y, m + 1, 0).getDate()) / 7),
    row: Math.floor((offset + p.getDate() - 1) / 7),
  };
};
// ---- MonthGrid.vue:17-40 rows ----
const monthGridRows = (year, month0) => {
  const offset = (new Date(year, month0, 1).getDay() + 6) % 7;
  const days = new Date(year, month0 + 1, 0).getDate();
  const count = Math.ceil((offset + days) / 7);
  const out = [];
  for (let r = 0; r < count; r++) {
    const row = [];
    for (let c = 0; c < 7; c++) {
      const d = new Date(year, month0, 1 - offset + r * 7 + c);
      const key = date.ymd(d);
      row.push({ key, day: d.getDate(), out: d.getMonth() !== month0, today: key === TODAY, weekend: c >= 5, weekdayIndex: d.getDay() });
    }
    out.push(row);
  }
  return out;
};
// ---- CalendarView.vue:42-47 neighbour ----
const neighbour = (selected, mode, n) => {
  if (mode === 'week') return date.addDays(selected, 7 * n);
  const p = date.parseYmd(selected);
  const first = date.ymd(new Date(p.getFullYear(), p.getMonth() + n, 1));
  return TODAY.startsWith(first.slice(0, 7)) ? TODAY : first;
};
// ---- CalendarView.vue:48-58 panes / pageIndex / slots ----
const mod3 = (k) => ((k % 3) + 3) % 3;
const pageIndex = (p, mode) => mode === 'week'
  ? Math.floor(date.diffDays(date.mondayOf(p.date), '2000-01-03') / 7)
  : p.year * 12 + p.month0;
const buildSlots = (selected, mode) => {
  const panes = [-1, 0, 1].map((n) => geom(n ? neighbour(selected, mode, n) : selected));
  const slots = [];
  panes.forEach((p, i) => { slots[mod3(pageIndex(p, mode))] = { geometry: p, n: i - 1 }; });
  // 连续三页的 pageIndex mod 3 必定覆盖 0/1/2，不会留空洞。
  return { panes, slots: slots.map((s, slot) => ({ slot, n: s.n, date: s.geometry.date })) };
};
// ---- CalendarView.vue:66-88 dots ----
const computeDots = (tasks, panes) => {
  const byDay = new Map();
  const days = new Set();
  const add = (d, t) => { if (!byDay.has(d)) byDay.set(d, []); byDay.get(d).push(t); };
  for (const p of panes) {
    const start = date.mondayOf(`${p.year}-${String(p.month0 + 1).padStart(2, '0')}-01`);
    for (let i = 0; i < 42; i++) days.add(date.addDays(start, i));
  }
  for (const t of tasks) {
    if (t.repeat) {
      for (const d of days) if (rep.occursOn(t, d)) add(d, { ...t, done: t.doneDates.includes(d) });
    } else if (t.date) add(t.date, t);
  }
  const m = {};
  for (const [d, list] of byDay) {
    const open = list.filter((t) => !t.done).map(quad.quadrantOf).sort();
    m[d] = open.length ? open.slice(0, 3).map((q) => `q${q}`) : ['done'];
  }
  return m;
};
// ---- store.js:151-152 tasksOn（flatMap 复刻） ----
const tasksOn = (tasks, d) => tasks.flatMap((t) => (t.repeat
  ? (rep.occursOn(t, d) ? [rep.instanceOf(t, d)] : [])
  : (t.date === d ? [t] : [])));
const countsAsDone = (t) => t.done && !t.dropped;   // store.js:182
// ---- CalendarView.vue:229-263 ----
const dayTasks = (d) => tasksOn(TASKS, d).sort(quad.byTime);
const overdue = (selected) => selected === TODAY
  ? TASKS.filter((t) => !t.repeat && !t.done && t.date && t.date < TODAY).sort(quad.byDate)
  : [];
const progress = (list) => {
  const total = list.filter((t) => !t.dropped).length;
  const done = list.filter(countsAsDone).length;
  return { done, total, ratio: total ? done / total : 0 };
};
const doneSummary = (list) => {
  const doneTasks = list.filter((t) => t.done);
  const ringDone = list.filter(countsAsDone).length;
  return { done: ringDone, dropped: doneTasks.length - ringDone };
};

const f = {
  meta: { baseline_commit: BASELINE, generator: 'ios/PlannerTests/Fixtures/generate_calendar_view_fixtures.mjs', today: TODAY, rowH: ROW_H,
          timezone: Intl.DateTimeFormat().resolvedOptions().timeZone },
  tasks: TASKS,   // Swift 侧用 JSONDecoder 解成 [PlannerTask]，作为全部用例的输入
  geom: [], monthGrid: [], neighbour: [], slots: [], drop: [], shiftOf: [],
  dots: [], todayColumn: [], heading: [], weekdayHeader: [], monthName: [], lunarYearLabel: [],
  dayTasks: [], overdue: [], progress: [], doneSummary: [], split: [], byTime: [], byDate: [], quadrantOf: [],
  strings: [],
};

const DATES = ['2024-02-29', '2026-01-01', '2026-01-31', '2026-02-01', '2026-11-01', '2026-11-09',
               '2026-11-13', '2026-11-15', '2026-12-01', '2026-12-31', '2027-01-05', '2028-02-29'];

for (const d of DATES) f.geom.push({ date: d, expected: geom(d) });

for (const [year, month0] of [[2024, 1], [2026, 0], [2026, 1], [2026, 10], [2026, 11], [2027, 0], [2028, 1]]) {
  f.monthGrid.push({ year, month0, expected: monthGridRows(year, month0) });
}

for (const mode of ['month', 'week']) {
  for (const selected of ['2026-11-13', '2026-01-31', '2026-12-31', '2024-02-29']) {
    for (const n of [-1, 1]) f.neighbour.push({ selected, mode, n, expected: neighbour(selected, mode, n) });
    const { panes, slots } = buildSlots(selected, mode);
    f.slots.push({ selected, mode, expected: slots });
    f.drop.push({ selected, mode, rows: geom(selected).rows, rowH: ROW_H,
                  expected: mode === 'month' ? (geom(selected).rows - 1) * ROW_H : 0 });
    for (const p of panes) {
      f.shiftOf.push({ date: p.date, mode, row: p.row, rowH: ROW_H,
                       expected: mode === 'month' ? 0 : -p.row * ROW_H });
    }
    const t = TODAY;
    const visible = mode === 'week' ? date.mondayOf(t) === date.mondayOf(selected) : t.slice(0, 7) === selected.slice(0, 7);
    f.todayColumn.push({ selected, mode, expected: visible ? (date.parseYmd(t).getDay() + 6) % 7 : -1 });
    const dots = computeDots(TASKS, panes);
    f.dots.push({ selected, mode, expected: dots });
  }
}

// heading + 星期表头 + 月份名 + 干支年：中英两套
for (const lang of ['zh', 'en']) {
  i18n.lang = lang;
  const isEn = lang === 'en';
  for (const d of DATES) {
    const rel = date.dateLabel(d);
    const md = date.monthDay(date.parseYmd(d));
    const n = date.diffDays(d, TODAY);
    const isRel = n >= -1 && n <= (isEn ? 1 : 2);
    const weekday = date.weekdayName(date.parseYmd(d).getDay());
    const full = date.dayInfo(d).full;
    const parts = [isRel && md, weekday, full].filter(Boolean);
    f.heading.push({ date: d, lang, expected: { title: isRel ? rel : md, sub: parts.join(' · ') } });
  }
  f.weekdayHeader.push({ lang, expected: [1, 2, 3, 4, 5, 6, 0].map((d) => date.weekdayName(d, true)) });
  f.monthName.push({ lang, expected: Array.from({ length: 12 }, (_, m) => date.monthName(m)) });
  for (const y of [1900, 2024, 2025, 2026, 2027, 2100]) {
    f.lunarYearLabel.push({ year: y, lang, expected: date.lunarYearLabel(y) });
  }
}
i18n.lang = 'zh';

for (const d of DATES) {
  const list = dayTasks(d);
  f.dayTasks.push({ date: d, expected: list.map((t) => ({ id: t.id, date: t.date, done: t.done, occ: t.occ ?? '' })) });
  f.overdue.push({ date: d, expected: overdue(d).map((t) => t.id) });
  f.progress.push({ date: d, expected: progress(list) });
  f.doneSummary.push({ date: d, expected: doneSummary(list) });
  f.split.push({ date: d, expected: { open: list.filter((t) => !t.done).map((t) => t.id), done: list.filter((t) => t.done).map((t) => t.id) } });
}

f.quadrantOf.push({ tasks: TASKS.map((t) => ({ id: t.id, important: t.important, urgent: t.urgent })),
                    expected: TASKS.map((t) => ({ id: t.id, q: quad.quadrantOf(t) })) });
f.byTime.push({ expected: TASKS.slice().sort(quad.byTime).map((t) => t.id) });
f.byDate.push({ expected: TASKS.slice().sort(quad.byDate).map((t) => t.id) });

// 词条：只比对字符串值（函数值含 plural / lowerRel，由 Swift 侧调用点另行组装）
for (const [zh, en] of Object.entries(enCalendar)) {
  if (typeof en === 'string') f.strings.push({ zh, expected: en });
}

const out = resolve(root, 'ios/PlannerTests/Fixtures/calendar_view_fixtures.json');
writeFileSync(out, JSON.stringify(f) + '\n');
console.log('wrote ios/PlannerTests/Fixtures/calendar_view_fixtures.json');
for (const k of Object.keys(f)) if (Array.isArray(f[k])) console.log(`  ${k}: ${f[k].length}`);
