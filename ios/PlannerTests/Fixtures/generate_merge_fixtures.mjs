#!/usr/bin/env node
// T-05 / M-05 合并算法契约黄金夹具生成器。
//
// oracle 是 baseline_commit 97a7c4c 的真实源码 shared/merge.js（48 行，未复制、未改写）：
// 直接 import 该文件，调用它的 taskSig / mergeState 产出期望值。
// merge.js 是纯函数、无 import，Node 下可直接加载，不需要运行副本。
//
// 用法（任意 cwd）：
//   node ios/PlannerTests/Fixtures/generate_merge_fixtures.mjs
// 输出：ios/PlannerTests/Fixtures/merge_fixtures.json
//
// 期望值用「规范化 dump」表示，而不是 JSON.stringify(state)：
// Swift 的字典没有插入序，`deleted` / `meta` 的键序不可复现，而 §2.6.1 只要求
// 任务数组有序、taskSig 键序敏感。dump 对这两个字典按键名排序后再比较，
// 既保留全部语义，又不引入无意义的键序差异。

import { writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../../..');
const { taskSig, mergeState } = await import(pathToFileURL(resolve(root, 'shared/merge.js')).href);

const BASELINE = '97a7c4c17602327a42d30110806a6a1e6fa0e798';
const NOW = 1763000000000;   // 2026-11-13T…Z 附近，固定注入，保证可复现
const DAY = 864e5;

// 任务含 PlannerTask 的全部 17 个字段，且键序为 normalizeTask 的输出序
// （Swift 侧 JSONDecoder 直接解码；顺序错误会让 sig 对比立刻失败）。
const mk = (o = {}) => ({
  id: 't1', title: '示例任务', note: '', date: '2026-01-01', time: '',
  important: false, urgent: false, done: false, dropped: false,
  createdAt: 1700000000000, doneAt: null, repeat: '',
  doneDates: [], skipDates: [], remind: null, parentId: '', updatedAt: 1700000000000,
  ...o,
});

// 与 Swift 侧 MergeState.contractDump() 必须逐字一致。
const num = (v) => (Number.isInteger(v) ? String(v) : String(v));
const dump = (state) => {
  const tasks = (state.tasks || []).map((t) => JSON.stringify(t));
  const ids = (state.tasks || []).map((t) => t.id).join('|');
  const deleted = Object.entries(state.deleted || {})
    .map(([k, v]) => `${k}:${num(v)}`).sort().join(',');
  const meta = Object.entries(state.meta || {})
    .map(([k, v]) => `${k}:${v}`).sort().join(',');
  return `ids:${ids}\ntasks:${tasks.join('\n')}\ndeleted:${deleted}\nmeta:${meta}`;
};

const caseOf = (name, a, b, now = NOW) => {
  const merged = mergeState(a, b, now);
  return {
    name,
    now,
    a,
    b,
    expect: { taskIds: merged.tasks.map((t) => t.id), dump: dump(merged) },
    // 输入任务本身的 taskSig：Swift 侧逐条比对，确保序列化片段等价（VERIFY-01 复用）。
    inputSigs: { a: (a.tasks || []).map(taskSig), b: (b.tasks || []).map(taskSig) },
  };
};

const S = (tasks, deleted = {}, meta = { tz: 'Asia/Shanghai' }) => ({ tasks, deleted, meta });

const cases = [];

// ---- 1. 空状态 ----
cases.push(caseOf('empty-both', S([]), S([])));
cases.push(caseOf('empty-a', S([]), S([mk({ id: 't1' }), mk({ id: 't2' })])));
cases.push(caseOf('empty-b', S([mk({ id: 't1' }), mk({ id: 't2' })]), S([])));

// ---- 2. 不相交：顺序 = a 在前、b 在后 ----
cases.push(caseOf(
  'disjoint',
  S([mk({ id: 't1' }), mk({ id: 't2' })]),
  S([mk({ id: 't3' }), mk({ id: 't4' })]),
));

// ---- 3. 交叉重复：位置取「首次出现」 ----
cases.push(caseOf(
  'dup-first-occurrence',
  S([mk({ id: 't1' }), mk({ id: 't2' })]),
  S([mk({ id: 't2', title: '乙' }), mk({ id: 't1', title: '甲' })]),
));

// ---- 4/5. updatedAt 裁决 ----
cases.push(caseOf(
  'newer-in-b',
  S([mk({ id: 't1', title: '旧', updatedAt: 1700000001000 })]),
  S([mk({ id: 't1', title: '新', updatedAt: 1700000002000 })]),
));
cases.push(caseOf(
  'newer-in-a',
  S([mk({ id: 't1', title: '新', updatedAt: 1700000002000 })]),
  S([mk({ id: 't1', title: '旧', updatedAt: 1700000001000 })]),
));
cases.push(caseOf(
  'newer-equal-both-sides',
  S([mk({ id: 't1', title: '同', updatedAt: 1700000002000 })]),
  S([mk({ id: 't1', title: '同', updatedAt: 1700000002000 })]),
));

// ---- 6. 平局 → taskSig 字符串裁决 ----
cases.push(caseOf(
  'tie-sig-ascii',
  S([mk({ id: 't1', title: 'A', updatedAt: 1700000002000 })]),
  S([mk({ id: 't1', title: 'a', updatedAt: 1700000002000 })]),
));
// 非 BMP（代理对）vs BMP 高码位：UTF-16 序与 Unicode 标量序相反。
// UTF-16: 😀 = D83D DE00 < FFFD；标量序: U+1F600 > U+FFFD。
cases.push(caseOf(
  'tie-sig-emoji-vs-fffd',
  S([mk({ id: 't1', title: '😀', updatedAt: 1700000002000 })]),
  S([mk({ id: 't1', title: '\uFFFD', updatedAt: 1700000002000 })]),
));
// 组合字符 vs 预组合字符：Swift 原生 `==` 视为相同，JS 逐 code unit 能分出大小。
cases.push(caseOf(
  'tie-sig-combining',
  S([mk({ id: 't1', title: 'e\u0301', updatedAt: 1700000002000 })]),
  S([mk({ id: 't1', title: '\u00e9', updatedAt: 1700000002000 })]),
));
// 转义与中文：验证带引号/反斜杠/换行的字符串片段逐字一致。
cases.push(caseOf(
  'tie-sig-escapes',
  S([mk({ id: 't1', title: '写"引号"\\反斜杠\n换行', updatedAt: 1700000002000 })]),
  S([mk({ id: 't1', title: '写"引号"\\反斜杠\r换行', updatedAt: 1700000002000 })]),
));
cases.push(caseOf(
  'tie-sig-chinese',
  S([mk({ id: 't1', title: '打', updatedAt: 1700000002000 })]),
  S([mk({ id: 't1', title: '买', updatedAt: 1700000002000 })]),
));

// ---- 9~12. 墓碑 ----
cases.push(caseOf(
  'tombstone-kills',
  S([], { t1: 1700000002000 }),
  S([mk({ id: 't1', updatedAt: 1700000001000 })]),
));
cases.push(caseOf(
  'tombstone-equal-updatedAt',
  S([], { t1: 1700000002000 }),
  S([mk({ id: 't1', updatedAt: 1700000002000 })]),
));
cases.push(caseOf(
  'tombstone-resurrect',
  S([], { t1: 1700000001000 }),
  S([mk({ id: 't1', updatedAt: 1700000002000 })]),
));
// gone === 0 是 falsy：任务保留，墓碑也不清除（只能等 90 天清理）。
cases.push(caseOf(
  'tombstone-zero',
  S([mk({ id: 't1', updatedAt: 1700000002000 })], { t1: 0 }),
  S([]),
));

// ---- 13/14. 父子 ----
cases.push(caseOf(
  'parent-tombstoned-child-dropped',
  S([mk({ id: 'p1' }), mk({ id: 'c1', parentId: 'p1' }), mk({ id: 'c2', parentId: 'p1' })]),
  S([], { p1: 1700000009000 }),
));
cases.push(caseOf(
  'orphan-child-dropped',
  S([mk({ id: 'c1', parentId: 'gone' })]),
  S([]),
));
cases.push(caseOf(
  'child-kept-with-parent',
  S([mk({ id: 'p1' }), mk({ id: 'c1', parentId: 'p1' })]),
  S([]),
));

// ---- 15/16. 墓碑 90 天边界 ----
cases.push(caseOf(
  'tombstone-ttl-expired',
  S([], { t1: NOW - 90 * DAY - 1 }),
  S([mk({ id: 't1', updatedAt: 1700000000000 })]),
));
cases.push(caseOf(
  'tombstone-ttl-boundary-exact',
  S([], { t1: NOW - 90 * DAY }),
  S([mk({ id: 't1', updatedAt: 1700000000000 })]),
));

// ---- 17/18. deleted / meta 合并 ----
cases.push(caseOf(
  'deleted-merge-keeps-max',
  S([], { x: 1700000001000 }),
  S([], { x: 1700000000000, y: 1700000003000 }),
));
cases.push(caseOf(
  'meta-b-overrides-a',
  S([], {}, { tz: 'Asia/Shanghai', app: 'android' }),
  S([], {}, { tz: 'America/New_York' }),
));

// ---- 19. 混合 ----
cases.push(caseOf(
  'mixed',
  S(
    [mk({ id: 't1', title: '一', updatedAt: 1700000001000 }),
     mk({ id: 't2', title: '二', parentId: '' }),
     mk({ id: 'c1', parentId: 't2' })],
    { t3: 1700000005000 },
  ),
  S(
    [mk({ id: 't1', title: '一改', updatedAt: 1700000004000 }),
     mk({ id: 't3', title: '三' }),
     mk({ id: 't4', title: '四', dropped: true, done: true })],
    { t2: 1700000006000 },
    { tz: 'Europe/London' },
  ),
));

// ---- 20. 随机模糊（确定性种子，覆盖组合爆炸） ----
let seed = 20261113;
const rnd = () => {
  seed = (seed * 1103515245 + 12345) % 2147483648;
  return seed / 2147483648;
};
const pick = (arr) => arr[Math.floor(rnd() * arr.length)];
const IDS = ['a1', 'a2', 'a3', 'b1', 'b2', 'p1', 'c1', 'c2'];
const TITLES = ['写周报', 'Water plants', '😀', '\uFFFD', 'e\u0301', '\u00e9', '', '写 "引号" \\ 反斜杠'];
const TIMES = [1700000000000, 1700000001000, 1700000002000, NOW - 90 * DAY - 5, NOW - 90 * DAY + 5];

const randTask = () => {
  const dropped = rnd() < 0.1;
  return mk({
    id: pick(IDS),
    title: pick(TITLES),
    note: rnd() < 0.3 ? 'note-' + pick(TITLES) : '',
    date: pick(['2026-01-01', '2026-11-13', '']),
    important: rnd() < 0.5,
    urgent: rnd() < 0.5,
    dropped,
    done: dropped || rnd() < 0.3,
    createdAt: pick(TIMES),
    updatedAt: pick(TIMES),
    // 子任务只允许「一层」且不能重复：父任务 id 从非 c* 里取。
    parentId: rnd() < 0.25 ? pick(['p1', 'a1', 'b2']) : '',
  });
};
const randState = () => {
  const tasks = [];
  const n = Math.floor(rnd() * 4);
  for (let i = 0; i < n; i++) tasks.push(randTask());
  const deleted = {};
  for (const id of IDS) if (rnd() < 0.18) deleted[id] = pick(TIMES);
  return S(tasks, deleted, rnd() < 0.5 ? { tz: 'Asia/Shanghai' } : {});
};

for (let i = 0; i < 150; i++) {
  cases.push(caseOf(`fuzz-${String(i + 1).padStart(3, '0')}`, randState(), randState()));
}

// ---- taskSig 单值夹具 ----
const sigCases = [
  ['ascii', mk({ title: 'hello' })],
  ['chinese', mk({ title: '写周报' })],
  ['emoji', mk({ title: '😀🎉' })],
  ['combining', mk({ title: 'e\u0301' })],
  ['escapes', mk({ title: 'a"b\\c\nd\te', note: 'n\u0001' })],
  ['nulls', mk({ doneAt: null, remind: null, parentId: '', date: '' })],
  ['numbers', mk({ createdAt: 1700000000000, doneAt: 1700000000500, remind: 0 })],
  ['remind-sixty', mk({ time: '09:30', remind: 60 })],
  ['repeat-until', mk({ id: 'r1', date: '2026-11-13', repeat: 'w1:135~2026-12-31' })],
  ['doneDates', mk({ repeat: 'd1', date: '2026-11-13', doneDates: ['2026-11-13', '2026-11-14'], skipDates: ['2026-11-15'] })],
  ['updatedAt-excluded', mk({ updatedAt: 9999999999999 })],
].map(([name, task]) => ({ name, task, sig: taskSig(task) }));

// ---- 输入合法性守卫 ----
//
// 合并函数不做规范化（shared/merge.js 直接吃任务对象），因此夹具里的任务必须是
// `store.js:normalizeTask` 的**不动点**：一旦某个字段会被 normalize 改写，
// JS 侧 sig 与 Swift 侧（解码即 normalize）就会天然不同，得到的失败是夹具缺陷、
// 不是引擎缺陷。这里逐条核对，避免把这类噪声混进契约测试。
const KEY_ORDER = [
  'id', 'title', 'note', 'date', 'time', 'important', 'urgent', 'done', 'dropped',
  'createdAt', 'doneAt', 'repeat', 'doneDates', 'skipDates', 'remind', 'parentId', 'updatedAt',
];
const isYMD = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s);
const isHM = (s) => typeof s === 'string' && /^\d{2}:\d{2}$/.test(s);

