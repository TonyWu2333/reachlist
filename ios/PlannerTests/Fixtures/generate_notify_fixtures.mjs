#!/usr/bin/env node
// T-11 / M-07 提醒排程黄金夹具生成器。
//
// oracle 全部来自 baseline_commit 97a7c4c 的真实源码 src/lib/notify.js（115 行）：
// · planReminders / remindLabel / remindShort / toNotification / idOf 的函数体**逐字未改**；
//   notify.js 顶层依赖 vue / Capacitor / store.js / repeat.js / date.js / quadrant.js / i18n.js，
//   /tmp 运行副本只替换 4 行环境依赖 import 为 stub、把 4 行相对 import 改成绝对 file URL，
//   并在末尾追加 1 行 export（toNotification / idOf 上游未导出，需观察其真实输出）。
// · 日期 / 重复 / 象限 / 本地化都走项目内真实模块（绝对路径 import 命中同一模块实例，
//   所以 i18n.lang 的切换对 QUADRANTS getter 与 repeatLabel 同时生效）。
// · 文案中文原文为键，英文值来自 src/lib/i18n-en.js:core 的真实 t() 输出。
//
// 每个 planCases 自带 tz，生成器用 `TZ=<tz>` 子进程逐时区计算（JS new Date 走本地时区），
// Swift harness 按 case 的 tz 注入 TimeZone 复现，因此一份夹具即可跨 5 时区验证。
//
// 生成命令：node ios/PlannerTests/Fixtures/generate_notify_fixtures.mjs
// 输出：ios/PlannerTests/Fixtures/notify_fixtures.json

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { execFileSync } from 'node:child_process';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../../..');
const abs = (p) => pathToFileURL(resolve(root, p)).href;
const BASELINE = '97a7c4c17602327a42d30110806a6a1e6fa0e798';
const TZS = ['Asia/Shanghai', 'America/New_York', 'Europe/London', 'Pacific/Auckland', 'Asia/Kolkata'];

// ---- 构造 /tmp 运行副本 ----
const src = readFileSync(resolve(root, 'src/lib/notify.js'), 'utf8');
const replacements = [
  ["import { reactive, watch } from 'vue';", 'const reactive = (x) => x; const watch = () => {};'],
  ["import { Capacitor } from '@capacitor/core';", 'const Capacitor = { isNativePlatform: () => true };'],
  ["import { LocalNotifications } from '@capacitor/local-notifications';",
   'const LocalNotifications = globalThis.__t11_LN;'],
  ["import { state } from './store.js';", 'const state = globalThis.__t11_state;'],
  ["import { occursOn, repeatLabel } from './repeat.js';",
   `import { occursOn, repeatLabel } from '${abs('src/lib/repeat.js')}';`],
  ["import { ymd, addDays } from './date.js';",
   `import { ymd, addDays } from '${abs('src/lib/date.js')}';`],
  ["import { QUADRANTS, quadrantOf } from './quadrant.js';",
   `import { QUADRANTS, quadrantOf } from '${abs('src/lib/quadrant.js')}';`],
  ["import { t as tr } from './i18n.js';", `import { t as tr } from '${abs('src/lib/i18n.js')}';`],
];
let patched = src;
for (const [from, to] of replacements) {
  if (!patched.includes(from)) throw new Error(`替换未命中：${from}`);
  patched = patched.replace(from, to);
}
const changed = src.split('\n').filter((l, i) => l !== patched.split('\n')[i]).length;
if (changed !== replacements.length) throw new Error(`运行副本改动 ${changed} 行，预期 ${replacements.length} 行`);
patched += '\nexport { toNotification, idOf };\n';
const oracleDir = '/tmp/t11_oracle';
mkdirSync(oracleDir, { recursive: true });
const oraclePath = resolve(oracleDir, 'notify.mjs');
writeFileSync(oraclePath, patched);

globalThis.__t11_state = { settings: { remindOn: true }, tasks: [] };
globalThis.__t11_LN = {
  checkPermissions: async () => ({ display: 'granted' }),
  requestPermissions: async () => ({ display: 'granted' }),
  getPending: async () => ({ notifications: [] }),
  cancel: async () => {},
  schedule: async () => {},
  createChannel: async () => {},
  addListener: () => {},
};
const notify = await import(pathToFileURL(oraclePath).href);
const { i18n, t } = await import(abs('src/lib/i18n.js'));

