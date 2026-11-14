#!/usr/bin/env node
// T-16 / M-11 + M-12 + M-16 + M-17 契约黄金夹具生成器。
//
// oracle = baseline_commit 97a7c4c 的真实源码：
// · src/lib/date.js / repeat.js / quadrant.js / i18n.js / i18n-en*.js —— 直接 import，
//   不复制、不改写；语言通过 i18n.lang 切换。
// · QuadrantView.vue / RoutineView.vue / SearchSheet.vue / MeView.vue 的 computed 因依赖
//   Vue 响应式与 DOM，在下方按源码逐行复刻（每段标注源位置），函数体与上游一致。
//
// 无参 `new Date()` 固定为**本地** 2026-11-13 12:00:00（T-08 的做法），
// 带参数构造原样透传；Swift 侧用同一本地时刻注入 PlannerCalendar / dateLabel。
//
// 用法：node ios/PlannerTests/Fixtures/generate_t16_fixtures.mjs
// 输出：ios/PlannerTests/Fixtures/t16_fixtures.json

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

const date = await importFromRoot('src/lib/date.js');
const rep = await importFromRoot('src/lib/repeat.js');
const quad = await importFromRoot('src/lib/quadrant.js');
const { t, i18n } = await importFromRoot('src/lib/i18n.js');

const BASELINE = '97a7c4c17602327a42d30110806a6a1e6fa0e798';
const TODAY = '2026-11-13';
if (date.today() !== TODAY) throw new Error(`固定日期失败：${date.today()}`);
const setLang = (l) => { i18n.lang = l; };
const ms = (y, m, d, h = 10, min = 0) => new RealDate(y, m - 1, d, h, min).getTime();

// ---- 任务语料（与 Swift 侧 PlannerTask.normalize 的输入一致） ----
const mkTask = (o = {}) => ({
  id: 't1', title: '示例任务', note: '', date: '', time: '',
  important: false, urgent: false, done: false, dropped: false,
  createdAt: ms(2026, 11, 1), doneAt: null, repeat: '',
  doneDates: [], skipDates: [], remind: null, parentId: '', updatedAt: ms(2026, 11, 1),
  ...o,
});
const TASKS = [
  mkTask({ id: 'q1-open', title: '交季度报表', note: '财务 报表 复核', date: TODAY, time: '09:00', important: true, urgent: true }),
  mkTask({ id: 'q2-open', title: '写规划文档', note: '长期 规划', date: date.addDays(TODAY, 3), time: '14:00', important: true, createdAt: ms(2026, 11, 2) }),
  mkTask({ id: 'q3-open', title: '回复客户电话', date: date.addDays(TODAY, -2), urgent: true }),
  mkTask({ id: 'q4-open', title: '整理桌面', date: date.addDays(TODAY, 9) }),
  mkTask({ id: 'no-date', title: '随手记 会议想法', note: '没有日期 也可以搜索' }),
  mkTask({ id: 'done-one', title: '完成的项目报告', note: '报告 已归档', date: TODAY, done: true, doneAt: ms(2026, 11, 13, 8, 30) }),
  mkTask({ id: 'dropped-one', title: '放弃的旧报告', date: date.addDays(TODAY, -1), done: true, dropped: true, doneAt: ms(2026, 11, 12, 9) }),
  mkTask({ id: 'child', title: '打印会议材料', note: '会议 材料', date: TODAY, parentId: 'q1-open' }),
  mkTask({ id: 'daily', title: '每天跑步', note: '运动 打卡', date: date.addDays(TODAY, -10), time: '07:30', repeat: 'd1', doneDates: [TODAY, date.addDays(TODAY, -1)], createdAt: ms(2026, 10, 20) }),
  mkTask({ id: 'weekdays', title: '工作日站会', date: date.addDays(TODAY, -20), time: '09:30', repeat: 'w1:12345', createdAt: ms(2026, 10, 21) }),
  mkTask({ id: 'weekly', title: '周会', date: date.addDays(TODAY, -14), time: '18:00', repeat: 'w1:5', doneDates: [date.addDays(TODAY, -7)], createdAt: ms(2026, 10, 22) }),
  mkTask({ id: 'monthly', title: '月度复盘', date: '2026-01-31', repeat: 'm1', createdAt: ms(2026, 10, 23) }),
  mkTask({ id: 'yearly', title: '纪念日', date: '2020-05-20', repeat: 'y1', createdAt: ms(2026, 10, 24) }),
  mkTask({ id: 'ended', title: '已结束的每天打卡', date: date.addDays(TODAY, -30), repeat: 'd1~' + date.addDays(TODAY, -3), createdAt: ms(2026, 10, 25) }),
  mkTask({ id: 'interval', title: '每三天浇花', date: date.addDays(TODAY, -6), repeat: 'd3', createdAt: ms(2026, 10, 26) }),
];
const findTask = (id) => TASKS.find((x) => x.id === id);

