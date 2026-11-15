#!/usr/bin/env node
// T-19 / M-23 全量本地化契约黄金夹具生成器。
//
// oracle = baseline_commit 97a7c4c 的真实源码：
// · src/lib/i18n-en.js（含 calendar / sheets / pages 三组）—— 直接 import，拿最终生效的
//   211 个词条键（同名键按 core → calendar → sheets → pages 的覆盖顺序，与运行时一致）；
// · src/lib/i18n.js:t / applyLang / plural —— 为覆盖「缺失词条回退」分支，只把该文件复制成
//   /tmp/t19_oracle/i18n.mjs 并替换 3 处环境依赖（vue:reactive、import.meta.env.DEV、
//   相对 import 改绝对 URL），函数体逐字未改；替换次数在下方断言。
//   与 §7.2.2 的 T-03 做法一致（那里替换 2 处，这里多 1 处相对 import）。
//
// 用法：node ios/PlannerTests/Fixtures/generate_t19_fixtures.mjs
// 产出：
//   ios/PlannerTests/Fixtures/t19_fixtures.json
//   ios/Planner/Localization/LocalizationDictionary.swift（纯字符串词条，勿手改）

import { writeFileSync, readFileSync, mkdirSync, readdirSync, statSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../../..');
const importFromRoot = (p) => import(pathToFileURL(resolve(root, p)).href);
const BASELINE = '97a7c4c17602327a42d30110806a6a1e6fa0e798';

// ---- 1. oracle 运行副本（只替换环境依赖，函数体逐字未改） ----
const oracleDir = '/tmp/t19_oracle';
mkdirSync(oracleDir, { recursive: true });
let i18nSource = readFileSync(resolve(root, 'src/lib/i18n.js'), 'utf8');
const patches = [
  ["import { reactive } from 'vue';", 'const reactive = (x) => x;'],
  ["import EN from './i18n-en.js';",
   `import EN from '${pathToFileURL(resolve(root, 'src/lib/i18n-en.js')).href}';`],
  ['import.meta.env.DEV', 'false'],
];
for (const [from, to] of patches) {
  if (!i18nSource.includes(from)) throw new Error(`oracle 环境依赖未找到：${from}`);
  if (i18nSource.split(from).length !== 2) throw new Error(`oracle 环境依赖出现多次：${from}`);
  i18nSource = i18nSource.replace(from, to);
}
writeFileSync(join(oracleDir, 'i18n.mjs'), i18nSource);

const { t, i18n, applyLang, plural } =
  await import(pathToFileURL(join(oracleDir, 'i18n.mjs')).href);
const { default: EN } = await importFromRoot('src/lib/i18n-en.js');

// applyLang 会读写 navigator.language 与 document.documentElement.lang（浏览器环境）。
// DOM shim 必须在所有 ESM import 之后再装：i18n-en/*.js 会间接加载真实 i18n.js → vue，
// vue 的 runtime-dom 在模块加载阶段读 globalThis.document，提前伪造会因缺 createElement 崩溃。
Object.defineProperty(globalThis, 'document', {
  value: { documentElement: {} }, configurable: true, writable: true,
});
const setSystemLanguage = (raw) => Object.defineProperty(globalThis, 'navigator', {
  value: { language: raw }, configurable: true, writable: true,
});
setSystemLanguage('zh-CN');

const keys = Object.keys(EN);
const functionKeys = keys.filter((k) => typeof EN[k] === 'function');
const stringKeys = keys.filter((k) => typeof EN[k] === 'string');
if (keys.length !== new Set(keys).size) throw new Error('上游词典出现重复键');

// ---- 2. 逐词条的参数组合 ----
// 数字类占位符必须传 number：上游 plural / `p.n === 1` / `p.m - 1` 用严格相等与算术，
// 传字符串会与真实调用（{ n: count }）不等价。
const NUMERIC = new Set(['n', 'a', 'b', 'm', 'y', 'done', 'total']);
const VALUES = {
  n: [0, 1, 2, 5],
  a: [1, 3, 7, 2],
  b: [2, 7, 1, 4],
  m: [1, 6, 12, 3],
  y: [2026, 2027, 2000, 2031],
  done: [0, 1, 3, 5],
  total: [1, 3, 8, 12],
  date: ['Tomorrow', 'Today', '2026-11-20', 'Next Monday'],
  time: ['14:00', '09:30', '2026-11-13 08:00', '23:59'],
  title: ['写周报', 'Buy milk', '季度复盘', 'A & B'],
  when: ['明天下午3点', 'tomorrow 3pm', '每周五', 'no date'],
  q: ['会议', 'report', '周报 复核', ''],
  name: ['重要且紧急', 'Matrix', '计划去做', 'Critical'],
  msg: ['令牌不对', 'Timeout', '404', ''],
  host: ['192.168.1.5', 'example.com', 'localhost', '10.0.0.2'],
  code: ['401', '500', '200', '0'],
  occ: ['2026-11-13', '2026-11-14', '', '2026-12-01'],
};
const fallback = ['甲', '乙', '丙', '丁'];

const paramsForKey = (key, variant) => {
  const names = [...new Set([...key.matchAll(/\{(\w+)\}/g)].map((m) => m[1]))];
  const out = {};
  for (const name of names) {
    const vals = VALUES[name] || fallback;
    out[name] = vals[variant % vals.length];
  }
  return out;
};

const entries = [];
for (const key of keys) {
  for (const lang of ['zh', 'en']) {
    i18n.lang = lang;
    for (let v = 0; v < 4; v++) {
      const params = paramsForKey(key, v);
      entries.push({ key, lang, params, expected: t(key, params) });
    }
  }
}

// ---- 3. 缺失回退 / 未知占位符（i18n.js:21-28） ----
const missingCases = [];
i18n.lang = 'en';
for (const [key, params] of [
  ['未登记词条 {x}', { x: '甲' }],
  ['未知占位 {known} 与 {unknown}', { known: 'K' }],
  ['共 {n} 项', {}],
]) {
  missingCases.push({ key, params, lang: i18n.lang, expected: t(key, params) });
}
i18n.lang = 'zh';
for (const [key, params] of [
  ['未登记词条 {x}', { x: '甲' }],
  ['未知占位 {known} 与 {unknown}', { known: 'K' }],
]) {
  missingCases.push({ key, params, lang: i18n.lang, expected: t(key, params) });
}

// ---- 4. 语言判定 / 切换（applyLang + systemLang，真实源码执行） ----
const langCases = [];
for (const system of ['zh', 'zh-CN', 'zh-Hans', 'zhHans', 'en', 'en-US', 'fr', '', 'ZH-tw', 'zh_TW']) {
  setSystemLanguage(system);
  for (const pref of ['auto', 'zh', 'en', 'xx']) {
    applyLang(pref);
    langCases.push({
      system, pref, expected: i18n.lang,
      htmlLang: globalThis.document.documentElement.lang,
    });
  }
}
setSystemLanguage('zh-CN');
applyLang('auto');

// ---- 5. plural / 术语表 ----
const pluralCases = [
  [1, 'task', null], [0, 'task', null], [2, 'task', null], [5, 'hour', null],
  [1, 'routine', null], [3, 'subtask', null], [1, 'task', 'tasks'],
  [2, 'current task', 'current tasks'],
].map(([n, one, many]) => ({
  n, one, many, expected: many === null ? plural(n, one) : plural(n, one, many),
}));

// i18n-en.js 顶部 Glossary 的固定译法；逐字断言，不允许界面另造词。
const GLOSSARY = {
  日程: 'Calendar', 四象限: 'Matrix', 打卡: 'Routines', 我的: 'Me',
  提醒: 'Reminder', 重复: 'Repeat', 备注: 'Notes', 象限: 'Quadrant',
  放弃: 'Drop', 推迟: 'Postpone', 跳过: 'Skip', 恢复: 'Restore',
  连接码: 'Connection code', 导出备份: 'Export backup', 未命名任务: 'Untitled task',
};
const glossaryCases = [];
i18n.lang = 'en';
for (const [key, expected] of Object.entries(GLOSSARY)) {
  const got = t(key);
  if (got !== expected) throw new Error(`术语表不一致：${key} → ${got}，期望 ${expected}`);
  glossaryCases.push({ key, expected: got });
}

// ---- 6. 扫描 Swift 调用点，登记全部界面 key（用于「无缺失词条」断言） ----
const walk = (dir) => readdirSync(dir).flatMap((name) => {
  const p = join(dir, name);
  return statSync(p).isDirectory() ? walk(p) : (p.endsWith('.swift') ? [p] : []);
});
const callSiteKeys = new Set();
for (const file of walk(resolve(root, 'ios/Planner'))) {
  const src = readFileSync(file, 'utf8');
  // 只取字面量 key；变量 key（AppStrings.t(key, ...)）由业务代码自行保证来源合法。
  const re = /(?:AppStrings\.t|FeatureStrings\.[ts]|LocalizationService\.t|ReachText)\(\s*"((?:[^"\\]|\\.)*)"/g;
  for (const m of src.matchAll(re)) callSiteKeys.add(m[1]);
}
const callSiteList = [...callSiteKeys].sort();
const callSiteNotUpstream = callSiteList.filter((k) => !keys.includes(k));

