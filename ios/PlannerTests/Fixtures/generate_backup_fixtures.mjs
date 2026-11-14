#!/usr/bin/env node
// T-12 / M-18 备份导出导入黄金夹具生成器。
//
// oracle 全部来自 baseline_commit 97a7c4c 的真实源码 src/lib/backup.js（41 行）：
// · exportBackup / importBackup 的函数体**逐字未改**；/tmp 运行副本只把 6 行 import
//   换成环境 stub（Capacitor / Filesystem / Share / store / date / i18n 的绝对路径），
//   其余一字不动。语言与日期仍走项目内真实模块（同一模块实例）。
// · 用 FixedDate 固定 `new Date()`，使 exportedAt 与文件名可复现；
// · Share / Filesystem / confirm / replaceAll 全部用捕获 stub 记录真实实参。
// · 文案中文原文为键，英文来自 src/lib/i18n-en.js:core 的真实 t() 输出。
//
// 生成命令：node ios/PlannerTests/Fixtures/generate_backup_fixtures.mjs
// 输出：ios/PlannerTests/Fixtures/backup_fixtures.json

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../../..');
const abs = (p) => pathToFileURL(resolve(root, p)).href;
const BASELINE = '97a7c4c17602327a42d30110806a6a1e6fa0e798';

// ---- 固定时间（本地 2026-11-14 15:17:26.123 @ Asia/Shanghai） ----
const FIXED_MS = Date.UTC(2026, 10, 14, 7, 17, 26, 123);
const TZ = process.env.TZ || 'Asia/Shanghai';
const RealDate = Date;
class FixedDate extends RealDate {
  constructor(...args) { if (args.length === 0) super(FIXED_MS); else super(...args); }
  static now() { return FIXED_MS; }
}
globalThis.Date = FixedDate;

// ---- 运行副本：只替换 6 行 import ----
const src = readFileSync(resolve(root, 'src/lib/backup.js'), 'utf8');
const replacements = [
  ["import { Capacitor } from '@capacitor/core';", 'const Capacitor = globalThis.__t12_capacitor;'],
  ["import { Filesystem, Directory, Encoding } from '@capacitor/filesystem';",
   'const { Filesystem, Directory, Encoding } = globalThis.__t12_fs;'],
  ["import { Share } from '@capacitor/share';", 'const Share = globalThis.__t12_share;'],
  ["import { state, replaceAll } from './store.js';",
   'const { state, replaceAll } = globalThis.__t12_store;'],
  ["import { today } from './date.js';", `import { today } from '${abs('src/lib/date.js')}';`],
  ["import { t } from './i18n.js';", `import { t } from '${abs('src/lib/i18n.js')}';`],
];
let patched = src;
for (const [from, to] of replacements) {
  if (!patched.includes(from)) throw new Error(`替换未命中：${from}`);
  patched = patched.replace(from, to);
}
const changed = src.split('\n').filter((l, i) => l !== patched.split('\n')[i]).length;
if (changed !== replacements.length) throw new Error(`运行副本改动 ${changed} 行，预期 ${replacements.length} 行`);
const oracleDir = '/tmp/t12_oracle';
mkdirSync(oracleDir, { recursive: true });
const oraclePath = resolve(oracleDir, 'backup.mjs');
writeFileSync(oraclePath, patched);

let capture;
globalThis.__t12_capacitor = { isNativePlatform: () => true };
globalThis.__t12_fs = {
  Directory: { Cache: 'CACHE' }, Encoding: { UTF8: 'utf8' },
  Filesystem: {
    writeFile: async (args) => {
      capture.written = { path: args.path, data: args.data, directory: args.directory, encoding: args.encoding };
      return { uri: 'file:///cache/' + args.path };
    },
  },
};
globalThis.__t12_share = {
  share: async (args) => { capture.shared = { title: args.title, files: args.files }; },
};
globalThis.__t12_store = {
  state: { tasks: [] },
  replaceAll: (arr) => { capture.replaced = Array.isArray(arr) ? arr.map((x) => JSON.parse(JSON.stringify(x))) : null; },
};
globalThis.confirm = (msg) => { capture.confirmText = msg; return capture.confirmResult; };

const backup = await import(pathToFileURL(oraclePath).href);
const { i18n } = await import(abs('src/lib/i18n.js'));

// ---- 任务构造器：17 字段与 store.js:normalizeTask 输出键序一致 ----
const mkTask = (o = {}) => ({
  id: 'a1', title: '开会', note: '', date: '2026-11-14', time: '09:00',
  important: false, urgent: false, done: false, dropped: false,
  createdAt: 1700000000000, doneAt: null, repeat: '', doneDates: [], skipDates: [],
  remind: 0, parentId: '', updatedAt: 1700000000000, ...o,
});

