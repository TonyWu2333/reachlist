#!/usr/bin/env node
// T-09 / M-02 TaskStore 契约黄金夹具生成器。
//
// oracle 是 baseline_commit 97a7c4c 的真实源码 src/lib/store.js（246 行）。
// 它在浏览器/Capacitor 下依赖 `vue:reactive/watch`、`@capacitor/preferences`、
// `crypto.randomUUID`、`Date.now()`。为了在 Node 里把它当纯函数 oracle 跑，
// 这里生成一份 /tmp 运行副本，**只替换 5 处环境依赖**（import 行与全局），
// 所有操作函数体逐字未改；生成器会断言替换命中数并打印 diff 行数供复核。
//
// 运行副本里的 `watch` 是 no-op：本夹具验证的是状态机与持久化语义，
// 250ms 防抖由 Swift 侧 TaskStore（UI 包装）单独实现并用 XCTest 验证。
//
// 用法（任意 cwd）：node ios/PlannerTests/Fixtures/generate_store_fixtures.mjs
// 输出：ios/PlannerTests/Fixtures/store_fixtures.json

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../../..');
const here4 = (p) => pathToFileURL(resolve(root, p)).href;

const BASELINE = '97a7c4c17602327a42d30110806a6a1e6fa0e798';
const FIXED_MS = new Date(2026, 10, 13, 12, 0, 0).getTime(); // 本地 2026-11-13 12:00

// ---- 运行副本：只改 5 处环境依赖 ----
const src = readFileSync(resolve(root, 'src/lib/store.js'), 'utf8');
const replacements = [
  ["import { reactive, watch } from 'vue';",
   'const reactive = (x) => x; const watch = () => {};'],
  ["import { load, save, loadSettings, saveSettings } from './storage.js';",
   'const { load, save, loadSettings, saveSettings } = globalThis.__t09_storage;'],
  ["from './repeat.js'", `from '${here4('src/lib/repeat.js')}'`],
  ["from './date.js'", `from '${here4('src/lib/date.js')}'`],
  ["from '../../shared/merge.js'", `from '${here4('shared/merge.js')}'`],
];
let patched = src;
for (const [from, to] of replacements) {
  if (!patched.includes(from)) throw new Error(`替换未命中：${from}`);
  patched = patched.replace(from, to);
}
const unchangedLines = src.split('\n').filter((l, i) => l === patched.split('\n')[i]).length;
const changedLines = src.split('\n').length - unchangedLines;
if (changedLines !== replacements.length) {
  throw new Error(`运行副本改动了 ${changedLines} 行，预期仅 ${replacements.length} 行`);
}
const oracleDir = '/tmp/t09_oracle';
mkdirSync(oracleDir, { recursive: true });
const oraclePath = resolve(oracleDir, 'store.mjs');
writeFileSync(oraclePath, patched);

// ---- 固定环境 ----
const RealDate = Date;
class FixedDate extends RealDate {
  constructor(...args) { super(...(args.length ? args : [FIXED_MS])); }
  static now() { return FIXED_MS; }
}
globalThis.Date = FixedDate;
Object.defineProperty(globalThis, 'crypto', {
  value: { randomUUID: () => `t09-${globalThis.__t09_nextId++}` },
  configurable: true, writable: true,
});

globalThis.__t09_storage = {
  // storage.js:8-21 的等价：传入字符串时先 JSON.parse，失败则另存原文并回退空数据。
  load: async () => {
    const raw = globalThis.__t09_data;
    if (typeof raw !== 'string') return raw;
    try {
      const data = JSON.parse(raw);
      if (!Array.isArray(data.tasks)) throw new Error('bad shape');
      return data;
    } catch {
      globalThis.__t09_corrupt++;
      return { version: 1, tasks: [] };
    }
  },
  save: async (d) => {
    globalThis.__t09_saved = d;
    globalThis.__t09_saveCount++;
  },
  loadSettings: async () => globalThis.__t09_settings,
  saveSettings: async (s) => { globalThis.__t09_savedSettings = { ...s }; },
};