const guardTask = (t, where) => {
  const bad = [];
  if (!t.id || typeof t.id !== 'string') bad.push('id 为空');
  if (typeof t.title !== 'string' || t.title !== t.title.trim()) bad.push('title 未 trim');
  if (!(t.date === '' || isYMD(t.date))) bad.push('date 非法');
  if (!(t.time === '' || isHM(t.time))) bad.push('time 非法');
  if (t.dropped && !t.done) bad.push('dropped=true 但 done=false');
  if (!(t.remind === null || (Number.isInteger(t.remind) && t.remind >= 0))) bad.push('remind 非 null 且非 >=0 整数');
  for (const d of [...(t.doneDates || []), ...(t.skipDates || [])]) if (!isYMD(d)) bad.push('doneDates/skipDates 非法');
  if (!Number.isFinite(t.createdAt) || t.createdAt === 0) bad.push('createdAt');
  if (!Number.isFinite(t.updatedAt) || t.updatedAt === 0) bad.push('updatedAt');
  const keys = Object.keys(t).join(',');
  if (keys !== KEY_ORDER.join(',')) bad.push('键序不等于 normalizeTask 输出序');
  if (bad.length) throw new Error(`${where} / ${t.id}: 不是 normalize 的不动点 → ${bad.join('; ')}`);
};

cases.forEach((c) => {
  (c.a.tasks || []).forEach((t, i) => guardTask(t, `${c.name}.a[${i}]`));
  (c.b.tasks || []).forEach((t, i) => guardTask(t, `${c.name}.b[${i}]`));
});
sigCases.forEach((c) => guardTask(c.task, `sig:${c.name}`));

const fixture = {
  meta: {
    generator: 'ios/PlannerTests/Fixtures/generate_merge_fixtures.mjs',
    command: 'node ios/PlannerTests/Fixtures/generate_merge_fixtures.mjs',
    oracle: 'shared/merge.js @ ' + BASELINE,
    baseline_commit: BASELINE,
    now: NOW,
    case_count: cases.length,
    sig_case_count: sigCases.length,
    dump_format: 'ids:<id|id>\\ntasks:<JSON.stringify(t) 每行一条>\\ndeleted:<id:ms 按 id 排序>\\nmeta:<k:v 按 k 排序>',
  },
  cases,
  sigCases,
};

writeFileSync(
  resolve(here, 'merge_fixtures.json'),
  JSON.stringify(fixture, null, 1) + '\n',
  'utf8',
);
console.log(`merge fixtures: ${cases.length} cases, ${sigCases.length} sig cases -> merge_fixtures.json`);
