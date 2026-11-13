#!/usr/bin/env node
// T-06 / M-06 契约黄金夹具 + OPEN-07=A 静态数据源生成器。
//
// oracle 是 baseline_commit 97a7c4c 的真实源码 src/lib/date.js（未复制、未改写、未打补丁）。
// date.js 依赖的 i18n.js 在 Node 下可直接 import：date.js 只取 isEn()，不触碰
// navigator / document / import.meta.env 那几处 Vite 路径，因此无需运行副本。
//
// 用法（任意 cwd 均可，路径按脚本位置解析）：
//   node ios/PlannerTests/Fixtures/generate_calendar_fixtures.mjs
//
// 输出：
//   ios/Planner/Resources/lunar-data.json          静态表（dayInfo 全量快照 + 干支年）
//   ios/PlannerTests/Fixtures/calendar_fixtures.json  契约逐字对比夹具
//
// 静态表是「JS 输出的快照」而非「原始数据 + Swift 侧重写选择逻辑」：
// 每一行就是 date.js:dayInfo(s) 的五个字段，Swift 侧只做查表，零逻辑偏差。

import { writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../../..');
const importFromRoot = (p) => import(pathToFileURL(resolve(root, p)).href);

const date = await importFromRoot('src/lib/date.js');
const { i18n } = await importFromRoot('src/lib/i18n.js');

const BASELINE = '97a7c4c17602327a42d30110806a6a1e6fa0e798';
const out = (p, value) => {
  writeFileSync(resolve(root, p), JSON.stringify(value) + '\n');
  console.log('wrote', p);
};

const SEP = '|';
const encodeInfo = (info, ymd) => {
  const fields = [info.text, info.kind, info.holiday, info.holidayName, info.full];
  if (fields.some((f) => f.includes(SEP))) {
    throw new Error(`dayInfo(${ymd}) 的字段包含分隔符 ${SEP}，需换编码`);
  }
  return fields.join(SEP);
};

// ---- 1. 静态表：1900-01-01 .. 2100-12-31（lunar-javascript 农历表的完整有效范围） ----

const START_Y = 1900, END_Y = 2100;
const years = {};
const yearLabels = {};
const holidayYears = new Set();
let days = 0;

for (let y = START_Y; y <= END_Y; y++) {
  const rows = [];
  const cursor = new Date(y, 0, 1);
  while (cursor.getFullYear() === y) {
    const ymd = date.ymd(cursor);
    const info = date.dayInfo(ymd);
    rows.push(encodeInfo(info, ymd));
    if (info.holiday) holidayYears.add(y);
    days++;
    cursor.setDate(cursor.getDate() + 1);
  }
  years[String(y)] = rows;
  yearLabels[String(y)] = date.lunarYearLabel(y);
}

const holidayList = [...holidayYears].sort((a, b) => a - b);
out('ios/Planner/Resources/lunar-data.json', {
  meta: {
    source: 'lunar-javascript@1.7.8 via src/lib/date.js:dayInfo / lunarYearLabel (baseline oracle)',
    baseline_commit: BASELINE,
    generator: 'ios/PlannerTests/Fixtures/generate_calendar_fixtures.mjs',
    generated_from: 'node ios/PlannerTests/Fixtures/generate_calendar_fixtures.mjs',
    range: ['1900-01-01', '2100-12-31'],
    days,
    holiday_data_years: `${holidayList[0]}-${holidayList[holidayList.length - 1]}`,
    holiday_note: '法定节假日/调休来自 lunar-javascript 内嵌 HolidayUtil；该范围之外 JS 侧同样返回空，Swift 查表结果一致。',
    encoding: 'years[yyyy][dayOfYear-1] = text|kind|holiday|holidayName|full；kind = festival|term|lunar',
    language_note: 'dayInfo 与 lunarYearLabel 不走 i18n，中英界面下名称均为中文（A-13）。',
  },
  yearLabels,
  years,
});

// ---- 2. 契约夹具 ----

const today = date.today();
const withLang = (lang, fn) => {
  const prev = i18n.lang;
  i18n.lang = lang;
  try { return fn(); } finally { i18n.lang = prev; }
};

// 覆盖：节气、农历节日、公历节日、休/班、初一、闰月、普通农历日、跨年、调休数据边界。
const dayInfoDates = [
  '1900-01-01', '1999-12-31', '2000-01-01', '2024-02-10', '2025-06-25',
  '2025-12-31', '2026-01-01', '2026-02-17', '2026-04-05', '2026-05-01',
  '2026-06-19', '2026-09-25', '2026-10-01', '2026-10-10', '2026-11-13',
  '2026-12-21', '2026-12-25', '2026-12-31', '2027-01-01', '2027-10-01',
  '2028-01-01', '2030-02-03', '2050-06-01', '2100-12-31',
];

const fixture = {
  meta: {
    baseline_commit: BASELINE,
    generator: 'ios/PlannerTests/Fixtures/generate_calendar_fixtures.mjs',
    today,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    note: 'dateLabel 的 today 由夹具注入，Swift 侧不得读系统当前时间，保证可复现。',
  },
  dayInfo: [],
  dayInfo_en: [],
  dateLabel: [],
  weekdayName: [],
  monthDay: [],
  monthName: [],
  ordinal: [],
  lunarYearLabel: [],
  arithmetic: [],
};

for (const s of dayInfoDates) {
  const info = date.dayInfo(s);
  fixture.dayInfo.push({ date: s, ...info });
}
// A-13：英文界面下农历/节气/节日名称仍为中文。
// date.js 的 dayInfo 有模块级 Map 缓存，静态表生成阶段已把 1900-2100 全部日期缓存，
// 换日期也躲不开缓存。用带 query 的独立 date.js 实例（空 cache）+ 英文语言重算，
// 并断言与中文实例逐字相同。i18n 模块仍是同一实例，所以 isEn() 确实读到 en。
const dateEn = await import(pathToFileURL(resolve(root, 'src/lib/date.js')).href + '?fresh=t06-en');
withLang('en', () => {
  if (dateEn.weekdayName(5) !== 'Fri') throw new Error('英文模块实例未生效，A-13 用例无效');
  for (const s of dayInfoDates) {
    const en = dateEn.dayInfo(s);
    const zh = date.dayInfo(s);
    if (JSON.stringify(en) !== JSON.stringify(zh)) {
      throw new Error(`dayInfo(${s}) 随界面语言变化，A-13 不成立`);
    }
    fixture.dayInfo_en.push({ date: s, ...en });
  }
});

// dateLabel：相对今天 + 绝对跨年 + 远期，中英各一套。
const labelOffsets = [-400, -365, -30, -7, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 30, 48, 365, 400];
const labelDates = [
  ...labelOffsets.map((n) => date.addDays(today, n)),
  '2026-01-01', '2026-12-31', '2027-01-01', '2024-02-29',
];
for (const lang of ['zh', 'en']) {
  withLang(lang, () => {
    for (const s of labelDates) {
      fixture.dateLabel.push({ date: s, today, lang, expected: date.dateLabel(s) });
    }
  });
}

for (const lang of ['zh', 'en']) {
  withLang(lang, () => {
    for (let i = 0; i < 7; i++) {
      for (const short of [false, true]) {
        fixture.weekdayName.push({ i, short, lang, expected: date.weekdayName(i, short) });
      }
    }
    for (let m = 1; m <= 12; m++) {
      fixture.monthDay.push({ date: `${2026}-${date.pad(m)}-15`, lang, expected: date.monthDay(date.parseYmd(`2026-${date.pad(m)}-15`)) });
    }
    for (let m0 = 0; m0 < 12; m0++) {
      fixture.monthName.push({ m0, lang, expected: date.monthName(m0) });
    }
  });
}

for (const n of [1, 2, 3, 4, 5, 10, 11, 12, 13, 14, 20, 21, 22, 23, 24, 30, 31, 101, 111, 112, 113]) {
  fixture.ordinal.push({ n, expected: date.ordinal(n) });
}

for (const year of [1900, 1949, 2000, 2024, 2025, 2026, 2027, 2030, 2050, 2100]) {
  fixture.lunarYearLabel.push({ year, expected: date.lunarYearLabel(year) });
}

const arithmeticDates = [
  '2024-02-28', '2024-02-29', '2026-01-01', '2026-12-31',
  '2026-03-08', '2026-11-01', '2026-03-29', '2026-10-25',
  '2026-04-05', '2026-11-13', '2000-02-29', '2100-12-31',
];
for (const s of arithmeticDates) {
  for (const n of [-365, -30, -1, 0, 1, 7, 30, 365]) {
    fixture.arithmetic.push({ op: 'addDays', input: s, n, expected: date.addDays(s, n) });
  }
  fixture.arithmetic.push({ op: 'mondayOf', input: s, expected: date.mondayOf(s) });
  fixture.arithmetic.push({ op: 'weekdayOf', input: s, expected: date.weekdayOf(s) });
  fixture.arithmetic.push({ op: 'ymdRoundTrip', input: s, expected: date.ymd(date.parseYmd(s)) });
  fixture.arithmetic.push({ op: 'weekdayIndex', input: s, expected: date.parseYmd(s).getDay() });
}
for (const [a, b] of [
  ['2026-11-13', '2026-11-13'], ['2026-11-14', '2026-11-13'], ['2026-11-13', '2026-11-14'],
  ['2024-03-01', '2024-02-28'], ['2027-01-01', '2026-01-01'], ['2026-03-09', '2026-03-07'],
  ['2026-11-02', '2026-10-31'], ['1900-01-01', '2100-12-31'],
]) {
  fixture.arithmetic.push({ op: 'diffDays', input: a, b, expected: date.diffDays(a, b) });
}
for (const n of [0, 1, 9, 10, 11, 99, 100]) {
  fixture.arithmetic.push({ op: 'padNumber', input: n, expected: date.pad(n) });
}

out('ios/PlannerTests/Fixtures/calendar_fixtures.json', fixture);
console.log(`静态表 ${days} 天 / ${holidayList[0]}-${holidayList[holidayList.length - 1]} 调休年份；夹具 ${fixture.dateLabel.length} 条 dateLabel、${fixture.dayInfo.length} 条 dayInfo`);
