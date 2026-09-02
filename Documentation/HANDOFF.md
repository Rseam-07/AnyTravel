# AnyTravel 接力交接（DeepSeek → Codex）

> 更新于 2026-09-02 深夜。本文是 DeepSeek 会话结束时的工程状态快照与后续建议，供 Codex 会话直接接管。先读本文，再读 [FEATURE_ROADMAP](FEATURE_ROADMAP.md)、[DATA_CHANNELS](DATA_CHANNELS.md) 与 `CHANGELOG.md` 顶部的新条目。

## 1. 仓库与工作副本

- 主仓库（本会话工作目录）：`/Users/conrad/Documents/AnyTravel`，本地提交 `518c0ce`
- Codex 侧工作副本：`/Users/conrad/Documents/ChatGPT/AnyTravel`（**已同步**，本地提交 `34b2b3c`，文件树与主仓库一致；注意两棵树的 `.git` 是各自独立的仓库，提交哈希不同）
- 远端：`origin = https://github.com/Rseam-07/AnyTravel.git`，分支 `main`，上游 HEAD 仍为 `6ee2004`（Release AnyTravel iOS 0.6.3）——**本轮两个本地提交都未 push**
- **交接时的约定**：以 `/Users/conrad/Documents/AnyTravel` 的提交为准；两个副本的差异必须在双方开工前比对（`diff -rq` 或双方 `git status`），必要时把其中一棵同步成另一棵，避免并行修改互相覆盖。
- 常规提交流程：`xcodegen generate --spec project.yml` 之后再提交（`project.yml` 是工程源定义）。

## 2. 当前状态：一个大而未提交的功能集

0.6.3 发布后（2026-09-01 14:03 之后到 09-02 21:09）在一棵工作树上完成了下一轮功能开发，**全部未提交**。本轮 DeepSeek 会话把其中缺失的文档补齐、验证构建与测试，并把状态固化为提交（见第 5 节）。

### 功能清单（对应代码）

1. **生成前景点挑选**：`任意方向从“让旅程在地图上展开”改为先打开“先挑想去的地方”`（`PlannerViewModel.requestPlan` → `beginAttractionSelection`），`AttractionSelectionView` 展示按热度/评分/距离排好、可跨 MapKit 与高德合并去重的候选；勾选主游览点会获得 1.28 倍停留（`TourismPlanningPolicy`），选少顺路补齐、超选给压力提示。
   - `AnyTravel/Features/Planner/AttractionSelectionView.swift`（新增）
   - `PlannerViewModel.swift`：`attraction*` 状态与 `confirmAttractionSelection(automatic:)`
   - `MapSearchService.swift`：`discoverAttractionCandidates`（MapKit 各关键词 + 高德合并、60km 上限、加权评分）
   - `Models/TripModels.swift`：`AttractionPopularity`、`AttractionPlanningPriority`
2. **内容自适应面板**：`RootView.swift` 的 `PlannerPanelLayout.preferredHeight` + `PlannerPanelAutoFitToken`，按阶段/焦点/数量自动贴合高度，拖动松手后按速度落档；`QuanarFlight...`。
3. **应用内直连价格通道**：
   - `RollingGoDirectClient.swift`（新增）：直连 `https://mcp.rollinggo.cn/mcp` 的 `searchHotels`，SSE 解析、总价→每晚换算、城市+景点锚点、去重、上限 40。伴随服务接通时优先走节点，否则用内置密钥。
   - `Railway12306DirectClient.swift`（新增）：官方车站表站点归一 → `leftTicket/query` + `queryTicketPrice`；与节点结果合并（`PlannerViewModel.refreshTransportQuotes`），只读，购买链接回官方页。
   - `QunarFlightDirectClient.swift`（新增，`@MainActor` + WebKit）：`touch.qunar.com/ncs/page/flightlist` 页面 + 劫持 `flight/api/touchInnerList` JSON；与 `ProviderLoginView` 共用 `WKWebsiteDataStore.default()`，复用已登录去哪儿会话；解析卡片与 `minPrice`，无裸数字不标实时。
   - `EmbeddedServiceConfiguration.swift`（新增）：从 Info.plist（`$(ANYTRAVEL_ROLLINGGO_API_KEY)` 等）或进程环境读取；`project.yml`/`Info.plist` 已加三个键位。**构建时不传这些 build settings 也不报错**（代码会忽略 `$(` 前缀与 `undefined`）。
