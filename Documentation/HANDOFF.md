# AnyTravel 接力交接

> 更新于 2026-09-05，记录 0.8.2 的真实工程状态。目标见 [PLAN_TO_1_0](PLAN_TO_1_0.md)，功能清单见 [FEATURE_ROADMAP](FEATURE_ROADMAP.md)，价格来源见 [DATA_CHANNELS](DATA_CHANNELS.md)，资料许可见 [THIRD_PARTY_DATA](THIRD_PARTY_DATA.md)。

## 仓库与版本

- 工作目录：`/Users/conrad/Documents/ChatGPT/AnyTravel`
- 远端：`https://github.com/Rseam-07/AnyTravel.git`
- 分支：`main`
- iOS Bundle Identifier：`com.anytravel.app`
- iOS：`MARKETING_VERSION = 0.8.2`，`CURRENT_PROJECT_VERSION = 17`
- Android：`versionName = 0.8.2`，`versionCode = 17`
- iOS 工程以 `project.yml` 为源；修改后运行 `xcodegen generate --spec project.yml`。
- 发布密钥只从被 Git 忽略的 `Config/Secrets.xcconfig` 或运行环境注入，不得提交明文。

## 0.8.2 已经落地

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
   - iOS 与 Android 均优先直连 RollingGo 酒店，并并行补充雅高集团官网公开选日房价、希尔顿官网品牌目录、铁路 12306 去返程班次/席别价和飞猪航班起价。
   - 同一酒店或班次的多渠道报价聚合到一张卡；真实结果会移除数值占位，用户手选后不被刷新覆盖。
   - Backend 继续承载携程/同程登录会话、艺龙开放平台、万邦目录、去哪儿门票和托管智能向导；公开官网适配器即使没有合作方凭据也能独立返回目录或选日价格。

4. **Android 与 Web 完成度**
   - Android 已有生成前景点挑选、18%–94% 连续底部面板、开放式自然语言调整、住宿/交通筛选、地图聚焦、长按地图加点、日程增删/跨天移动、30 步撤销重做、PDF/ICS 导出、费用和本地保存；自定义模型 Key 使用 Keystore 加密。
   - Android 路线优先采用 Valhalla 道路几何，失败才明确降级为示意线；旧行程恢复时会丢弃体积过大的缓存路线并重新拉取路线和当前报价。
   - Android 12 采用 MapLibre OpenGL、TextureView、像素倍率上限、较低预取与增量地图更新，避免面板拖动和大批报价刷新同时触发地图重建。
   - Web 已完成地图优先四页流程、三档移动面板、资料选点、路线/天气/价格、自然语言调整、旅册、分享恢复、打印和可安装 PWA 外壳。

5. **可靠性与重复代码整顿**
   - Android 报价、路线与智能向导共用统一网络边界，集中处理版本标识、超时、取消、响应大小和连接释放。
   - iOS 与 Android 各自只保留一套住宿名称归一、品牌官网映射和同一物业判断；同楼不同品牌、远距离同名分店与多渠道报价保留均有回归测试。
   - iOS 和伴随服务的请求版本标识从构建元数据读取，不再散落硬编码版本号。
   - iOS 面板使用单一手动档位和可自动复位的手势位移；把手与内容层独立，键盘不会改变手选档位，提交后自动适配。界面测试同时检查实际高度、可点击性与返回主要内容的闭环。
   - 具体酒店品牌与所属集团分别处理，同集团不同品牌不会因接近坐标而误并；空名称也不能作为同一物业证据。
   - 当前 Android lint 的 Kotlin 分析器并行运行 Debug/Release 分析时出现过内部指针失效，串行 `--no-parallel --max-workers=1` 全量通过；没有关闭任何 lint 检查。

## 本轮可复核结果

- iOS 常规单元套件：执行 86 项，其中 3 项实时网络测试按设计跳过；其余 83 项通过，0 失败。常规界面套件 18 项中 16 项通过、2 项联网用例按设计跳过。
- iOS 独立联网套件：3 项价格源测试和 2 项价格首屏 XCUITest 全部通过，0 跳过、0 失败；截图中出现 RollingGo 酒店每晚价、飞猪航班起价和铁路 12306 班次/席别价，价格卡片可点击。设备 Release 构建通过。
- Android 常规单元套件：27 项中 25 项通过、2 项联网用例按设计跳过；另行开启 1 项真实聚合测试，酒店、航班与铁路数字结果通过，0 跳过。lint 与 Release 通用 APK 构建通过。
- Backend：53/53；Web：7/7，生产构建与知识库一致性校验通过。

## 当前边界

- IPA 无签名，需自签侧载；Android 发布包使用 Release 编译设置和公开预览签名，并非生产签名。客户端内置服务密钥可以被提取，只应使用可轮换、有限额的发布凭据。
- 实时数字是查询时的展示价或起价，不等于锁价；库存、房型、舱位、税费、早餐和退改以购买页为准。
- 当前提供的默认 GLM 凭据在最新联网复核中返回 HTTP 401。三端仍可用本机规则理解常见中文调整；托管模型需更换有效凭据再验收。
- 去哪儿、携程和同程的登录型来源仍会受用户会话与页面验证影响；艺龙、万邦等商家接口未配置凭据时明确显示 `disabled`。
- Android 已支持地图长按加点、同日/跨天移动、删除、撤销重做和 PDF/ICS；仍缺搜索式精确加点、拖拽重排、跨天复制、景点门票、门到门接驳和版本历史。
- 本轮没有 Android 真机/模拟器 Compose 回归，也没有 Xperia 1 II 实体设备，所以索尼 Android 12 闪退只能做代码级规避，不能写成真机已修复；三端弱网、大字体、TalkBack、横屏和平板也仍待验收。
- 雅高官网公开选日价格已经联网验收；希尔顿当前只提供公开城市目录与官网入口，不冒充选日实时价。其他品牌官网仍需逐家建立稳定的查询契约。

## 下一步顺序

1. 把共享规划契约下沉到 Backend，减少 iOS、Android、Web 三套规则漂移，并加入固定城市金样本回归。
2. 补多城市、跨城大交通、中途换住处和按夜拆分酒店；加入儿童年龄、房间数、床型、早餐和取消政策归一。
3. Android 补搜索式加点、拖拽排序、跨天复制、门票、门到门接驳和会话型渠道，并在 Xperia 1 II/Android 12 上抓取真实 tombstone 与 logcat 做稳定性闭环。
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
cd ../Android && ./gradlew testDebugUnitTest lintDebug assembleDebug assembleRelease
```