// ---- 任务构造器：17 字段与 store.js:normalizeTask 输出键序一致 ----
const mkTask = (o = {}) => ({
  id: 'a1', title: '开会', note: '', date: '2026-11-14', time: '09:00',
  important: false, urgent: false, done: false, dropped: false,
  createdAt: 1700000000000, doneAt: null, repeat: '', doneDates: [], skipDates: [],
  remind: 0, parentId: '', updatedAt: 1700000000000, ...o,
});

// ---- 1) 提醒文案（中英两套，逐字来自 t()） ----
const labels = [];
for (const m of [null, 0, 5, 15, 30, 60, 120]) {
  const out = { m };
  for (const lang of ['zh', 'en']) {
    i18n.lang = lang;
    out[lang + 'Label'] = notify.remindLabel(m);
    out[lang + 'Short'] = notify.remindShort(m);
  }
  labels.push(out);
}
i18n.lang = 'zh';

// ---- 2) idOf：UTF-16 哈希（含中文 / emoji 代理对 / Int32 边界） ----
const idKeys = [
  'a1|2026-11-14', 'x|2026-01-01', '', '任务A|2026-11-14',
  '😀|2026-11-14', 'a'.repeat(40) + '|2026-11-14',
  'zzzzzz|2026-12-31', '0|1970-01-01',
];
const idOf = idKeys.map((key) => ({ key, expected: notify.idOf(key) }));

// ---- 3) planReminders 语料（时区无关定义，at 由各时区本地时刻算出） ----
const planSets = [
  {
    name: 'basic-filter',
    // 本地 2026-11-14 12:00:00；at 固定用该时刻的 epoch，交由各时区子进程重算
    now: '2026-11-14T12:00:00',
    tasks: [
      mkTask({ id: 't-once', title: '一次性', date: '2026-11-14', time: '18:00', remind: 0 }),
      mkTask({ id: 't-past', title: '已过去', date: '2026-11-14', time: '09:00', remind: 0 }),
      mkTask({ id: 't-noremind', title: '不提醒', remind: null }),
      mkTask({ id: 't-notime', title: '无时间', time: '', remind: 5 }),
      mkTask({ id: 't-nodate', title: '无日期', date: '', remind: 5 }),
      mkTask({ id: 't-done', title: '已完成', done: true, remind: 0 }),
      mkTask({ id: 't-tomorrow', title: '明天', date: '2026-11-15', time: '08:30', remind: 15 }),
    ],
  },
  {
    name: 'repeat-d1-window',
    now: '2026-11-14T12:00:00',
    tasks: [
      mkTask({ id: 'r-d1', title: '每天', date: '2026-11-01', time: '07:00',
               repeat: 'd1', remind: 5, doneDates: ['2026-11-15', '2026-11-17'] }),
    ],
  },
  {
    name: 'repeat-weekly-and-until',
    now: '2026-11-14T12:00:00',
    tasks: [
      mkTask({ id: 'r-w', title: '工作日', date: '2026-11-01', time: '09:30',
               repeat: 'w1:12345', remind: 0, skipDates: ['2026-11-18'] }),
      mkTask({ id: 'r-m', title: '每月', date: '2026-10-15', time: '10:00', repeat: 'm1' }),
      mkTask({ id: 'r-y', title: '每年', date: '2020-12-20', time: '20:00', repeat: 'y1' }),
      mkTask({ id: 'r-until', title: '到月底', date: '2026-11-01', time: '11:00',
               repeat: 'd1~2026-11-20', remind: 30 }),
    ],
  },
  {
    name: 'max-60-clamp',
    now: '2026-11-01T00:00:00',
    // 3 条 d1 × 31 天 = 93 条候选，验证按时间排序后只留前 60
    tasks: ['A', 'B', 'C'].map((s, i) => mkTask({
      id: 'cap-' + s, title: '上限' + s, date: '2026-11-01', time: `0${7 + i}:00`,
      repeat: 'd1', remind: 0,
    })),
  },
  {
    name: 'remind-crosses-midnight',
    now: '2026-11-14T23:50:00',
    tasks: [
      mkTask({ id: 'x-1', title: '次日凌晨', date: '2026-11-15', time: '00:10', remind: 60 }),
      mkTask({ id: 'x-2', title: '今晚', date: '2026-11-14', time: '23:59', remind: 0 }),
      mkTask({ id: 'x-3', title: '已过提醒点', date: '2026-11-15', time: '00:30', remind: 60 }),
    ],
  },
  {
    name: 'quadrant-and-repeat-flags',
    now: '2026-11-14T12:00:00',
    tasks: [1, 2, 3, 4].map((q) => mkTask({
      id: 'q' + q, title: '象限' + q, date: '2026-11-16', time: '14:00', remind: 30,
      important: q <= 2, urgent: q === 1 || q === 3,
      repeat: q % 2 ? 'd2' : '',
    })),
  },
  {
    name: 'dst-spring-forward',
    // America/New_York 2026-03-08 02:00→03:00，02:30 是不存在的本地时间
    now: '2026-03-07T12:00:00',
    tasks: [
      mkTask({ id: 'dst-gap', title: '跳跃时刻', date: '2026-03-08', time: '02:30', remind: 0 }),
      mkTask({ id: 'dst-ok', title: '正常时刻', date: '2026-03-08', time: '09:00', remind: 0 }),
    ],
  },
  {
    name: 'empty',
    now: '2026-11-14T12:00:00',
    tasks: [],
  },
];

