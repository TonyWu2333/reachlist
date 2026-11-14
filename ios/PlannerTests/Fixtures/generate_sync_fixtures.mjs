#!/usr/bin/env node
// T-10 / M-08+M-09 同步契约黄金夹具生成器。
//
// oracle 全部来自 baseline_commit 97a7c4c 的真实源码：
// · 连接码正则：`src/lib/sync.js:13-16` 的 parseCode。sync.js 顶层依赖
//   vue / store.js（Capacitor）/ i18n.js，/tmp 运行副本里这 3 行 import
//   全部换成等价 stub（parseCode 本身不用它们），其余含 parseCode 函数体逐字未改。
// · 错误文案：`src/lib/i18n.js:t()` 在 lang='zh' / 'en' 下的真实输出。
// · 同步载荷：`JSON.stringify({ ...syncPayload(), meta: { tz } })` 的逐字输出。
//
// 生成命令：node ios/PlannerTests/Fixtures/generate_sync_fixtures.mjs
// 输出：ios/PlannerTests/Fixtures/sync_fixtures.json

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../../..');
const here4 = (p) => import(pathToFileURL(resolve(root, p)).href);

const BASELINE = '97a7c4c17602327a42d30110806a6a1e6fa0e798';

// ---- parseCode oracle：只替换 1 行 import ----
const src = readFileSync(resolve(root, 'src/lib/sync.js'), 'utf8');
const replacements = [
  ["import { reactive } from 'vue';", 'const reactive = (x) => x;'],
  ["import { state, syncPayload, applyRemote, onLocalChange } from './store.js';",
   'const state = { settings: {} }; const syncPayload = () => ({}); const applyRemote = () => {}; const onLocalChange = () => {};'],
  ["import { t } from './i18n.js';", 'const t = (s) => s;'],
];
let patched = src;
for (const [from, to] of replacements) {
  if (!patched.includes(from)) throw new Error(`替换未命中：${from}`);
  patched = patched.replace(from, to);
}
const changed = src.split('\n').filter((l, i) => l !== patched.split('\n')[i]).length;
if (changed !== replacements.length) throw new Error(`运行副本改动 ${changed} 行，预期 ${replacements.length} 行`);
const oracleDir = '/tmp/t10_oracle';
mkdirSync(oracleDir, { recursive: true });
const oraclePath = resolve(oracleDir, 'sync.mjs');
writeFileSync(oraclePath, patched);
const { parseCode } = await import(pathToFileURL(oraclePath).href);

// ---- 文案 oracle ----
const { t, i18n } = await here4('src/lib/i18n.js');
const keys = [
  ['令牌不对', undefined],
  ['服务器返回 {code}', { code: 500 }],
  ['连不上服务器', undefined],
  ['连接码格式不对：应该是 地址#令牌', undefined],
  ['正在同步…', undefined],
  ['还没同步过', undefined],
  ['同步完成', undefined],
];
const strings = [];
for (const [key, params] of keys) {
  i18n.lang = 'zh';
  const zh = t(key, params);
  i18n.lang = 'en';
  const en = t(key, params);
  strings.push({ key, zh, en });
}
i18n.lang = 'zh';

// ---- 载荷 oracle ----
// 17 键顺序与 store.js:normalizeTask 一致；deleted 按 key 排序规范化（对象键序无语义）。
const mkTask = (o = {}) => ({
  id: 'a1', title: '开会', note: '', date: '2026-11-13', time: '09:00',
  important: false, urgent: false, done: false, dropped: false,
  createdAt: 1700000000000, doneAt: null, repeat: '', doneDates: [], skipDates: [],
  remind: null, parentId: '', updatedAt: 1700000000000, ...o,
});
const normalized = (obj) => '{' + Object.keys(obj).sort()
  .map((k) => `${JSON.stringify(k)}:${JSON.stringify(obj[k])}`).join(',') + '}';
const payloadCases = [
  { tasks: [], deleted: {}, tz: 'Asia/Shanghai' },
  { tasks: [mkTask(), mkTask({ id: 'a2', title: '带/斜杠', note: 'http://x/y', repeat: 'd1' })],
    deleted: { gone: 1600000000000, a2: 1500000000000 }, tz: 'America/New_York' },
];
const payloads = payloadCases.map((p) => ({
  tasks: p.tasks, deleted: p.deleted, tz: p.tz,
  expected: '{"tasks":[' + p.tasks.map((x) => JSON.stringify(x)).join(',')
    + '],"deleted":' + normalized(p.deleted)
    + ',"meta":{"tz":' + JSON.stringify(p.tz) + '}}',
}));

// ---- 连接码用例 ----
const T16 = 'abcdefghijklmnop';
const codes = [
  '', null, undefined, '   ',
  `http://127.0.0.1:18787#${T16}`,
  `https://example.com#${T16}`,
  `http://example.com/#${T16}`,
  `  http://x:1#${T16}  `,
  `http://x/path/sub#${T16}`,
  `http://x#abc._~-0123456789`,
  `http://x#${T16.slice(0, 15)}`,
  `http://x#${T16}extra`,
  'ftp://x#abcdefghijklmnop',
  'http://x#has space in token',
  'http://x#bad!token1234567',
  `https://#${T16}`,
  'http://x',
  `http://x#`,
  `http://x#${T16}#more`,
  `HTTP://x#${T16}`,
  `http://x y#${T16}`,
  `http://x#${T16}\n`,
];
const parseCases = codes.map((code) => ({ code: code ?? null, expected: parseCode(code) }));

const out = {
  meta: {
    baseline_commit: BASELINE,
    generator: 'ios/PlannerTests/Fixtures/generate_sync_fixtures.mjs',
    oracle: '/tmp/t10_oracle/sync.mjs (运行副本，仅替换 1 行 import)',
    oracle_changed_lines: changed,
    parse_case_count: parseCases.length,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    note: 'parseCode / 文案 / 载荷编码的期望值均由真实上游源码产出；载荷 deleted 按 key 排序规范化。',
  },
  parseCode: parseCases,
  strings,
  payloads,
};
const dest = resolve(here, 'sync_fixtures.json');
writeFileSync(dest, JSON.stringify(out, null, 2) + '\n');
console.log(`wrote ${dest}: ${parseCases.length} codes, ${strings.length} strings, ${payloads.length} payloads, oracle changed ${changed} line`);