// ---- QuadrantView.vue:22-39 ----
const RANGES = ['all', 'today', 'week'];
const inRange = (t, range) => {
  if (range === 'all' || !t.date) return true;
  if (range === 'today') return t.date <= TODAY;
  return t.date <= date.addDays(date.mondayOf(TODAY), 6);
};
const quadrantCases = [];
for (const range of RANGES) {
  for (const showDone of [false, true]) {
    const g = { 1: [], 2: [], 3: [], 4: [] };
    for (const raw of TASKS) {
      if (raw.parentId) continue;
      if (raw.repeat) continue;
      if ((showDone || !raw.done) && inRange(raw, range)) g[quad.quadrantOf(raw)].push(raw);
    }
    for (const k in g) g[k].sort(quad.byDate);
    quadrantCases.push({
      range, showDone,
      groups: Object.fromEntries([1, 2, 3, 4].map((q) => [String(q), g[q].map((x) => x.id)])),
      counts: Object.fromEntries([1, 2, 3, 4].map((q) => [String(q), g[q].filter((x) => !x.done).length])),
    });
  }
}

// ---- RoutineView.vue:26-67 ----
const GROUPS = [['daily', '每天'], ['interval', '每隔几天'], ['weekly', '每周'], ['monthly', '每月'], ['yearly', '每年'], ['ended', '已结束']];
const unitOf = (t) => {
  const r = rep.parseRule(t.repeat);
  let u = '次';
  if (rep.repeatGroup(t.repeat) === 'daily') u = '天';
  else if (r.freq === 'w' && r.n === 1 && r.days.length === 1) u = '周';
  else if (r.freq === 'm' && r.n === 1) u = '个月';
  else if (r.freq === 'y' && r.n === 1) u = '年';
  return u;
};
const routines = TASKS.filter((t) => t.repeat && !t.parentId);
const todayList = routines.filter((t) => rep.occursOn(t, TODAY));
const doneToday = todayList.filter((t) => t.doneDates.includes(TODAY)).length;
const progress = todayList.length ? doneToday / todayList.length : 0;
const allRoutine = routines.map((t) => {
  const occ = rep.occursOn(t, TODAY) ? TODAY : rep.nextOccurrence(t, TODAY);
  const task = occ ? rep.instanceOf(t, occ) : { ...t, occ: '' };
  return {
    task, group: occ ? rep.repeatGroup(t.repeat) : 'ended',
    isToday: occ === TODAY, streak: rep.streakOf(t, TODAY), unit: unitOf(t),
  };
});
const routineGroups = GROUPS.map(([key, label]) => {
  const items = allRoutine.filter((it) => it.group === key).sort(
    (a, b) => b.isToday - a.isToday
      || (a.task.time || '99').localeCompare(b.task.time || '99')
      || a.task.createdAt - b.task.createdAt,
  );
  return {
    key, label,
    items: items.map((it) => ({
      id: it.task.id, occ: it.task.occ || '', isToday: it.isToday,
      streak: it.streak, unit: it.unit, date: it.task.date, done: it.task.done,
    })),
  };
}).filter((g) => g.items.length);
const routineCases = [];
for (const lang of ['zh', 'en']) {
  setLang(lang);
  const headline = !todayList.length ? t('今天没有要打卡的')
    : doneToday === todayList.length ? t('今天的卡都打完了')
    : t('今天还剩 {n} 项', { n: todayList.length - doneToday });
  routineCases.push({
    lang,
    headline,
    detail: t('今天 {done}/{total} · 共 {n} 项打卡', { done: doneToday, total: todayList.length, n: routines.length }),
    progress,
    groups: routineGroups.map((g) => ({ ...g, labelText: t(g.label) })),
  });
}
setLang('zh');