// ---- 1) exportBackup ----
const exportSets = [
  { name: 'empty', tasks: [] },
  { name: 'one', tasks: [mkTask()] },
  {
    name: 'mixed',
    tasks: [
      mkTask({ id: 'a1', title: '带/斜杠与"引号"', note: 'http://x/y?a=1&b=2', remind: 15 }),
      // state.tasks 是 normalize 之后的对象（store.js:32 对 title 做 .trim()），
      // 因此转义字符放在中间，不在字符串末尾留空白，避免夹具绕过真实数据流。
      mkTask({ id: 'a2', title: '多行\n与制表\t继续', note: 'U+2028   结束', date: '2026-11-15',
               time: '18:30', repeat: 'd1', doneDates: ['2026-11-14', '2026-11-15'],
               skipDates: ['2026-11-16'], important: true, urgent: true, done: true,
               doneAt: 1763120000000, dropped: true, remind: 60,
               parentId: 'p0', createdAt: 1700000000000.5 }),
      mkTask({ id: '😀', title: 'emoji 与中文', note: '', remind: null, doneAt: 0 }),
    ],
  },
  {
    name: 'null-and-empty',
    tasks: [mkTask({ id: 'z', title: '', note: '', date: '', time: '', remind: null,
                     doneAt: null, repeat: '', doneDates: [], skipDates: [] })],
  },
];
const exportCases = [];
for (const lang of ['zh', 'en']) {
  i18n.lang = lang;
  for (const s of exportSets) {
    capture = { confirmResult: true };
    globalThis.__t12_store.state.tasks = s.tasks;
    await backup.exportBackup();
    exportCases.push({
      lang, name: s.name, tasks: s.tasks, fixedMs: FIXED_MS, tz: TZ,
      expected: {
        fileName: capture.written.path,
        text: capture.written.data,
        directory: capture.written.directory,
        encoding: capture.written.encoding,
        shareTitle: capture.shared.title,
        shareFiles: capture.shared.files,
      },
    });
  }
}

// ---- 2) importBackup ----
const valid3 = JSON.stringify({ version: 1, exportedAt: '2026-11-01T00:00:00.000Z',
  tasks: [mkTask({ id: 'i1' }), mkTask({ id: 'i2' }), mkTask({ id: 'i3' })] }, null, 2);
const valid1 = JSON.stringify({ version: 1, tasks: [mkTask({ id: 'only' })] });
const valid0 = JSON.stringify({ version: 1, tasks: [] });
const importSets = [
  { name: 'broken-json', fileText: '{oops', currentCount: 5, confirm: true },
  { name: 'no-tasks', fileText: '{"version":1}', currentCount: 5, confirm: true },
  { name: 'tasks-not-array', fileText: '{"tasks":"x"}', currentCount: 5, confirm: true },
  { name: 'null-root', fileText: 'null', currentCount: 5, confirm: true },
  { name: 'user-cancels', fileText: valid3, currentCount: 5, confirm: false },
  { name: 'replace-3-into-5', fileText: valid3, currentCount: 5, confirm: true },
  { name: 'replace-1-into-1', fileText: valid1, currentCount: 1, confirm: true },
  { name: 'replace-empty', fileText: valid0, currentCount: 7, confirm: true },
  { name: 'into-empty-current', fileText: valid3, currentCount: 0, confirm: true },
];
const importCases = [];
for (const lang of ['zh', 'en']) {
  i18n.lang = lang;
  for (const s of importSets) {
    capture = { confirmResult: s.confirm };
    globalThis.__t12_store.state.tasks = Array.from({ length: s.currentCount }, (_, i) => mkTask({ id: 'c' + i }));
    const result = await backup.importBackup({ text: async () => s.fileText });
    importCases.push({
      lang, name: s.name, fileText: s.fileText, currentCount: s.currentCount, confirm: s.confirm,
      expected: {
        ok: result.ok,
        message: result.message === undefined ? null : result.message,
        count: result.count === undefined ? null : result.count,
        confirmText: capture.confirmText === undefined ? null : capture.confirmText,
        replacedCount: capture.replaced === null || capture.replaced === undefined ? null : capture.replaced.length,
      },
    });
  }
}
i18n.lang = 'zh';

const out = {
  meta: {
    baseline: BASELINE,
    oracle: 'src/lib/backup.js (function bodies verbatim; 6 import lines replaced by stubs)',
    generatedBy: 'node ios/PlannerTests/Fixtures/generate_backup_fixtures.mjs',
    fixedMs: FIXED_MS,
    tz: TZ,
    exportCases: exportCases.length,
    importCases: importCases.length,
  },
  exportCases, importCases,
};
writeFileSync(resolve(here, 'backup_fixtures.json'), JSON.stringify(out, null, 2) + '\n');
console.log(`backup_fixtures.json: export=${exportCases.length} import=${importCases.length}`);
