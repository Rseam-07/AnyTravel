# AnyTravel

> 旅行是一场诗意的迁徙。AnyTravel 让每一次选择，都在地图上长成旅程。

AnyTravel 是一款地图优先的开源 iOS 旅行规划应用。用户不必先填完一张长表格：可以先选车次，也可以先挑住处；可以从预算出发，也可以只说“我想去苏州”。路线、住宿、抵达枢纽和每天的安排都会在背景地图上随选择更新。

<p align="center">
  <img src="Documentation/Brand/Exports/folded-horizon.png" width="128" alt="AnyTravel 折叠远方图标">
</p>

![首次进入：旅行是一场诗意的迁徙](Documentation/Screenshots/onboarding.png)

![地图上的完整苏州方案](Documentation/Screenshots/complete-plan.png)

## 一段旅程如何展开

- 第一次打开应用时，先看四页简短介绍，再留下常用出发地、人数和预算。行程默认保持轻松节奏。
- 携程、去哪儿、Trip.com 和铁路 12306 可在应用内登录。密码只提交给平台网页；报价与购买页会沿用同一 WebKit 会话。
- 日期、预算、兴趣、住宿和交通没有固定填写顺序，每一项都可以暂时留白。
- `MKLocalSearch` 会寻找真实景点、酒店、民宿和交通枢纽；`MKDirections` 会逐段绘制当前日路线。
- 选定住处后，交通建议会结合抵达时间、车站或机场到住处的距离、总耗时和票价重新排列。
- 最终方案包含每天的具体时段、地点介绍、路线、住宿候选、交通方式、购买入口和费用明细。
- 用户拖动地图时，自动镜头立即让出控制；点击卡片、车站或酒店时，地图再把相应位置带回视野。

## 当前数据能力

| 内容 | 当前实现 | 结果如何展示 |
| --- | --- | --- |
| 地点与市内路线 | Apple MapKit 实时搜索与路径计算 | 地图标记、逐段路线、距离与预计时间 |
| 酒店与民宿位置 | Apple Maps 候选；按景点均距和交通枢纽距离排序 | 地图卡片与推荐理由 |
| 酒店实时价格 | RollingGo MCP（配置密钥后）；携程持久化浏览器会话（用户自行登录后） | 渠道、每晚/总价口径、抓取时间、购买入口 |
| 铁路班次与票价 | 铁路 12306 公开查询页，只读查询 | 车次、发到时间、余票、席别价格与官方购票页 |
| 去哪儿与 Trip.com | 应用内登录、会话复用和购买页入口 | 未接通实时适配器时明确显示“到渠道查询” |
| 航班 | 已预留携程、去哪儿与 Skyscanner 适配位置 | 当前先提供渠道入口，不把估算冒充实时票价 |

各适配器的状态、输入输出与验证边界见 [数据渠道说明](Documentation/DATA_CHANNELS.md)。铁路购票链接始终指向 [铁路 12306 官方页面](https://www.12306.cn/mormhweb/zxdt/202412/t20241211_43192.html)。RollingGo 接入参考其[官方开源仓库](https://github.com/RollingGo-AI/RollingGo-hotel-MCP-CN)。

## 运行 iOS 应用

要求：iOS 17 或更新版本，建议使用 Xcode 26 或更新版本；当前发布验证工具链为 Xcode 27.0 beta、Swift 6.4 和 iOS 26.5 模拟器。工程使用 SwiftUI、MapKit、Observation、WebKit 和 Swift 6，不含第三方 App 运行时依赖。

```sh
xcodegen generate --spec project.yml
open AnyTravel.xcodeproj
```

选择 `AnyTravel` scheme 后即可运行。`project.yml` 是工程定义的源文件；提交前请重新生成一次 Xcode 工程。

调试启动参数：

- `--force-onboarding`：每次展示首次启动流程。
- `--skip-onboarding`：直接进入空白地图规划页。
- `--ui-test-ready`：载入带明确“演示价”标识的苏州完整方案，只用于界面验收。

## 运行开源报价节点

```sh
cd Backend
npm install
npx playwright install chromium
cp .env.example .env
set -a; source .env; set +a
npm start
```

随后在 App 的“旅途偏好与价格渠道”中填写节点地址。模拟器可用 `http://127.0.0.1:8787/`；真机需使用同一局域网内电脑的 IP。携程采集前运行 `npm run login:ctrip`，由用户在弹出的浏览器里自行登录。完整请求示例见 [Backend/README.md](Backend/README.md)。

## 验证

```sh
# iOS 单元测试与 UI 流程
xcodebuild \
  -project AnyTravel.xcodeproj \
  -scheme AnyTravel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/AnyTravelDerived \
  CODE_SIGNING_ALLOWED=NO \
  test

# 报价节点解析测试
cd Backend && npm test
```

0.2.0 发布前验证结果：13/13 iOS 单元测试、4/4 XCUITest、4/4 Node 测试通过；Release 配置模拟器构建通过。2026-08-31 的联网抽查中，“上海→苏州”返回上海站至苏州站的可购车次、余票和二等座价格。住宿实时价需要配置 RollingGo 密钥或先完成携程节点登录，因此仓库不附带伪造的“实时成功”截图。

## 隐私与边界

- 行程、默认偏好和平台会话保存在用户自己的设备；应用不读取平台密码。
- 自建报价节点的密钥和浏览器 Cookie 保留在运行节点的机器上，`.env` 与 `.data` 均不会提交。
- 价格会标注渠道、口径和抓取时间；最终房型、税费、退改、余票和订单以平台结算页为准。
- 本项目只读分析了用户提供的 FocusFlight IPA，用于理解地图优先的交互结构；没有复制或重新分发其代码与资源。详见 [参考审计](Documentation/REFERENCE_AUDIT.md)。

## 开源许可

AnyTravel 采用 [MIT License](LICENSE)。原创“折叠远方”图标的来源与缩放检查记录见 [视觉资产清单](Documentation/Brand/ASSET_MANIFEST.md)。