// ---- SearchSheet.vue:27-63 ----
const WS = '[ \\t\\n\\r\\f\\v\\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000\\ufeff]';
const termsOf = (q) => q.trim().toLowerCase().split(/\s+/).filter(Boolean);
const searchResults = (q) => {
  const terms = termsOf(q);
  if (!terms.length) return { open: [], done: [] };
  const hit = TASKS.filter((t) => {
    const hay = `${t.title}\n${t.note}`.toLowerCase();
    return terms.every((w) => hay.includes(w));
  });
  return {
    open: hit.filter((t) => t.repeat || !t.done).sort(quad.byDate),
    done: hit.filter((t) => !t.repeat && t.done).sort((a, b) => (b.doneAt ?? 0) - (a.doneAt ?? 0)),
  };
};
const marksOf = (text, q) => {
  const terms = termsOf(q);
  if (!terms.length) return [{ text, hit: false }];
  const re = new RegExp(`(${terms.map((w) => w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|')})`, 'gi');
  return text.split(re).map((part, i) => ({ text: part, hit: i % 2 === 1 })).filter((m) => m.text);
};
const noteSnippet = (task, q) => {
  const note = task.note.replace(/\s+/g, ' ');
  const lower = note.toLowerCase();
  const terms = termsOf(q);
  const i = Math.min(...terms.map((w) => lower.indexOf(w)).filter((x) => x >= 0));
  if (!Number.isFinite(i)) return '';
  const start = Math.max(0, i - 8);
  return (start ? '…' : '') + note.slice(start, start + 40);
};
const subOf = (task) => [
  task.dropped && t('已放弃'),
  task.repeat ? rep.repeatLabel(task.repeat, task.date) : task.date ? date.dateLabel(task.date) : t('无日期'),
  task.time,
  task.parentId && `↳ ${findTask(task.parentId)?.title ?? ''}`,
].filter(Boolean).join(' · ');
const QUERIES = ['报告', '会议', '会议 材料', '运动 打卡', 'REPORT', '财务  复核', '不存在', '', '   '];
const searchCases = [];
for (const lang of ['zh', 'en']) {
  setLang(lang);
  for (const q of QUERIES) {
    const r = searchResults(q);
    const hit = [...r.open, ...r.done];
    searchCases.push({
      lang, q,
      open: r.open.map((x) => x.id), done: r.done.map((x) => x.id),
      marks: hit.length ? marksOf(hit[0].title, q) : [],
      snippet: hit.length ? noteSnippet(hit[0], q) : '',
      subs: hit.slice(0, 4).map((x) => subOf(x)),
      noResult: t('没有找到包含「{q}」的任务', { q: q.trim() }),
    });
  }
}
setLang('zh');

// ---- MeView.vue:14-102 ----
const tasksOn = (d) => TASKS.flatMap((t) => (t.repeat
  ? (rep.occursOn(t, d) ? [rep.instanceOf(t, d)] : [])
  : (t.date === d ? [t] : [])));
const todayTasks = tasksOn(TODAY);
const todayCounted = todayTasks.filter((t) => !t.dropped);
const todayDone = todayCounted.filter((t) => t.done).length;
const ratio = todayCounted.length ? todayDone / todayCounted.length : 0;
const pendingAll = TASKS.filter((t) => !t.repeat && !t.done).length
  + todayTasks.filter((t) => t.repeat && !t.done).length;