// 每个时区用独立子进程计算 at（JS 的 new Date 依赖进程 TZ）。子进程只 import 同一份
// /tmp 运行副本并调用 planReminders，不重复生成夹具，也不改任何函数体。
const computeScript = `
import { readFileSync } from 'node:fs';
const m = await import(${JSON.stringify(pathToFileURL(oraclePath).href)});
const { sets } = JSON.parse(readFileSync(0, 'utf8'));
const cases = [];
for (const s of sets) {
  const now = new Date(s.now);
  const plan = m.planReminders(s.tasks, now);
  cases.push({
    name: s.name,
    nowMs: now.getTime(),
    tasks: s.tasks,
    taskCount: s.tasks.length,
    expected: plan.map((p) => ({ at: p.at, taskId: p.task.id, date: p.date })),
  });
}
process.stdout.write(JSON.stringify(cases));
`;
const planCases = [];
for (const tz of TZS) {
  const payload = JSON.stringify({ sets: planSets, tz });
  const raw = execFileSync(process.execPath, ['--input-type=module', '-e', computeScript],
    { input: payload, env: { ...process.env, TZ: tz }, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  for (const c of JSON.parse(raw)) planCases.push({ ...c, tz });
}

// ---- 4) toNotification（中英两套） ----
const notiTasks = [
  mkTask({ id: 'n1', title: '周报', date: '2026-11-16', time: '09:00', remind: 0 }),
  mkTask({ id: 'n2', title: '喝水', date: '2026-11-16', time: '09:30', remind: 5,
           repeat: 'd1', important: true, urgent: true }),
  mkTask({ id: 'n3', title: '月度复盘', date: '2026-11-16', time: '10:00', remind: 60,
           repeat: 'm1~2026-12-31', important: true }),
  mkTask({ id: 'n4', title: '带/斜杠与"引号"', date: '2026-11-16', time: '23:00', remind: 15 }),
  mkTask({ id: '😀', title: 'emoji 任务', date: '2026-11-16', time: '08:00', remind: 30,
           repeat: 'y1' }),
];
const notificationCases = [];
for (const lang of ['zh', 'en']) {
  i18n.lang = lang;
  for (const task of notiTasks) {
    for (const date of ['2026-11-16', '2026-11-17']) {
      const at = Date.UTC(2026, 10, 20, 3, 0, 0); // toNotification 用绝对 ms，不依赖 TZ
      const n = notify.toNotification({ at, task, date });
      notificationCases.push({
        lang, taskId: task.id, date, at, task,
        expected: {
          id: n.id, title: n.title, body: n.body, channelId: n.channelId,
          extraId: n.extra.id, extraOcc: n.extra.occ,
          scheduleAt: n.schedule.at.toISOString(),
        },
      });
    }
  }
}
i18n.lang = 'zh';

const out = {
  meta: {
    baseline: BASELINE,
    oracle: 'src/lib/notify.js (function bodies verbatim; 4 stub imports + 4 absolute imports + 1 appended export)',
    generatedBy: 'node ios/PlannerTests/Fixtures/generate_notify_fixtures.mjs',
    timezones: TZS,
    windowDays: 30,
    max: 60,
    labels: labels.length,
    idOf: idOf.length,
    planCases: planCases.length,
    notificationCases: notificationCases.length,
  },
  labels, idOf, planCases, notificationCases,
};
writeFileSync(resolve(here, 'notify_fixtures.json'), JSON.stringify(out, null, 2) + '\n');
console.log(`notify_fixtures.json: labels=${labels.length} idOf=${idOf.length} ` +
            `planCases=${planCases.length} (${TZS.length} TZ × ${planSets.length} sets) ` +
            `notifications=${notificationCases.length}`);