// ---- 工具 ----
const sortedDeleted = (obj) =>
  '{' + Object.keys(obj || {}).sort()
    .map((k) => `${JSON.stringify(k)}:${JSON.stringify(obj[k])}`).join(',') + '}';

const normalizeSaved = (d) =>
  '{"version":1,"tasks":[' + (d.tasks || []).map((t) => JSON.stringify(t)).join(',')
  + '],"deleted":' + sortedDeleted(d.deleted || {}) + '}';

const taskList = (list) => '[' + list.map((t) => JSON.stringify(t)).join(',') + ']';

const mkTask = (o = {}) => ({
  id: 'seed-1', title: '示例任务', note: '', date: '2026-11-13', time: '',
  important: false, urgent: false, done: false, dropped: false,
  createdAt: 1700000000000, doneAt: null, repeat: '', doneDates: [], skipDates: [],
  remind: null, parentId: '', updatedAt: 1700000000000, ...o,
});

// ---- 用例 ----
const cases = [];
const add = (name, setup, ops) => cases.push({ name, setup: setup || {}, ops });

add('empty_start', {}, []);
add('add_then_flush', {}, [
  { op: 'add', fields: { title: '开会', date: '2026-11-13' } },
  { op: 'flush' },
]);
add('update_stamp_and_tombstone', {}, [
  { op: 'add', fields: { title: '写周报', date: '2026-11-13' } },
  { op: 'flush' },
  { op: 'update', id: 't09-1', patch: { done: true } },
  { op: 'flush' },
  { op: 'remove', id: 't09-1' },
  { op: 'flush' },
]);
add('undo_delete_clears_tombstone', {}, [
  { op: 'add', fields: { title: '任务A' } },
  { op: 'flush' },
  { op: 'remove', id: 't09-1' },
  { op: 'flush' },
  { op: 'undo' },
  { op: 'flush' },
]);
add('drop_and_undo', {}, [
  { op: 'add', fields: { title: '不做了', date: '2026-11-14' } },
  { op: 'drop', id: 't09-1' },
  { op: 'flush' },
  { op: 'undo' },
  { op: 'flush' },
]);
add('toggle_one_shot', {}, [
  { op: 'add', fields: { title: '一次性' } },
  { op: 'toggle', id: 't09-1', occ: '' },
  { op: 'flush' },
  { op: 'toggle', id: 't09-1', occ: '' },
  { op: 'flush' },
]);
add('toggle_repeat_by_occ', {}, [
  { op: 'add', fields: { title: '每天喝水', date: '2026-11-01', repeat: 'd1' } },
  { op: 'toggle', id: 't09-1', occ: '2026-11-13' },
  { op: 'toggle', id: 't09-1', occ: '2026-11-14' },
  { op: 'toggle', id: 't09-1', occ: '2026-11-13' },
  { op: 'skip', id: 't09-1', occ: '2026-11-15' },
  { op: 'flush' },
  { op: 'undo' },
  { op: 'flush' },
]);
add('remove_with_children', {}, [
  { op: 'add', fields: { title: '父任务' } },
  { op: 'addSub', parentId: 't09-1', fields: { title: '子任务1' } },
  { op: 'addSub', parentId: 't09-1', fields: { title: '子任务2' } },
  { op: 'remove', id: 't09-1' },
  { op: 'flush' },
  { op: 'undo' },
  { op: 'flush' },
]);
add('subtask_progress', {}, [
  { op: 'add', fields: { title: '父任务', date: '2026-11-01', repeat: 'd1', important: true } },
  { op: 'addSub', parentId: 't09-1', fields: { title: '子1' } },
  { op: 'addSub', parentId: 't09-1', fields: { title: '子2' } },
  { op: 'toggleSub', parentId: 't09-1', childId: 't09-2', occ: '2026-11-13' },
  { op: 'toggleSub', parentId: 't09-1', childId: 't09-3', occ: '2026-11-13' },
  { op: 'flush' },
]);
add('add_defaults', {}, [
  { op: 'add', fields: { title: '有时间', time: '09:00' } },
  { op: 'add', fields: { title: '重复无日期', repeat: 'w1:135' } },
  { op: 'add', fields: { title: '显式提醒', time: '10:00', remind: 15 } },
  { op: 'add', fields: { title: '显式不提醒', time: '11:00', remind: null } },
  { op: 'flush' },
]);
add('replace_all_with_legacy_migration',
  { data: { version: 1, tasks: [mkTask({ id: 'p1', title: '旧父任务', important: true,
    subtasks: [{ id: 'c1', title: '旧子1', done: true }, { title: '旧子2' }, { title: '  ' }] })],
    deleted: {} } },
  [{ op: 'flush' }, { op: 'replaceAll', tasks: [mkTask({ id: 'n1', title: '新任务' })] }, { op: 'flush' }]);
