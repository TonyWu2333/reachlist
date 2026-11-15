# 可及清单 · iOS 原生版

基于上游 [TonyWu2333/reachlist](https://github.com/TonyWu2333/reachlist) 的契约等价 iOS 原生实现，
事实基线为 `97a7c4c`（v0.12.0）。Web / Android 端代码在本仓库的上游历史中，本分支 `ios-native` 新增
`ios/` 下的 Swift 工程。

## 目录

| 路径 | 内容 |
|---|---|
| `ios/Planner/Core/` | 数据模型、日历、重复、解析、合并、存储、同步、提醒、备份（纯 Foundation，可独立测试） |
| `ios/Planner/Features/` | 日历、四象限、打卡、搜索、我的、任务详情、快速添加 |
| `ios/Planner/App/` | 入口、骨架、设计系统与反馈层 |
| `ios/PlannerTests/` | XCTest 与黄金夹具（oracle 取自上游 `src/lib/*.js`） |
| `ios/Planner.xcodeproj/` | Xcode 工程 |

## 构建

用 Xcode 打开 `ios/Planner.xcodeproj`。真机运行前把
`ios/Planner/Config/Signing.xcconfig` 里的 `DEVELOPMENT_TEAM` 改成你自己的 Team ID
（仓库里是占位值 `YOUR_TEAM_ID`）。最低部署目标 iOS 26。

端到端同步测试需要一个本地临时服务器；相关地址与令牌在测试文件里均为占位值，
按测试文件头部注释启动即可。

## 契约

`Core/` 下的算法与上游 `src/lib/` 的 JS 实现逐字对齐，跨端一致性由
`PlannerTests/Fixtures/` 里的黄金夹具保证：夹具由 `generate_*.mjs` 以真实 JS 源码为 oracle 生成，
XCTest 在真机上读 bundle 内的 JSON 做全量断言。
