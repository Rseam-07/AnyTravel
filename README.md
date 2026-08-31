# AnyTravel

> 旅行是一场诗意的迁徙。AnyTravel 让每一次选择，都在地图上长成旅程。

AnyTravel 是一款地图优先的开源 iOS 与 Android 旅行规划应用。用户不必先填完一张长表格：可以先选车次，也可以先挑住处；可以从预算出发，也可以只说“我想去XX”。路线、住宿、抵达枢纽和每天的安排都会在背景地图上随选择更新。

<p align="center">
  <img src="Documentation/Brand/Exports/folded-horizon.png" width="128" alt="AnyTravel 折叠远方图标">
</p>

![首次进入：旅行是一场诗意的迁徙](Documentation/Screenshots/onboarding.png)

![地图上的完整苏州方案](Documentation/Screenshots/complete-plan.png)

![跨天复制、撤销与重做](Documentation/Screenshots/itinerary-editor.png)

![去程与返程拥有各自的班次、价格与选择](Documentation/Screenshots/round-trip-transport.png)

![车站与住处之间也有完整的接驳选择](Documentation/Screenshots/door-to-door-transfer.png)

![把完整方案导出为 PDF，并交给系统分享页](Documentation/Screenshots/plan-export-share.png)

动效实录：[首次启动与初始化](Documentation/Demo/onboarding-motion.mp4) · [地图、住宿、交通与费用联动](Documentation/Demo/map-plan-motion.mp4)

