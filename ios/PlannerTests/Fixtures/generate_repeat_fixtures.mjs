#!/usr/bin/env node
// T-07 / M-03 重复规则引擎契约黄金夹具生成器。
//
// oracle 是 baseline_commit 97a7c4c 的真实源码 src/lib/repeat.js（164 行，未复制、未改写）。
// repeat.js 依赖 date.js 与 i18n.js:isEn，两者在 Node 下可直接 import；
// 语言通过 i18n.lang = 'zh' | 'en' 切换，不用运行副本、不替换函数体。
//
// 用法（任意 cwd）：
//   node ios/PlannerTests/Fixtures/generate_repeat_fixtures.mjs
// 输出：ios/PlannerTests/Fixtures/repeat_fixtures.json
//
// 所有日期都固定注入，不读系统当前时间（repeatLabel / occursOn / nextOccurrence /
// streakOf / normalizeRepeat 都接受显式日期），保证夹具可复现。

import { writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../../..');
const importFromRoot = (p) => import(pathToFileURL(resolve(root, p)).href);

const rep = await importFromRoot('src/lib/repeat.js');
const date = await importFromRoot('src/lib/date.js');
const { i18n } = await importFromRoot('src/lib/i18n.js');

const BASELINE = '97a7c4c17602327a42d30110806a6a1e6fa0e798';
const TODAY = '2026-11-13';

// 任务含 PlannerTask 的全部 17 个字段，Swift 侧用 JSONDecoder 直接解码。
const mkTask = (o = {}) => ({
  id: 't1', title: '示例任务', note: '', date: '2026-01-01', time: '',
  important: false, urgent: false, done: false, dropped: false,
  createdAt: 1700000000000, doneAt: null, repeat: 'd1',
  doneDates: [], skipDates: [], remind: null, parentId: '', updatedAt: 1700000000000,
  ...o,
});

const f = {
  meta: {
    baseline_commit: BASELINE,
    generator: 'ios/PlannerTests/Fixtures/generate_repeat_fixtures.mjs',
    today: TODAY,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    note: '全部日期显式注入；语言由 i18n.lang 切换；任务对象含 PlannerTask 全 17 字段。',
  },
  parseRule: [], formatRule: [], normalizeRepeat: [],
  occursOn: [], nextOccurrence: [], instanceOf: [],
  repeatLabel: [], repeatGroup: [], streakOf: [], tasksOn: [],
};

// ---- parseRule：合法 / 非法 / 边界 ----
const rules = [
  'd1', 'd3', 'd0', 'd99', 'd999', 'd1000',
  'w1:12345', 'w1:06', 'w1:0123456', 'w2:5', 'w3:135', 'w1:531', 'w1',
  'm1', 'm2', 'm31', 'y1', 'y4',
  'd1~2026-12-31', 'm1~2027-01-01', 'w2:5~2026-12-31',
  '', 'x1', 'D1', 'd', 'd1:', 'w1:', 'w1:8', 'w1:12345678',
  'd1~2026-13-01', 'd1~bad', ' d1', 'd1 ', 'daily',
];
for (const s of rules) f.parseRule.push({ s, expected: rep.parseRule(s) });

// ---- formatRule ----
const formatCases = [
  { freq: 'd', n: 1, days: [], until: '' },
  { freq: 'd', n: 3, days: [5], until: '2026-12-31' },
  { freq: 'w', n: 2, days: [5, 1, 1], until: '2026-12-31' },
  { freq: 'w', n: 1, days: [0, 6], until: '' },
  { freq: 'm', n: 0, days: [], until: '' },
  { freq: 'y', n: 4, days: [], until: '2030-01-01' },
  { freq: 'm', n: -2, days: [], until: '' },
];
for (const rule of formatCases) f.formatRule.push({ rule, expected: rep.formatRule(rule) });

// ---- normalizeRepeat（老数据迁移） ----
for (const s of ['daily', 'weekdays', 'monthly', 'weekly', 'd1', 'w2:5', 'bogus', '', 'd1~2026-12-31']) {
  f.normalizeRepeat.push({ s, date: '2026-11-13', expected: rep.normalizeRepeat(s, '2026-11-13') });
}
// weekly 在不同开始日期下取星期
for (const date of ['2026-11-09', '2026-11-13', '2026-11-15', '2024-02-29']) {
  f.normalizeRepeat.push({ s: 'weekly', date, expected: rep.normalizeRepeat('weekly', date) });
}

// ---- occursOn：边界覆盖 §8.2 第 2 条 ----
const occurDates = [
  '2024-01-31', '2024-02-29', '2024-03-31', '2024-04-30', '2025-01-31',
  '2025-02-28', '2025-12-31', '2026-01-01', '2026-01-31', '2026-02-28',
  '2026-11-13', '2026-11-14', '2026-11-15', '2026-11-20', '2026-12-25',
  '2026-12-31', '2027-01-01', '2027-01-08', '2028-02-29', '2030-01-01',
];
const occurTasks = [
  mkTask({ id: 'd1', date: '2026-01-01', repeat: 'd1' }),
  mkTask({ id: 'd3', date: '2026-01-01', repeat: 'd3' }),
  mkTask({ id: 'm31', date: '2024-01-31', repeat: 'm1' }),
  mkTask({ id: 'm2', date: '2026-01-15', repeat: 'm2' }),
  mkTask({ id: 'y29', date: '2024-02-29', repeat: 'y1' }),
  mkTask({ id: 'y4', date: '2024-02-29', repeat: 'y4' }),
  mkTask({ id: 'w135', date: '2026-01-02', repeat: 'w1:135' }),
  mkTask({ id: 'w2_5', date: '2026-12-25', repeat: 'w2:5' }),          // 跨年隔周五
  mkTask({ id: 'wdays', date: '2026-01-01', repeat: 'w1:12345' }),
  mkTask({ id: 'weekend', date: '2026-01-01', repeat: 'w1:06' }),
  mkTask({ id: 'until', date: '2026-11-01', repeat: 'd1~2026-11-15' }), // 结束日期当天 / 之后
  mkTask({ id: 'skip', date: '2026-11-01', repeat: 'd1', skipDates: ['2026-11-13', '2026-11-14'] }),
  mkTask({ id: 'ended', date: '2026-01-01', repeat: 'd1~2026-01-31' }),
  mkTask({ id: 'invalid', date: '2026-01-01', repeat: 'w1' }),
  mkTask({ id: 'none', date: '', repeat: 'd1' }),
];
for (const task of occurTasks) {
  for (const d of occurDates) f.occursOn.push({ task, d, expected: rep.occursOn(task, d) });
}

// ---- nextOccurrence ----
const nextCases = [
  [mkTask({ date: '2026-11-01', repeat: 'd1' }), '2026-11-13'],
  [mkTask({ date: '2026-11-01', repeat: 'd3' }), '2026-11-13'],
  [mkTask({ date: '2027-01-01', repeat: 'm1' }), '2026-11-13'],         // from 早于开始日期
  [mkTask({ date: '2026-11-01', repeat: 'd1~2026-11-15' }), '2026-11-13'],
  [mkTask({ date: '2026-11-01', repeat: 'd1~2026-11-15' }), '2026-11-20'], // until 已过 → ''
  [mkTask({ date: '2026-11-01', repeat: 'd1', skipDates: ['2026-11-13', '2026-11-14'] }), '2026-11-13'],
  [mkTask({ date: '2026-12-25', repeat: 'w2:5' }), '2026-12-26'],       // 跨年
  [mkTask({ date: '2024-01-31', repeat: 'm1' }), '2024-02-01'],         // 月底
  [mkTask({ date: '2024-02-29', repeat: 'y1' }), '2025-02-01'],         // 闰年
  [mkTask({ date: '2026-01-01', repeat: '' }), '2026-11-13'],           // 无规则
  [mkTask({ date: '', repeat: 'd1' }), '2026-11-13'],                    // 无开始日期
  [mkTask({ date: '2026-01-01', repeat: 'w1' }), '2026-11-13'],          // 非法规则
];
for (const [task, from] of nextCases) {
  f.nextOccurrence.push({ task, from, expected: rep.nextOccurrence(task, from) });
}

// ---- instanceOf ----
for (const [task, d] of [
  [mkTask({ date: '2026-01-01', repeat: 'd1', doneDates: ['2026-11-13'] }), '2026-11-13'],
  [mkTask({ date: '2026-01-01', repeat: 'd1', doneDates: [] }), '2026-11-13'],
  [mkTask({ date: '2026-01-01', repeat: 'd1', done: true, doneDates: ['2026-11-12'] }), '2026-11-13'],
]) {
  const inst = rep.instanceOf(task, d);
  f.instanceOf.push({ task, d, expected: { date: inst.date, done: inst.done, occ: inst.occ } });
}

// ---- repeatLabel：中英 × withUntil ----
const labelRules = [
  'd1', 'd3', 'd99',
  'w1:0123456', 'w1:12345', 'w1:06', 'w1:135', 'w1:0', 'w2:5', 'w3:135',
  'm1', 'm2', 'm31', 'y1', 'y4',
  'd1~2026-12-31', 'm1~2027-01-01', 'w2:5~2026-12-31',
  '', 'w1', 'x1',
];
const labelDates = ['2026-11-13', '2024-01-31', '2024-02-29', '2026-12-31'];
for (const lang of ['zh', 'en']) {
  i18n.lang = lang;
  for (const date of labelDates) {
    for (const rule of labelRules) {
      for (const withUntil of [false, true]) {
        f.repeatLabel.push({ rule, date, lang, withUntil, expected: rep.repeatLabel(rule, date, withUntil) });
      }
    }
  }
}
i18n.lang = 'zh';

// ---- repeatGroup ----
for (const rule of ['d1', 'd3', 'w1:0123456', 'w1:12345', 'w2:5', 'm1', 'm2', 'y1', 'y4', '', 'w1']) {
  f.repeatGroup.push({ rule, expected: rep.repeatGroup(rule) });
}

// ---- streakOf ----
const streakCases = [
  [mkTask({ date: '2026-11-01', repeat: 'd1', doneDates: ['2026-11-10', '2026-11-11', '2026-11-12'] }), '2026-11-13'],
  [mkTask({ date: '2026-11-01', repeat: 'd1', doneDates: ['2026-11-10', '2026-11-12'] }), '2026-11-13'], // 中间断
  [mkTask({ date: '2026-11-01', repeat: 'd1', doneDates: ['2026-11-12', '2026-11-13'] }), '2026-11-13'], // 今天已完成
  [mkTask({ date: '2026-11-01', repeat: 'd1', doneDates: ['2026-11-12'], skipDates: ['2026-11-11'] }), '2026-11-13'], // 跳过日不算断
  [mkTask({ date: '2026-11-01', repeat: 'd1', doneDates: [], skipDates: ['2026-11-13'] }), '2026-11-13'],
  [mkTask({ date: '2026-11-13', repeat: 'd1', doneDates: [] }), '2026-11-13'],  // 开始日期就是今天
  [mkTask({ date: '2026-11-01', repeat: 'w1:135', doneDates: ['2026-11-09', '2026-11-11'] }), '2026-11-13'],
  [mkTask({ date: '2026-11-01', repeat: 'm1', doneDates: ['2026-11-01'] }), '2026-11-13'],
  // 800 次回溯上限：doneDates 必须覆盖从 d0 往前 800+ 个发生日，否则测不到上限。
  // 用本地时间日期串（date.js:addDays），不能用 toISOString。
  [mkTask({ date: '2024-01-01', repeat: 'd1', doneDates: Array.from({ length: 1200 }, (_, i) => date.addDays('2024-01-01', i)) }), '2026-11-13'],
];
for (const [task, d0] of streakCases) {
  f.streakOf.push({ task, d0, expected: rep.streakOf(task, d0) });
}

// ---- tasksOn：一次性 + 重复混合 ----
const mixedTasks = [
  mkTask({ id: 'once-today', date: '2026-11-13', repeat: '' }),
  mkTask({ id: 'once-other', date: '2026-11-14', repeat: '' }),
  mkTask({ id: 'daily', date: '2026-11-01', repeat: 'd1' }),
  mkTask({ id: 'odd', date: '2026-11-01', repeat: 'd2' }),
  mkTask({ id: 'skipped', date: '2026-11-01', repeat: 'd1', skipDates: ['2026-11-13'] }),
  mkTask({ id: 'done-inst', date: '2026-11-01', repeat: 'd1', doneDates: ['2026-11-13'] }),
  mkTask({ id: 'ended', date: '2026-01-01', repeat: 'd1~2026-01-31' }),
];
for (const d of ['2026-11-12', '2026-11-13', '2026-11-14', '2027-01-01']) {
  // 复刻 store.js:tasksOn 的 flatMap（不引入 store.js 的全局 state）
  const expected = mixedTasks.flatMap((t) => (t.repeat
    ? (rep.occursOn(t, d) ? [rep.instanceOf(t, d)] : [])
    : (t.date === d ? [t] : []))).map((t) => ({
      id: t.id, date: t.date, done: t.done, occ: t.occ ?? '',
    }));
  f.tasksOn.push({ tasks: mixedTasks, d, expected });
}

const out = resolve(root, 'ios/PlannerTests/Fixtures/repeat_fixtures.json');
writeFileSync(out, JSON.stringify(f) + '\n');
console.log('wrote ios/PlannerTests/Fixtures/repeat_fixtures.json');
for (const k of Object.keys(f)) {
  if (Array.isArray(f[k])) console.log(`  ${k}: ${f[k].length}`);
}