add('settings_defaults_and_patch', {}, [
  { op: 'settings', patch: { lang: 'en', defaultRemind: 15, syncOn: true, syncCode: 'http://x#1234567890123456' } },
  { op: 'add', fields: { title: '带默认提醒', time: '09:00' } },
  { op: 'flush' },
]);
add('settings_missing_lang', { settings: { showLunar: false, defaultRemind: 30 } }, [
  { op: 'settings', patch: { remindOn: false } },
]);
add('corrupt_data', { data: '__NOT_JSON__' }, [{ op: 'flush' }]);
add('load_existing_with_deleted',
  { data: { version: 1, tasks: [mkTask({ id: 'a' })], deleted: { gone: 1600000000000 } } },
  [{ op: 'add', fields: { title: '新任务' } }, { op: 'flush' }]);
add('sync_payload', {}, [
  { op: 'add', fields: { title: 'A' } },
  { op: 'payload' },
  { op: 'update', id: 't09-1', patch: { title: 'A2' } },
  { op: 'payload' },
  { op: 'flush' },
]);
add('apply_remote_newer_remote',
  { data: { version: 1, tasks: [mkTask({ id: 'a', title: '本地', updatedAt: 1000 })], deleted: {} } },
  [{ op: 'remote', state: { tasks: [mkTask({ id: 'a', title: '远端', updatedAt: 2000 })], deleted: {} } },
   { op: 'flush' }]);
add('apply_remote_tombstone_and_revive',
  { data: { version: 1, tasks: [mkTask({ id: 'a', title: '本地', updatedAt: 1000 })], deleted: {} } },
  [{ op: 'remote', state: { tasks: [], deleted: { a: 3000 } } },
   { op: 'flush' },
   { op: 'replaceAll', tasks: [mkTask({ id: 'a', title: '复活', updatedAt: 4000 })] },
   { op: 'flush' }]);
add('apply_remote_adds_task',
  { data: { version: 1, tasks: [], deleted: {} } },
  [{ op: 'remote', state: { tasks: [mkTask({ id: 'r1', title: '来自服务器', updatedAt: 5000 })], deleted: {} } },
   { op: 'flush' }]);
add('normalize_dirty_values', {}, [
  { op: 'replaceAll', tasks: [{
      id: 'd1', title: '  脏数据  ', note: 5, date: 'bad', time: '25:99',
      // doneAt 不放脏字符串：T-04 的 PlannerTask.normalize 已登记「脏值按 null 处理」
      // 这一有意窄化（§2.5.1 类型约束），不属 T-09 状态机范围。
      important: 1, urgent: 'yes', done: 0, dropped: true, createdAt: 0,
      doneAt: 1700000001000, repeat: 'daily', doneDates: ['2026-11-13', 'x', 7],
      skipDates: ['2026-11-14'], remind: -1, parentId: 0, updatedAt: 0,
    }] },
  { op: 'flush' },
]);
add('counts_and_children_sort', {}, [
  { op: 'add', fields: { title: '父' } },
  { op: 'addSub', parentId: 't09-1', fields: { title: '子B' } },
  { op: 'addSub', parentId: 't09-1', fields: { title: '子A' } },
  { op: 'flush' },
]);

