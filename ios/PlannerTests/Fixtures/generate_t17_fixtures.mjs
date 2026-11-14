#!/usr/bin/env node
// T-17 / M-13 + M-14 契约黄金夹具生成器。
//
// oracle = baseline_commit 97a7c4c 的真实源码：
// · src/lib/parse.js（自然语言解析，25 条 selfTest 同源）、date.js、repeat.js、
//   quadrant.js、i18n.js / i18n-en*.js —— 直接 import，不复制、不改写。
// · QuickAdd.vue:32-122 / TaskDetail.vue:28-219 的 computed 因依赖 Vue 响应式与 DOM，
//   在下方按源码逐行复刻（每段标注源位置），函数体与上游一致。
//
// 无参 `new Date()` 固定为本地 2026-11-13 12:00:00（T-08 的做法）。
//
// 用法：node ios/PlannerTests/Fixtures/generate_t17_fixtures.mjs
// 输出：ios/PlannerTests/Fixtures/t17_fixtures.json

import { writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../../..');
const importFromRoot = (p) => import(pathToFileURL(resolve(root, p)).href);

const RealDate = Date;
const FIXED = new RealDate(2026, 10, 13, 12, 0, 0);
class FixedDate extends RealDate {
  constructor(...args) { super(...(args.length ? args : [FIXED.getTime()])); }
  static now() { return FIXED.getTime(); }
}
globalThis.Date = FixedDate;

const { parseInput } = await importFromRoot('src/lib/parse.js');
const date = await importFromRoot('src/lib/date.js');
const rep = await importFromRoot('src/lib/repeat.js');
const quad = await importFromRoot('src/lib/quadrant.js');
const { t, i18n, isEn } = await importFromRoot('src/lib/i18n.js');

const BASELINE = '97a7c4c17602327a42d30110806a6a1e6fa0e798';
const TODAY = '2026-11-13';
if (date.today() !== TODAY) throw new Error(`固定日期失败：${date.today()}`);
const setLang = (l) => { i18n.lang = l; };
const ms = (y, m, d, h = 10, min = 0) => new RealDate(y, m - 1, d, h, min).getTime();

// ---- 任务语料 ----
const mkTask = (o = {}) => ({
  id: 't1', title: '示例任务', note: '', date: '', time: '',
  important: false, urgent: false, done: false, dropped: false,
  createdAt: ms(2026, 11, 1, 9, 15), doneAt: null, repeat: '',
  doneDates: [], skipDates: [], remind: null, parentId: '', updatedAt: ms(2026, 11, 1, 9, 15),
  ...o,
});
const TASKS = [
  mkTask({ id: 'plain', title: '写周报', note: '记得 附上 数据', date: TODAY, time: '14:00', important: true, urgent: true, remind: 15 }),
  mkTask({ id: 'nodate', title: '随手记', date: '', time: '' }),
  mkTask({ id: 'done', title: '已完成的报告', date: date.addDays(TODAY, -1), done: true, doneAt: ms(2026, 11, 12, 16, 40) }),
  mkTask({ id: 'dropped', title: '放弃的旧计划', date: date.addDays(TODAY, -3), done: true, dropped: true, doneAt: ms(2026, 11, 10, 8, 5) }),
  mkTask({ id: 'repeat', title: '每天背单词', date: date.addDays(TODAY, -10), time: '07:30', repeat: 'd1',
           doneDates: [TODAY, date.addDays(TODAY, -1), date.addDays(TODAY, -2)] }),
  mkTask({ id: 'repeat-until', title: '每周五复盘', date: '2026-10-02', repeat: 'w1:5~2026-12-31', doneDates: ['2026-11-06'] }),
  mkTask({ id: 'parent', title: '准备发布会', date: TODAY, important: true }),
  mkTask({ id: 'child-one', title: '订场地', date: TODAY, parentId: 'parent' }),
  mkTask({ id: 'child-repeat', title: '发提醒', parentId: 'repeat', doneDates: [TODAY] }),
  mkTask({ id: 'child-dropped', title: '不做的子任务', parentId: 'parent', done: true, dropped: true }),
];
const findTask = (id) => TASKS.find((x) => x.id === id) ?? null;

// ---- QuickAdd.vue:32-122 ----
const opened = (defaults) => ({
  text: '', note: '', showNote: false,
  date: defaults.date ?? date.today(), time: '', q: defaults.q ?? 4,
  repeat: defaults.repeat ?? '',
  manual: { date: false, time: false, repeat: false },
  useParse: true, panel: null,
});
const quickAddOracle = (c) => {
  const s = opened(c.defaults ?? {});
  s.text = c.text ?? '';
  s.note = c.note ?? '';
  s.useParse = c.useParse ?? true;
  if (c.state) Object.assign(s, c.state);
  if (c.manual) Object.assign(s.manual, c.manual);
  const parsed = s.useParse ? parseInput(s.text)
    : { title: s.text.trim(), date: '', time: '', repeat: '', hits: [] };
  const effDate = s.manual.date ? s.date : (parsed.date || s.date);
  const effTime = s.manual.time ? s.time : (parsed.time || s.time);
  const effRepeat = s.manual.repeat ? s.repeat : (parsed.repeat || s.repeat);
  const recognized = parsed.hits.length > 0 && !(s.manual.date && s.manual.time && s.manual.repeat);
  const whenLabel = effRepeat ? rep.repeatLabel(effRepeat, effDate) : effDate ? date.dateLabel(effDate) : '';
  const when = [whenLabel, effTime].filter(Boolean).join(' ');
  const msg = t('已识别 {when}，标题「{title}」', { title: parsed.title });
  const i = msg.indexOf('{when}');
  const flags = quad.quadrantFlags(s.q);
  return {
    title: parsed.title, parsedDate: parsed.date, parsedTime: parsed.time,
    parsedRepeat: parsed.repeat, hits: parsed.hits,
    effDate, effTime, effRepeat, recognized, whenLabel, when,
    before: msg.slice(0, i), after: msg.slice(i + 6),
    canSend: s.text.trim().length > 0,
    submit: {
      title: parsed.title, note: s.note, date: effDate, time: effTime,
      repeat: effRepeat, important: flags.important, urgent: flags.urgent,
    },
    toast: effRepeat ? t('已添加 · {when}', { when })
      : effDate ? t('已添加到{when}', { when: whenLabel })
      : t('已添加（无日期）'),
  };
};
const QUICK_CASES = [
  { name: 'plain', text: '买牛奶' },
  { name: 'parsed-tomorrow', text: '明天下午3点开会' },
  { name: 'parsed-repeat', text: '每天 跑步 到12月31日' },
  { name: 'parsed-week', text: '下周一 9:30 例会' },
  { name: 'default-date-q', text: '写方案', defaults: { date: date.addDays(TODAY, 2), q: 1 } },
  { name: 'default-repeat', text: '喝水', defaults: { repeat: 'd1' } },
  { name: 'default-repeat-no-date', text: '喝水', defaults: { repeat: 'd1', date: '' } },
  { name: 'manual-date', text: '明天 交报告', state: { date: '2026-11-20' }, manual: { date: true } },
  { name: 'manual-time', text: '明天下午3点 买菜', state: { time: '20:00' }, manual: { time: true } },
  { name: 'manual-repeat', text: '每天 跑步', state: { repeat: 'w1:135' }, manual: { repeat: true } },
  { name: 'manual-all', text: '明天下午3点 每天 跑步',
    state: { date: '2026-11-18', time: '08:00', repeat: 'd3' },
    manual: { date: true, time: true, repeat: true } },
  { name: 'undo-parse', text: '明天 交报告', useParse: false },
  { name: 'empty', text: '' },
  { name: 'spaces', text: '   ' },
  { name: 'no-date', text: '随手记', state: { date: '' } },
  { name: 'with-note', text: '写周报', note: '带上 数据 附件' },
  { name: 'monthly', text: '每月15号还信用卡' },
  { name: 'yearly', text: '每年5月20日 纪念日' },
];
const quickCases = [];
for (const lang of ['zh', 'en']) {
  setLang(lang);
  for (const c of QUICK_CASES) {
    quickCases.push({ name: c.name, lang, case: c, expected: quickAddOracle(c) });
  }
}
setLang('zh');

// ---- TaskDetail.vue:28-219 ----
const perOcc = (parent, child, occ) => !!(parent?.repeat && occ && !child.date);
const subDone = (parent, child, occ) => (perOcc(parent, child, occ) ? child.doneDates.includes(occ) : child.done);
const childrenOf = (id) => TASKS.filter((t) => t.parentId === id).sort((a, b) => a.createdAt - b.createdAt);
const subProgress = (parent, occ) => {
  const kids = childrenOf(parent.id).filter((c) => !c.dropped);
  return [kids.filter((c) => subDone(parent, c, occ)).length, kids.length];
};
const fmt = (m) => {
  const d = new Date(m);
  return `${date.monthDay(d)}${isEn() ? ',' : ''} ${date.pad(d.getHours())}:${date.pad(d.getMinutes())}`;
};
const dateText = (task) => {
  const d = task.date;
  if (!d) return t('无日期');
  const rel = date.dateLabel(d);
  const p = date.parseYmd(d);
  const md = date.monthDay(p);
  const wd = date.weekdayName(p.getDay());
  const full = isEn() ? `${wd}, ${md}` : `${md} ${wd}`;
  return rel === md || (isEn() && rel === wd) ? full : `${rel} · ${full}`;
};
const remindLabel = (m) => {
  if (m === null || m === undefined) return t('不提醒');
  if (m === 0) return t('准时');
  if (m >= 60) return t('提前 {n} 小时', { n: m / 60 });
  return t('提前 {n} 分钟', { n: m });
};
const deleteMessage = (name, kids, isRepeat) => {
  const p = { title: name, n: kids };
  return isRepeat && kids ? t('已删除「{title}」及以后的重复和{n} 个子任务', p)
    : isRepeat ? t('已删除「{title}」及以后的重复', p)
    : kids ? t('已删除「{title}」及{n} 个子任务', p)
    : t('已删除「{title}」', p);
};
const detailOracle = (c) => {
  const t0 = findTask(c.rootId);
  const parent = t0?.parentId ? findTask(t0.parentId) : null;
  const occOf = (task) => task?.repeat
    ? ((task.id === c.rootId && c.rootOcc) || rep.nextOccurrence(task, date.today()))
    : '';
  const occDay = occOf(t0);
  const parentOcc = occOf(parent);
  const done = parent ? subDone(parent, t0, parentOcc)
    : t0.repeat ? t0.doneDates.includes(occDay) : t0.done;
  const canDrop = !!t0 && !t0.repeat && !t0.done && !(parent?.repeat && !t0.date);
  const prog = t0 && !t0.parentId ? subProgress(t0, occDay) : [0, 0];
  const footer = t('创建于 {time}', { time: fmt(t0.createdAt) })
    + (t0.repeat ? ` · ${t('已完成 {n} 次', { n: t0.doneDates.length })}`
      : t0.doneAt && !t0.dropped ? ` · ${t('完成于 {time}', { time: fmt(t0.doneAt) })}` : '');
  const kids = childrenOf(t0.id);
  return {
    occDay, parentOcc, isDone: done, canDrop,
    dateText: dateText(t0),
    footer,
    remindValue: !t0.time ? t('先设时间') : remindLabel(t0.remind),
    repeatValue: t0.repeat ? rep.repeatLabel(t0.repeat, t0.date, true) : t('不重复'),
    droppedText: t('已放弃 · {time}', { time: fmt(t0.doneAt ?? 0) }),
    progress: prog,
    subView: kids.map((c2) => ({ id: c2.id, done: subDone(t0, c2, occDay) })),
    deleteMessages: [
      deleteMessage(t0.title, 0, false),
      deleteMessage(t0.title, 2, false),
      deleteMessage(t0.title, 0, true),
      deleteMessage(t0.title, 3, true),
    ],
  };
};
const DETAIL_CASES = [
  { name: 'plain', rootId: 'plain', rootOcc: '' },
  { name: 'nodate', rootId: 'nodate', rootOcc: '' },
  { name: 'done', rootId: 'done', rootOcc: '' },
  { name: 'dropped', rootId: 'dropped', rootOcc: '' },
  { name: 'repeat', rootId: 'repeat', rootOcc: '' },
  { name: 'repeat-occ', rootId: 'repeat', rootOcc: date.addDays(TODAY, -1) },
  { name: 'repeat-until', rootId: 'repeat-until', rootOcc: '' },
  { name: 'parent', rootId: 'parent', rootOcc: '' },
  { name: 'child-one', rootId: 'child-one', rootOcc: '' },
  { name: 'child-repeat', rootId: 'child-repeat', rootOcc: '' },
];
const detailCases = [];
for (const lang of ['zh', 'en']) {
  setLang(lang);
  for (const c of DETAIL_CASES) {
    detailCases.push({ name: c.name, lang, case: c, expected: detailOracle(c) });
  }
}
setLang('zh');

// ---- TaskDetail.vue:pushSub / goBack 的导航栈行为 ----
const navCases = [
  { name: 'push-pop', rootId: 'parent', actions: ['push:child-one', 'back'], expected: ['child-one', 'parent'] },
  { name: 'root-child-back-to-parent', rootId: 'child-one', actions: ['back'], expected: ['parent'] },
  { name: 'two-level', rootId: 'parent', actions: ['push:child-one', 'push:child-one', 'back', 'back'],
    expected: ['child-one', 'child-one', 'child-one', 'parent'] },
];

// ---- 词条（函数值 + 详情/快速添加专属纯字符串） ----
const STRING_KEYS = [
  ['未命名任务', {}], ['任务标题', {}], ['已放弃 · {time}', { time: '11月10日 08:05' }],
  ['开始日期', {}], ['先设时间', {}], ['已关闭全部提醒', {}], ['不重复', {}],
  ['子任务', {}], ['添加子任务，可以写“明天下午3点 买菜”', {}],
  ['象限', {}], ['备注', {}], ['添加备注…', {}],
  ['创建于 {time}', { time: '11月1日 09:15' }],
  ['已完成 {n} 次', { n: 1 }], ['已完成 {n} 次', { n: 7 }],
  ['完成于 {time}', { time: '11月12日 16:40' }],
  ['子任务都完成了', {}], ['完成任务', {}],
  ['已删除子任务「{title}」', { title: '订场地' }],
  ['已删除「{title}」', { title: '写周报' }],
  ['已删除「{title}」及以后的重复', { title: '每天背单词' }],
  ['已删除「{title}」及{n} 个子任务', { title: '准备发布会', n: 2 }],
  ['已删除「{title}」及以后的重复和{n} 个子任务', { title: '每天背单词', n: 1 }],
  ['已放弃「{title}」', { title: '写周报' }],
  ['准备做点什么？', {}],
  ['已识别 {when}，标题「{title}」', { title: '买菜' }],
  ['撤销识别', {}], ['添加', {}],
  ['已添加 · {when}', { when: '每天 07:30' }],
  ['已添加到{when}', { when: '明天' }],
  ['已添加（无日期）', {}],
  ['不提醒', {}], ['准时', {}],
  ['提前 {n} 小时', { n: 1 }], ['提前 {n} 分钟', { n: 15 }],
];
const stringCases = [];
for (const lang of ['zh', 'en']) {
  setLang(lang);
  for (const [key, params] of STRING_KEYS) {
    stringCases.push({ key, lang, params, value: t(key, params) });
  }
}
setLang('zh');

const out = {
  baseline: BASELINE,
  generator: 'generate_t17_fixtures.mjs',
  today: TODAY,
  fixedLocalTime: '2026-11-13T12:00:00',
  tasks: TASKS,
  quickAdd: quickCases,
  detail: detailCases,
  nav: navCases,
  strings: stringCases,
};
writeFileSync(resolve(here, 't17_fixtures.json'), JSON.stringify(out, null, 2) + '\n');
console.log(`wrote t17_fixtures.json: ${TASKS.length} tasks, ${quickCases.length} quickAdd, ${detailCases.length} detail, ${navCases.length} nav, ${stringCases.length} strings`);
