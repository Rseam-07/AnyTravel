# AnyTravel 接力交接

> 更新于 2026-09-04，记录 0.8.0 发布候选的真实工程状态。目标见 [PLAN_TO_1_0](PLAN_TO_1_0.md)，功能清单见 [FEATURE_ROADMAP](FEATURE_ROADMAP.md)，价格来源见 [DATA_CHANNELS](DATA_CHANNELS.md)，资料许可见 [THIRD_PARTY_DATA](THIRD_PARTY_DATA.md)。

## 仓库与版本

- 工作目录：`/Users/conrad/Documents/ChatGPT/AnyTravel`
- 远端：`https://github.com/Rseam-07/AnyTravel.git`
- 分支：`main`
- iOS Bundle Identifier：`com.anytravel.app`
- iOS：`MARKETING_VERSION = 0.8.0`，`CURRENT_PROJECT_VERSION = 15`
- Android：`versionName = 0.8.0`，`versionCode = 15`
- iOS 工程以 `project.yml` 为源；修改后运行 `xcodegen generate --spec project.yml`。
- 发布密钥只从被 Git 忽略的 `Config/Secrets.xcconfig` 或运行环境注入，不得提交明文。

## 0.8.0 已经落地

1. **国内旅行知识库**
   - `Web/src/knowledge/domestic-guide-knowledge.json` 是生成后的主快照，并复制到 iOS 与 Android 资源。
   - 当前覆盖 162 个目的地，其中 141 个位于中国，含 1,234 个候选地点、12 条规划规则和 867 个去重来源。
   - 来源包括文化和旅游部及地方文旅公开页面、OpenStreetMap、Wikidata、Audiala、88250 城市中心数据和人工核对的高德坐标链接。
   - 采集脚本会校验城市归属、坐标、来源、重复项和分类平衡；不要手工分别改三端 JSON。

2. **更贴近真实日期的规划**
   - iOS、Android 与 Web 均把用户勾选、热门度、兴趣、空间聚类、停留时长、用餐、移动成本和每天容量纳入排程。
   - iOS 会按具体出发日期解析每周开放信息，识别常见周一闭馆，并在可行时调换日期或候选。
   - 同名同址、名称变体和相近坐标在排程前合并；相距较远的同名分店保留。

3. **实时住宿和大交通**
   - iOS 与 Android 均可在 App 内直连 RollingGo 酒店、铁路 12306 去返程班次/席别价和飞猪航班起价。
   - 同一酒店或班次的多渠道报价聚合到一张卡；真实结果会移除数值占位，用户手选后不被刷新覆盖。
   - Backend 继续承载携程/同程登录会话、艺龙开放平台、万邦目录、去哪儿门票和托管智能向导。

4. **Android 与 Web 完成度**
   - Android 已有生成前景点挑选、三档连续底部面板、开放式自然语言调整、住宿/交通筛选、地图聚焦、费用和本地保存；自定义模型 Key 使用 Keystore 加密。
   - Web 已完成地图优先四页流程、三档移动面板、资料选点、路线/天气/价格、自然语言调整、旅册、分享恢复、打印和可安装 PWA 外壳。

## 本轮可复核结果

- iOS 常规单元套件：执行 79 项，其中 3 项实时网络测试按设计跳过；0 失败。
- iOS 实时价格套件：3/3 实际联网、0 跳过、0 失败；分别验证 RollingGo 酒店、飞猪航班和 12306 铁路数字价格。
- iOS 价格首屏 XCUITest：2/2；设备 Release 构建通过。
- Android 常规单元套件：11 项中 2 项实时用例按设计跳过，其余通过；单独启用的三源价格聚合测试 1/1 通过；lint 与 `assembleDebug` 通过。
- Backend：48/48；Web：7/7，生产构建通过；知识库一致性校验通过。

## 当前边界

- IPA 无签名，需自签侧载；Android 为调试签名通用 APK。客户端内置服务密钥可以被提取，只应使用可轮换、有限额的发布凭据。
- 实时数字是查询时的展示价或起价，不等于锁价；库存、房型、舱位、税费、早餐和退改以购买页为准。
- 当前提供的默认 GLM 凭据在最新联网复核中返回 HTTP 401。三端仍可用本机规则理解常见中文调整；托管模型需更换有效凭据再验收。
- 去哪儿、携程和同程的登录型来源仍会受用户会话与页面验证影响；艺龙、万邦等商家接口未配置凭据时明确显示 `disabled`。
- Android 地图路线仍是游览顺序示意；编辑、门票、PDF/ICS、跨天复制和版本历史尚未追平 iOS。
- 本轮没有 Android 真机/模拟器 Compose 回归，也没有完成三端弱网、大字体、横屏和平板验收。

## 下一步顺序

1. 把共享规划契约下沉到 Backend，减少 iOS、Android、Web 三套规则漂移，并加入固定城市金样本回归。
2. 补多城市、跨城大交通、中途换住处和按夜拆分酒店；加入儿童年龄、房间数、床型、早餐和取消政策归一。
3. Android 补方案增删/拖动/撤销、门票、PDF/ICS、会话型渠道和逐路段路线。
4. 加入天气、季节、节庆、预约和临时闭馆的动态风险层；静态知识只作为候选，不冒充当天状态。
5. 完成价格历史、变价提醒、同房型归一、更多酒店官网直连和真实登录会话长期稳定性测试。

## 常用验证命令

```sh
node Web/scripts/assemble-knowledge.mjs
node Web/scripts/validate-knowledge.mjs

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project AnyTravel.xcodeproj -scheme AnyTravel \
  -destination 'platform=iOS Simulator,id=989F27BF-D650-4580-8AC5-D681FA908DBC'

cd Backend && npm test
cd ../Web && npm test && npm run build
cd ../Android && ./gradlew testDebugUnitTest lintDebug assembleDebug
```