const overdue = TASKS.filter((t) => !t.repeat && !t.done && t.date && t.date < TODAY).length;
const doneDays = TASKS.flatMap((t) => (t.repeat ? t.doneDates
  : t.doneAt && !t.dropped ? [date.ymd(new Date(t.doneAt))] : []));
const weekDone = doneDays.filter((d) => d >= date.mondayOf(TODAY) && d <= TODAY).length;
const last7Days = Array.from({ length: 7 }, (_, i) => date.addDays(TODAY, i - 6));
const greetingKey = (h) => h < 6 ? '夜深了' : h < 11 ? '早上好' : h < 13 ? '中午好' : h < 18 ? '下午好' : '晚上好';
const parseCodeRe = /^(https?:\/\/[^\s#]+?)\/?#([A-Za-z0-9._~-]{16,})$/;
const syncStatus = (settings, syncState) => {
  if (!settings.syncOn) return '';
  const ok = parseCodeRe.test(settings.syncCode.trim());
  if (!ok) return t(settings.syncCode ? '连接码格式不对：应该是 地址#令牌' : '填入服务器启动时打印的连接码');
  if (syncState.busy) return t('正在同步…');
  if (syncState.error) return t('同步失败：{msg}', { msg: syncState.error });
  if (syncState.at) {
    const d = new Date(syncState.at);
    const time = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
    const host = settings.syncCode.match(parseCodeRe)?.[1].replace(/^https?:\/\//, '') ?? '';
    return t('已同步 · {time} · {host}', { time, host });
  }
  return t('还没同步过');
};
const meCases = [];
for (const lang of ['zh', 'en']) {
  setLang(lang);
  const counts = Object.fromEntries(last7Days.map((d) => [d, 0]));
  for (const d of doneDays) if (d in counts) counts[d]++;
  const max = Math.max(1, ...Object.values(counts));
  meCases.push({
    lang,
    greetings: [2, 8, 12, 15, 20].map((h) => t(greetingKey(h))),
    summary: !todayCounted.length ? t('今天还没有安排任务')
      : todayCounted.length === todayDone ? t('今天的任务全部完成了，真棒')
      : t('今天还有 {n} 个任务待完成', { n: todayCounted.length - todayDone }),
    doneTotal: t('{done} / {total} 已完成', { done: todayDone, total: todayCounted.length }),
    ratio, weekDone, pendingAll, overdue,
    last7: last7Days.map((d) => ({
      d, n: counts[d], h: counts[d] / max,
      label: d === TODAY ? t('今') : date.weekdayName(date.parseYmd(d).getDay(), true),
    })),
    last7Total: t('共 {n} 个', { n: Object.values(counts).reduce((a, b) => a + b, 0) }),
    langLabels: ['auto', 'zh', 'en'].map((p) => ({ zh: '中文', en: 'English' })[p] ?? t('跟随系统')),
    replaceHint: t('会替换当前全部 {n} 条任务', { n: TASKS.length }),
  });
}
const syncCases = [];
for (const lang of ['zh', 'en']) {
  setLang(lang);
  const settings = [
    { syncOn: false, syncCode: '' },
    { syncOn: true, syncCode: '' },
    { syncOn: true, syncCode: 'bad-code' },
    { syncOn: true, syncCode: 'http://192.168.1.5:18787#abcdefghijklmnop' },
  ];
  for (const s of settings) {
    for (const state of [{ busy: false, at: 0, error: '' }, { busy: true, at: 0, error: '' },
                         { busy: false, at: 0, error: "Can't reach the server" },
                         { busy: false, at: ms(2026, 11, 13, 14, 5), error: '' }]) {
      syncCases.push({ lang, settings: s, state, status: syncStatus(s, state) });
    }
  }
}
setLang('zh');

// ---- 词条（含 i18n-en 的函数值） ----
const STRING_KEYS = [
  ['全部', {}], ['本周', {}], ['已完成', {}], ['今天', {}],
  ['在{name}里新建', { name: '重要且紧急' }],
  ['已移到「{name}」', { name: '不重要不紧急' }],
  ['没有需要马上处理的事', {}], ['清清爽爽', {}],
  ['长按任务拖到其他象限 · 点击查看详情', {}],
  ['每天', {}], ['每隔几天', {}], ['每周', {}], ['每月', {}], ['每年', {}], ['已结束', {}],
  ['今天还剩 {n} 项', { n: 1 }], ['今天还剩 {n} 项', { n: 3 }],
  ['今天 {done}/{total} · 共 {n} 项打卡', { done: 1, total: 3, n: 1 }],
  ['今天 {done}/{total} · 共 {n} 项打卡', { done: 2, total: 4, n: 5 }],
  ['已删除「{title}」及 {n} 个子任务', { title: '周会', n: 1 }],
  ['已删除「{title}」及 {n} 个子任务', { title: '周会', n: 3 }],
  ['今天没有要打卡的', {}], ['今天的卡都打完了', {}], ['还没有打卡任务', {}],
  ['今天这次已跳过', {}], ['下一次已跳过', {}],
  ['夜深了', {}], ['早上好', {}], ['中午好', {}], ['下午好', {}], ['晚上好', {}],
  ['今天还没有安排任务', {}], ['今天的任务全部完成了，真棒', {}],
  ['今天还有 {n} 个任务待完成', { n: 1 }], ['今天还有 {n} 个任务待完成', { n: 4 }],
  ['{done} / {total} 已完成', { done: 2, total: 5 }],
  ['本周完成', {}], ['待办总数', {}], ['已过期', {}], ['近 7 天完成', {}],
  ['共 {n} 个', { n: 1 }], ['共 {n} 个', { n: 7 }],
  ['跟随系统', {}], ['通用', {}], ['日历显示', {}], ['农历与节气', {}],
  ['法定节假日与调休', {}], ['到点提醒', {}], ['新任务默认提醒', {}],
  ['会替换当前全部 {n} 条任务', { n: 1 }], ['会替换当前全部 {n} 条任务', { n: 12 }],
  ['会替换当前全部 {n} 条任务', { n: 0 }],
  ['用备份里的 {a} 条任务替换当前的 {b} 条？', { a: 3, b: 1 }],
  ['已恢复 {n} 条任务', { n: 1 }], ['已恢复 {n} 条任务', { n: 5 }],
  ['连接码格式不对：应该是 地址#令牌', {}], ['填入服务器启动时打印的连接码', {}],
  ['正在同步…', {}], ['同步失败：{msg}', { msg: 'Wrong token' }],
  ['已同步 · {time} · {host}', { time: '14:05', host: '192.168.1.5:18787' }],
  ['还没同步过', {}], ['同步完成', {}],
  ['已删除「{title}」及{n} 个子任务', { title: '项目', n: 2 }],
  ['已删除「{title}」及以后的重复和{n} 个子任务', { title: '跑步', n: 1 }],
  ['已完成 {n} 次', { n: 1 }], ['已完成 {n} 次', { n: 4 }],
  ['{n} 个任务已移到今天', { n: 1 }], ['{n} 个任务已移到今天', { n: 3 }],
  ['已推迟到{date}', { date: 'Tomorrow' }],
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
  generator: 'generate_t16_fixtures.mjs',
  today: TODAY,
  fixedLocalTime: '2026-11-13T12:00:00',
  tasks: TASKS,
  quadrant: quadrantCases,
  routine: routineCases,
  search: searchCases,
  me: meCases,
  sync: syncCases,
  strings: stringCases,
};
writeFileSync(resolve(here, 't16_fixtures.json'), JSON.stringify(out, null, 2) + '\n');
console.log(`wrote t16_fixtures.json: ${TASKS.length} tasks, ${quadrantCases.length} quadrant, ${routineCases.length} routine, ${searchCases.length} search, ${meCases.length} me, ${syncCases.length} sync, ${stringCases.length} strings`);
