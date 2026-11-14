#!/usr/bin/env node
// T-08 / M-04 中文自然语言解析契约黄金夹具生成器。
//
// oracle 是 baseline_commit 97a7c4c 的真实源码 src/lib/parse.js（183 行，未复制、未改写）。
// 只调用其导出的 parseInput；不调用 dayInfo，故 date.js 的 lunar-javascript 依赖不参与判定。
//
// parse.js 里的「今天」与「今年」都来自 `new Date()`，没有注入口。为保证夹具可复现且
// 能在多个时区下用同一份文件验证，这里在 Node 进程里把无参 `new Date()` 固定为
// **本地时间** 2026-11-13 12:00:00（用本地构造而非 epoch，跨时区时本地日期不变），
// 再动态 import oracle。带参数的 `new Date(y, m-1, d)` 一律原样透传，不改函数体。
//
// 用法（任意 cwd）：
//   node ios/PlannerTests/Fixtures/generate_parse_fixtures.mjs
// 输出：ios/PlannerTests/Fixtures/parse_fixtures.json
//
// Swift 侧用同样语义注入 now（本地 2026-11-13 12:00），逐字段对比 title/date/time/repeat/hits。

import { writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../../..');
const importFromRoot = (p) => import(pathToFileURL(resolve(root, p)).href);

const RealDate = Date;
const FIXED = new RealDate(2026, 10, 13, 12, 0, 0); // 本地 2026-11-13 12:00:00
class FixedDate extends RealDate {
  constructor(...args) { super(...(args.length ? args : [FIXED.getTime()])); }
  static now() { return FIXED.getTime(); }
}
globalThis.Date = FixedDate;

const { parseInput } = await importFromRoot('src/lib/parse.js');
const date = await importFromRoot('src/lib/date.js');

const BASELINE = '97a7c4c17602327a42d30110806a6a1e6fa0e798';
const TODAY = '2026-11-13';
if (date.today() !== TODAY) {
  throw new Error(`固定日期失败：date.today()=${date.today()}，期望 ${TODAY}`);
}

// ---- 语料 ----
// A. parse.js:181 内置 selfTest 的 25 条（OPEN-08=A 的等价标准），逐字照抄。
const SELF_TEST = [
  '明天下午3点开会', '周五 交周报', '下周一 9:30 例会', '11月20日体检', '今晚8点半跑步',
  '3号交房租', '买牛奶', '中午12点 吃饭', '后天上午十点一刻 面试', '每天 背单词',
  '每周五晚上八点 羽毛球', '每个工作日9:30站会', '每月15号还信用卡', '每周 大扫除',
  '每周一三五 健身', '每周一、周三 晚上7点 游泳', '隔周五 周会', '每两周的周二 汇报',
  '每隔一天 跑步', '每3天 浇花', '每周末 打扫', '每年5月20日 纪念日',
  '每两个月的1号 理发', '每天 背单词 到12月31日', '每月 总结',
];

// B. 日期规则 7 条：相对日、周/星期/礼拜、下/下下、N月N日、N号、中文数字、溢出。
const DATES = [
  '大后天 出差', '后天 交报告', '明日 发货', '明早 跑步', '明晚 看电影',
  '今天 复盘', '今日 结算', '今晚 散步', '今早 晨读',
  '下下周五 体检', '下周一 例会', '下周三 9:30 评审', '周日 休息', '周天 休息',
  '礼拜三 会议', '星期1 值班', '星期天 聚会', '周五 交周报',
  '11月20号 体检', '十一月二十日 体检', '1月1日 元旦', '12月31日 跨年',
  '3号交房租', '三十号 还款', '二十五号 还款', '十三号 缴费', '十号 缴费', '15号 发薪',
  '2月30日 测试溢出', '13月1日 测试溢出', '25号 十五点 复盘',
];

// C. 重复规则 10 条 + UNTIL_RE 的所有前缀/后缀形式。
const REPEATS = [
  '每隔一天 跑步', '隔天 跑步', '每2天 浇花', '每隔两天 跑步', '每3天 浇花',
  '每99天 检查', '每天 背单词', '每日 复盘', '天天 打卡',
  '工作日 站会', '每个工作日 站会', '周末 打扫', '每个周末 打扫', '每周末 打扫',
  '每周一三五 健身', '每周一、周三 游泳', '每周一，周三和周五 训练',
  '每两周五 周会', '隔周周五 周会', '每隔一周的周二 汇报',
  '每周 大扫除', '每周五 羽毛球', '每3周 评审',
  '每月15号 还款', '每两个月的1号 理发', '每隔两个月的1号 理发',
  '每年5月20日 纪念日', '每2年5月20日 纪念日', '每月 总结', '每年 体检',
  '每天 背单词 到12月31日', '每天 背单词 直到12月31日为止',
  '每天 背单词 截止到12月31日', '每天 背单词 至12月31日结束',
  '每天 背单词 到11月1日', '每月15号 到12月31日 还款',
];

// D. 时间规则 2 条：冒号、中文数字、半/一刻/三刻/分、时段词进位、判废分支。
const TIMES = [
  '9:30 开会', '21：00 看球', '上午9:30 例会', '下午3点 开会', '3点 开会',
  '8点15 出发', '十点一刻 面试', '下午三点半 喝茶', '晚上8点半 跑步',
  '中午12点 吃饭', '凌晨1点 起床', '24点 睡觉', '25点 无效',
  '早8点 晨会', '明早7点 跑步', '今晚8点半 跑步', '8点75分 无效',
  '傍晚6点 散步', '早晨6点 晨跑', '下午14点 开会', '12点 午饭',
  '十点三刻 见面', '9点08分 打卡', '9点8 打卡', '二十点 见面',
];

// E. 组合、标题收缩、无识别、纯标题、空白与英文（A-45：英文 UI 仍只识别中文）。
const MIXED = [
  '  明天  下午3点  开会  ', '买牛奶', '开会', 'meeting tomorrow',
  'call at 9:30', '2026-11-13 review', '明天', '今晚', '明早', '周五',
  '每天', '每月', '纯标题无日期', '明天下午3点', '3点', '', '   ',
  '明天 3点 开会 后天', '每周一 9:30 站会 到12月31日',
  '大后天上午9:30 季度复盘', '下下周一 十点一刻 双周会',
  '二零二六年 规划', '三十一点的会', '二十三点 休息',
];

// F. 空白 / 数字字符边界：验证 JS `\d`（仅 ASCII）与 `trim()` / `\s` 的等价性。
// 全角数字不应被识别；全角空格、制表符、不换行空格、BOM 都属 JS 的空白语义。
const EDGES = [
  '明天\u3000下午3点\u3000开会', '\uFEFF明天下午3点开会',
  '明天\t下午3点\n开会', '\u00A0明天下午3点开会',
  '11月20日\u3000体检', '每天\u3000背单词',
  '３点开会', '９:３０ 开会', '明天３点开会', '１１月２０日 体检',
  '明天\u200B下午3点开会',
];

const texts = [...SELF_TEST, ...DATES, ...REPEATS, ...TIMES, ...MIXED, ...EDGES];

const cases = texts.map((text) => {
  const r = parseInput(text);
  return {
    text,
    title: r.title,
    date: r.date,
    time: r.time,
    repeat: r.repeat,
    hits: r.hits,
  };
});

const out = {
  meta: {
    baseline_commit: BASELINE,
    generator: 'ios/PlannerTests/Fixtures/generate_parse_fixtures.mjs',
    today: TODAY,
    fixed_local_now: '2026-11-13T12:00:00',
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    self_test_count: SELF_TEST.length,
    case_count: cases.length,
    note: 'oracle = 真实 src/lib/parse.js；无参 new Date() 固定为本地 2026-11-13 12:00；字段顺序 title/date/time/repeat/hits，hits 为有序数组。',
  },
  cases,
};

const dest = resolve(here, 'parse_fixtures.json');
writeFileSync(dest, JSON.stringify(out, null, 2) + '\n');
console.log(`wrote ${dest}: ${cases.length} cases (selfTest ${SELF_TEST.length}), today=${TODAY}, tz=${out.meta.timezone}`);