// ---- 7. DEV / 自检页词条（上游不存在，不并入业务词典） ----
const DEV_STRINGS = {
  '设计系统自检': 'Design system check',
  '当前主题': 'Appearance',
  '浅色': 'Light',
  '深色': 'Dark',
  '色板': 'Palette',
  '自定义图标': 'Custom icons',
  '反馈层': 'Feedback',
  '普通提示': 'Show toast',
  '带撤销提示': 'Show undo toast',
  '系统弹窗': 'System sheet',
  '触感反馈': 'Haptics',
  '已撤销': 'Undone',
  '已删除一条任务': 'Task deleted',
  '骨架占位': 'Skeleton placeholder',
  '查看 T-03 原型': 'Open T-03 prototype',
  '查看 T-02 占位页': 'Open T-02 placeholder',
  '关闭': 'Close',
  '系统材质与玻璃': 'System materials & glass',
  '个图标': 'icons',
  '版本': 'Version',
  '系统弹窗由 SwiftUI .sheet 提供下滑关闭': 'System sheet provides swipe-to-dismiss',
  '骨架页，业务视图待 T-14 ~ T-17': 'Skeleton page; feature views arrive in T-14 ~ T-17',
  '任务行预览': 'Task row preview',
  '组件预览': 'Component preview',
  '示例任务': 'Sample task',
  '滑动试试：右滑完成，左滑推迟/放弃/删除': 'Try swiping: right to complete, left for postpone / drop / delete',
  '属性面板': 'Property panels',
  'T-14 组件预览，真实日历由 T-15 接入': 'T-14 component preview; the real calendar arrives in T-15',
  '查看 T-14 组件预览': 'Open T-14 component preview',
  '取消': 'Cancel',
};
const devNotCovered = callSiteNotUpstream.filter((k) => !(k in DEV_STRINGS));
if (devNotCovered.length) {
  throw new Error(`界面调用点存在既不在上游词典、也不在 DEV 词典的 key：${devNotCovered.join(' | ')}`);
}