// ---- 执行 ----
const outCases = [];
for (let idx = 0; idx < cases.length; idx++) {
  const c = cases[idx];
  globalThis.__t09_nextId = 1;
  globalThis.__t09_data = c.setup.data ?? { version: 1, tasks: [] };
  globalThis.__t09_settings = c.setup.settings ?? {};
  globalThis.__t09_saved = null;
  globalThis.__t09_savedSettings = null;
  globalThis.__t09_saveCount = 0;
  globalThis.__t09_corrupt = 0;

  const store = await import(pathToFileURL(oraclePath).href + `?case=${idx}`);
  await store.initStore();

  const undos = [];
  let lastPayload = null;
  for (const op of c.ops) {
    switch (op.op) {
      case 'add': store.addTask(op.fields); break;
      case 'update': store.updateTask(op.id, op.patch); break;
      case 'drop': undos.push(store.dropTask(op.id)); break;
      case 'toggle': store.toggleDone(op.id, op.occ); break;
      case 'skip': undos.push(store.skipOccurrence(op.id, op.occ)); break;
      case 'remove': undos.push(store.removeTask(op.id)); break;
      case 'addSub': store.addSubtask(op.parentId, op.fields); break;
      case 'toggleSub': store.toggleSubtask(op.parentId, op.childId, op.occ); break;
      case 'replaceAll': store.replaceAll(op.tasks); break;
      case 'flush': store.flush(); break;
      // syncPayload 返回的是 state.tasks 的引用，后续操作会改到同一批对象；深拷贝固定快照。
      case 'payload': lastPayload = JSON.parse(JSON.stringify(store.syncPayload())); break;
      case 'remote': store.applyRemote(op.state); break;
      case 'settings':
        Object.assign(store.state.settings, op.patch);
        await globalThis.__t09_storage.saveSettings(store.state.settings);
        break;
      case 'undo': undos.pop()?.(); break;
      default: throw new Error(`未知 op：${op.op}`);
    }
  }

  outCases.push({
    name: c.name,
    setup: c.setup,
    ops: c.ops,
    expect: {
      tasks: taskList(store.state.tasks),
      deleted: sortedDeleted(store.state.deleted),
      settings: JSON.stringify(store.state.settings),
      savedData: globalThis.__t09_saved ? normalizeSaved(globalThis.__t09_saved) : null,
      savedSettings: globalThis.__t09_savedSettings ? JSON.stringify(globalThis.__t09_savedSettings) : null,
      corruptCount: globalThis.__t09_corrupt,
      payload: lastPayload
        ? { tasks: taskList(lastPayload.tasks), deleted: sortedDeleted(lastPayload.deleted) }
        : null,
    },
  });
}

const out = {
  meta: {
    baseline_commit: BASELINE,
    generator: 'ios/PlannerTests/Fixtures/generate_store_fixtures.mjs',
    oracle: '/tmp/t09_oracle/store.mjs (运行副本，仅替换 5 处环境依赖)',
    oracle_changed_lines: changedLines,
    fixed_local_now: '2026-11-13T12:00:00',
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    case_count: outCases.length,
    note: 'id 由确定性 randomUUID 生成（t09-1, t09-2 ...），每个 case 重置；deleted/savedData 按 key 排序规范化。',
  },
  cases: outCases,
};
const dest = resolve(here, 'store_fixtures.json');
writeFileSync(dest, JSON.stringify(out, null, 2) + '\n');
console.log(`wrote ${dest}: ${outCases.length} cases, oracle changed ${changedLines} lines, tz=${out.meta.timezone}`);