下载：[iOS 0.5.4 无签名 IPA](https://github.com/Rseam-07/AnyTravel/releases/tag/v0.5.4) · [Android 0.4.0 APK](https://github.com/Rseam-07/AnyTravel/releases/tag/v0.4.0)

<p align="center">
  <img src="Documentation/Screenshots/android-welcome.png" width="30%" alt="Android 欢迎页">
  <img src="Documentation/Screenshots/android-plan.png" width="30%" alt="Android 地图方案">
  <img src="Documentation/Screenshots/android-live-stays.png" width="30%" alt="Android 实时酒店比价">
</p>

## 一段旅程如何展开

- 第一次打开应用时，先看四页简短介绍，再留下常用出发地、人数和预算。行程默认保持轻松节奏。
- iOS 可在应用内登录携程、去哪儿、Trip.com 和铁路 12306；Android 0.4 先提供平台页面入口。密码只提交给平台网页，AnyTravel 不读取或保存密码。
- 日期、预算、兴趣、住宿和交通没有固定填写顺序，每一项都可以暂时留白。
- `MKLocalSearch` 会寻找真实景点、酒店、民宿和交通枢纽；`MKDirections` 会逐段绘制当前日路线。
- 方案生成后仍可继续搜索 Apple Maps 地点、添加或删除停靠、拖动顺序、跨天移动或复制，并可撤销与重做；也能修改日期、出发地、人数、预算与交通偏好。地图路线和受影响的住宿、交通会重新计算。
- 选定住处后，交通建议会结合抵达时间、车站或机场到住处的距离、总耗时和票价重新排列；铁路去程与返程分别查询、选择和计入费用。
- 每一段大交通还会继续接到门前：分别比较车站或机场与住处之间的地铁公交、打车和步行，选择后地图切换到对应接驳线，费用表单列往返接驳。
- 最终方案包含每天的具体时段、地点介绍、路线、住宿候选、交通方式、购买入口和费用明细。
- 完整方案可以折成带地图的多页 PDF，也可以把每天的安排写成可导入系统日历的 `.ics`；两种文件都经由 iOS 系统分享页带走。
- 用户拖动地图时，自动镜头立即让出控制；点击卡片、车站或酒店时，地图再把相应位置带回视野。
- 欢迎页、路线展开、地图标记、标签滑块、卡片选择和报价刷新使用同一套可中断弹簧动效；系统开启“减少动态效果”后会自动改用淡入淡出或静态反馈。

## 当前数据能力

| 内容 | 当前实现 | 结果如何展示 |
| --- | --- | --- |
| 地点与市内路线 | iOS 使用 Apple MapKit；Android 使用人工核对目的地包与系统 Geocoder | 地图标记、逐日顺序、距离与预计时间；Android 0.4 明确标注路线为示意 |
| 酒店与民宿位置 | Apple Maps 候选；按景点均距和交通枢纽距离排序 | 地图卡片与推荐理由 |
| 酒店实时价格 | 两端支持 RollingGo MCP（配置密钥后）；iOS 另支持用户自行登录后的携程持久化浏览器会话 | 渠道、每晚/总价口径、抓取时间、缓存过期、部分成功与失败原因、购买入口 |
| 铁路班次与票价 | 铁路 12306 公开查询页，按抵达日与返程日分别只读查询 | 去程/返程独立车次、发到时间、余票、席别价格与官方购票页；单边失败不遮住另一边 |
| 门到门接驳 | iOS 使用 Apple MapKit 分别查询去程枢纽→住宿、住宿→返程枢纽的公交、驾车和步行 | 地图路线、耗时、距离、估算费用与推荐理由；地图缺少公交路线时明确标成“距离估算” |
| 方案导出 | iOS 原生生成带地图的多页 PDF 与标准 iCalendar 文件 | 日程、住处、往返交通、接驳和费用完整落款；无日期仍可导出 PDF，日历会明确要求先补日期 |
| 去哪儿与 Trip.com | iOS 支持应用内登录与会话复用；Android 提供购买页入口 | 未接通实时适配器时明确显示“到渠道查询” |
| 航班 | 已预留携程、去哪儿与 Skyscanner 适配位置 | 当前先提供渠道入口，不把估算冒充实时票价 |

各适配器的状态、输入输出与验证边界见 [数据渠道说明](Documentation/DATA_CHANNELS.md)，PDF 与日历的字段和降级规则见 [方案导出说明](Documentation/EXPORT_FORMATS.md)。铁路购票链接始终指向 [铁路 12306 官方页面](https://www.12306.cn/mormhweb/zxdt/202412/t20241211_43192.html)。RollingGo 接入参考其[官方开源仓库](https://github.com/RollingGo-AI/RollingGo-hotel-MCP-CN)。

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
- `--force-onboarding --motion-showcase`：在 Debug 中自动播放首次启动动效。
- `--ui-test-ready --motion-showcase-ready`：在 Debug 中自动播放地图方案标签与镜头联动。

## 运行 Android 应用

要求：JDK 17、Android SDK Platform 37.0 与 Build Tools 37.0.0；最低运行系统 Android 12（API 31）。

```sh
cd Android
./gradlew testDebugUnitTest assembleDebug
```

现代手机优先安装 `app-arm64-v8a-debug.apk`；不确定处理器时使用 `app-universal-debug.apk`。连接 Android 12 或更新版本的设备后，可运行 `./gradlew connectedDebugAndroidTest`。更多数据与签名边界见 [Android 说明](Android/README.md)。

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

0.5.4 发布前验证结果：29/29 iOS 单元测试、8/8 XCUITest、9/9 Node 测试通过；iPhone 17 Pro 模拟器真实生成一份带地图的完整方案 PDF，并进入系统分享页显示“存储到文件”。自动化样本生成 4 页 A4 PDF 与包含 15 个日程事件的 `.ics`，四页均完成渲染检查；设备 Release 构建产物为 0.5.4（8）。地图快照不可用时，PDF 会留下明确说明，不会绘制虚构路线。密钥只保存在被 Git 忽略的节点环境文件中。

0.4.0 Android 发布前验证结果：4/4 规划逻辑单元测试、1/1 Android 12 Compose 端到端流程和 lint 通过。APK 在 API 31 arm64 模拟器完成安装与视觉检查，并实际连接同一报价节点，显示 RollingGo 酒店实时价和铁路 12306 班次、票价、余票、接驳距离与抓取时间。APK 为调试签名预览包，尚未替代生产签名和真机矩阵。

## 隐私与边界

- 行程、默认偏好和平台会话保存在用户自己的设备；应用不读取平台密码。
- iOS 只有在对应平台网页留下有效 Cookie 后才会显示“会话已保存”；Cookie 失效后会自动撤销该状态。
- 自建报价节点的密钥和浏览器 Cookie 保留在运行节点的机器上，`.env` 与 `.data` 均不会提交。
- 价格会标注渠道、口径和抓取时间；最终房型、税费、退改、余票和订单以平台结算页为准。
- 本项目只读分析了用户提供的 FocusFlight IPA，用于理解地图优先的交互结构；没有复制或重新分发其代码与资源。详见 [参考审计](Documentation/REFERENCE_AUDIT.md)。

## 开源许可

AnyTravel 采用 [MIT License](LICENSE)。原创“折叠远方”图标的来源与缩放检查记录见 [视觉资产清单](Documentation/Brand/ASSET_MANIFEST.md)。