// ---- 8. 输出 fixture ----
const fixture = {
  baseline: BASELINE,
  generatedBy: 'node ios/PlannerTests/Fixtures/generate_t19_fixtures.mjs',
  oracle: 'src/lib/i18n.js + src/lib/i18n-en.js + i18n-en/{calendar,sheets,pages}.js',
  dictionaryKeys: keys,
  stringKeys,
  functionKeys,
  entries,
  missingCases,
  langCases,
  pluralCases,
  glossaryCases,
  callSiteKeys: callSiteList,
  callSiteNotUpstream,
};
writeFileSync(join(here, 't19_fixtures.json'), JSON.stringify(fixture, null, 2) + '\n');

// ---- 9. 生成 Swift 纯字符串词典 ----
const swiftLiteral = (s) => '"' + String(s)
  .replace(/\\/g, '\\\\')
  .replace(/"/g, '\\"')
  .replace(/\n/g, '\\n')
  .replace(/\r/g, '\\r')
  .replace(/\t/g, '\\t')
  .replace(/\u2028/g, '\\u{2028}')
  .replace(/\u2029/g, '\\u{2029}') + '"';

const dictLines = [];
dictLines.push('// 由 generate_t19_fixtures.mjs 从 baseline 97a7c4c 的上游词典生成，请勿手改。');
dictLines.push('// 生成命令：node ios/PlannerTests/Fixtures/generate_t19_fixtures.mjs');
dictLines.push('// 值含函数的词条不在此表，见 LocalizationFunctions.swift。');
dictLines.push('');
dictLines.push('import Foundation');
dictLines.push('');
dictLines.push('enum LocalizationDictionary {');
dictLines.push(`    /// 上游 ${stringKeys.length} 条纯字符串词条（中文原文为键）。`);
dictLines.push('    static let english: [String: String] = [');
for (const k of stringKeys) dictLines.push(`        ${swiftLiteral(k)}: ${swiftLiteral(EN[k])},`);
dictLines.push('    ]');
dictLines.push('');
dictLines.push(`    /// 上游全部 ${keys.length} 个 key（含 ${functionKeys.length} 条函数值），供覆盖检查。`);
dictLines.push('    static let allKeys: Set<String> = [');
for (const k of keys) dictLines.push(`        ${swiftLiteral(k)},`);
dictLines.push('    ]');
dictLines.push('');
dictLines.push(`    /// 自检页 / 原型页专用 ${Object.keys(DEV_STRINGS).length} 条 DEV 词条，上游不存在。`);
dictLines.push('    /// 与业务词典分开，避免污染「全界面词条无缺失」的判定。');
dictLines.push('    static let dev: [String: String] = [');
for (const [k, v] of Object.entries(DEV_STRINGS)) dictLines.push(`        ${swiftLiteral(k)}: ${swiftLiteral(v)},`);
dictLines.push('    ]');
dictLines.push('}');
dictLines.push('');
writeFileSync(resolve(root, 'ios/Planner/Localization/LocalizationDictionary.swift'), dictLines.join('\n'));

console.log(`baseline           : ${BASELINE}`);
console.log(`dictionary keys    : ${keys.length} (string ${stringKeys.length} / function ${functionKeys.length})`);
console.log(`fixture entries    : ${entries.length}`);
console.log(`lang/plural/gloss  : ${langCases.length} / ${pluralCases.length} / ${glossaryCases.length}`);
console.log(`call-site keys     : ${callSiteList.length} (not upstream: ${callSiteNotUpstream.length}, all in DEV)`);
console.log('wrote t19_fixtures.json + LocalizationDictionary.swift');