4. **后端新通道**（`Backend/`）：
   - `elong.mjs`（新增）：艺龙开放平台 `hotel.static.city/list/info/detail`，`md5(timestamp+md5(data+appkey)+secretKey)` 签名，按日期 `LowRate`、RMB/CNY、每次最多 10 个酒店 ID 分批。
   - `onebound-ctrip.mjs`（新增）：万邦 `item_search_hotel` 携程目录参考价。
   - `ctrip-flight.mjs`（新增）：携程航班列表（Playwright 持久会话，`CTRIP_FLIGHT_SCRAPER_ENABLED`，缺省回退 `CTRIP_SCRAPER_ENABLED`，默认关闭）。
   - `ctrip.mjs`/`tongcheng.mjs`/parser 重构为“带来源与 offer 数组”的输出；`quote-service.mjs` 并行聚合 `catalogAdapters` + `mergeAccommodationCatalogResults` + `mergeTransportOptions`；`server.mjs` 健康检查新增各通道状态。
5. **iOS 数据模型扩展**：`ProviderQuote` 增加 `sourceLabel/totalAmountCNY/roomName/bedType/mealPlan/cancellationPolicy/taxesIncluded/availability`；`AccommodationCatalogEntry` 改为 `quotes: [ProviderQuote]` + `providers/sources/providerHotelIDs`、坐标可空；`PricingBackendClient` 兼容新的 offers 数组。
6. **测试**：新增 `RollingGoDirectClientTests`、`Railway12306DirectClientTests`、`QunarFlightDirectClientTests`、`QunarLiveProbeTests`（见下）、`AMapPlaceClientTests`（内置 key 回退）、`TourismPlanningTests`（主游览点时长等）、`TravelAssistantClientTests`（托管模式内置 GLM 回退）。

### 本轮新增密钥/环境变量（都不进 Git）

| 键 | 位置 | 用途 |
| --- | --- | --- |
| `ANYTRAVEL_ROLLINGGO_API_KEY`（或环境 `ROLLINGGO_API_KEY`） | iOS 构建设置/运行环境 | RollingGo MCP 直连 |
| `ANYTRAVEL_AMAP_WEB_SERVICE_KEY`（或 `AMAP_API_KEY`） | 同上 | 高德 v5 Web 服务直连（须为“Web 服务”类型 Key） |
| `ANYTRAVEL_ZAI_API_KEY`（或 `ZAI_API_KEY`） | 同上 | 托管智能向导直连智谱 |
| `ELONG_USER/APP_KEY/SECRET_KEY`、`ONEBOUND_API_KEY/SECRET`、`CTRIP_FLIGHT_SCRAPER_ENABLED` | `Backend/.env` | 节点侧，`.env.example` 已更新 |

## 3. 已验证（本会话实测）

- iOS 构建：`xcodebuild -project AnyTravel.xcodeproj -scheme AnyTravel -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/AnyTravelDerived CODE_SIGNING_ALLOWED=NO build` → **BUILD SUCCEEDED**。
- iOS 全量测试（单元 + XCUITest）：**81/81 通过，0 失败、0 跳过**（0.6.3 为 73/73），其中 65 个单元测试、16 个 XCUITest；`QunarLiveProbeTests` 已真实联网（4.1 秒返回，断言“拿到价格或明确渠道状态均算通过”）。
- Backend 测试：`cd Backend && npm test` → **42/42 通过**（0.6.3 时为 29），新增艺龙/万邦/携程航班解析相关用例。

### 环境注意事项（重要）

- 本机 Xcode：`/Applications/Xcode-beta.app`（Xcode 27.0 27A5228h，Swift 6.4），`xcode-select -p` 已指向它；模拟器 `iPhone 17 Pro` / iOS 26.5。
- **文件沙箱会杀死 `swift-plugin-server`**（报 `external macro implementation type ... produced malformed response`），导致任何含 `@Observable` 的编译失败。在受限会话里跑 xcodebuild/swiftc 需要全权限；如果 Codex 会话也碰到同样的 `sandbox-exec: sandbox_apply: Operation not permitted`，先确认这是沙箱问题而不是代码问题（最小复现：`xcrun swiftc -typecheck` 一个用 `@Observable` 的小文件）。
- 提交前用 `xcodegen generate --spec project.yml` 重建工程；不要手工改 `project.pbxproj`。

## 4. 尚未验证 / 已知边界（诚实清单）

- **直连通道未做业务级联网验收**：12306 直连、去哪儿航班页直连只有 mock/探针测试；`QunarLiveProbeTests` 只是“页面可达且状态明确”的弱断言，本轮真实打开页面通过但未确认解析出真实航班数字。RollingGo 直连没有任何真实密钥验证。
- **节点新通道均未配置凭据**：`ELONG_*`、`ONEBOUND_*`、`CTRIP_FLIGHT_SCRAPER_ENABLED` 都是 `disabled`；没有联网数字报价验收。艺龙生产环境还要把服务端公网 IP 加入平台白名单。
- **当前高德 Key 返回 `USERKEY_PLAT_NOMATCH (10009)`**（平台类型非“Web 服务”），界面会回退 Apple Maps；换对 Key 后无需改代码。
- 版本号：`CHANGELOG.md` 顶部新条目暂标“0.7.0（开发中，未发布）”，**尚未**更新 `project.yml` 的 `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`，也未打 tag、未 push、未建 Release。
- 本轮未做：浅色/深色新页面（景点挑选、多渠道报价卡）截图检查、真机走查、Android 对齐、QA 视频动效。

## 5. 本轮会话做了什么

- 确认工作树状态：0.6.3 发布后存在一组未提交功能开发（景点挑选、面板自适应、应用内直连价格、后端新通道、报价多通道模型）。
- 在受限沙箱环境下定位并绕过 `swift-plugin-server` 问题，完成 iOS 构建与全量测试（81/81）、Backend 测试（42/42）。
- 补齐 Backend `.env.example` 与 `Backend/README.md` 的 `ONEBOUND_*`、`CTRIP_FLIGHT_SCRAPER_ENABLED` 说明；更新 `DATA_CHANNELS.md`、`FEATURE_ROADMAP.md`、`README.md` 数据能力/验证数字与 `CHANGELOG.md` 顶部条目。
- 把全部内容提交为 `git log -1` 对应的提交（未 push、未打 tag、未建 Release）。提交信息里写明验证数字，供 Codex 直接核对。

## 6. 建议 Codex 的下一步（按优先级）

1. 先 `git pull`/确认 base，然后 `xcodegen generate --spec project.yml` 并跑一次完整 `xcodebuild test`，把结果数字写回 `CHANGELOG.md` 与 `README.md`（连 iOS 单元/UI 与 Node 测试数字）。
2. 真机/模拟器走查新交互：`--ui-test-ready` 下“先挑想去的地方”→ 生成 → 住宿卡“N家比价”→ 交通卡直连报价 → 面板自适应高度；浅色/深色截图各一张。
3. 联网验收（需要真实密钥/会话）：RollingGo 内置 key 直连、12306 直连（去程+返程）、去哪儿航班页（先用模拟器，注意 WebKit 会话与登录）；`QunarLiveProbeTests` 单独跑并记录输出。
4. 若用户提供 `ELONG_*`/`ONEBOUND_*` 凭据：在节点 `.env` 配置后做一轮游艺龙/万邦目录+动态价验收，记录抓取时间与 `diagnostics`。
5. 决定版本号并执行发布流程（按仓库既有惯例：无签名 IPA、`Artifacts/` 命名、tag、`gh release`）；发布前把 `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` 增量并更新 README 下载链接。
6. Android 侧本轮无改动；新增功能（景点挑选、直连价格、面板自适应）是否向 Android 对齐，需与用户确认。

## 7. 常用命令

```sh
# iOS 构建/测试（沙箱受限时必须全权限运行）
xcodebuild -project AnyTravel.xcodeproj -scheme AnyTravel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/AnyTravelDerived CODE_SIGNING_ALLOWED=NO test

# 只跑探针
xcodebuild ... -only-testing:AnyTravelTests/QunarLiveProbeTests test

# Backend
cd Backend && npm test && npm start

# 重新生成工程
xcodegen generate --spec project.yml
```
