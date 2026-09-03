# AnyTravel 接力交接

> 更新于 2026-09-03，记录 iOS 0.7.0 发布候选的真实工程状态。目标与后续里程碑见 [PLAN_TO_1_0](PLAN_TO_1_0.md)，功能清单见 [FEATURE_ROADMAP](FEATURE_ROADMAP.md)，价格来源见 [DATA_CHANNELS](DATA_CHANNELS.md)。

## 仓库与构建

- 工作目录：`/Users/conrad/Documents/ChatGPT/AnyTravel`
- 远端：`https://github.com/Rseam-07/AnyTravel.git`
- 分支：`main`
- iOS Bundle Identifier：`com.anytravel.app`
- 0.7.0：`MARKETING_VERSION = 0.7.0`，`CURRENT_PROJECT_VERSION = 13`
- 工程以 `project.yml` 为源；提交前运行 `xcodegen generate --spec project.yml`，不要只手改 `project.pbxproj`。
- `Config/AnyTravel.xcconfig` 只定义公开的空默认值，并以可选方式包含被 Git 忽略的 `Config/Secrets.xcconfig`。后者用于向发布构建注入 RollingGo、高德和智谱默认配置，不得提交。

## 0.7.0 已实现

1. **默认酒店数字价格**
   - `RollingGoDirectClient` 按实际入住、离店日期、人数和景点锚点查询 RollingGo MCP。
   - 即使用户以前保存了失效的伴随服务地址，只要节点不可达、无结果或没有 RollingGo 数字报价，iOS 仍会继续走内置直连，不再被节点配置截断。
   - 同一住宿跨 RollingGo、携程、同程/艺龙、艺龙开放平台与万邦目录按名称、位置和分店语义合并；每个渠道的价格与购买入口单独保留。

2. **默认航班数字价格**
   - `FliggyFlightDirectClient` 使用飞猪公开 H5 MTOP 页面契约。普通匿名请求取得 `_m_h5_tk` Cookie 后完成页面签名；不使用账号令牌、设备指纹修改或私有客户端凭据。
   - 去程与返程各自按日期搜索，返回航司、航班号、机场、发到时刻、耗时、数字起价、抓取时间和购买页。
   - `QunarFlightDirectClient` 仅在用户明确保存过去哪儿网页会话后运行，避免默认后台触发验证码。
   - `NativeFlightOptionMerger` 按方向、航班号，或相近时刻与机场合并同一航班；飞猪、去哪儿、携程等渠道报价仍分别显示。

3. **生成与地图交互**
   - 生成前先列出按在线名次、评分和空间分布排序的景点；可勾选或跳过。主游览点停留更久，选少则顺路补齐，选多则保留并给压力提示。
   - 自动规划在空间聚类前合并跨来源重复地点，同时保留相距较远的同名分店。
   - 底部面板可连续拖到“只留输入框”或“几乎全屏”；每次业务操作后根据当前内容自动回到合适高度，不留固定空白。
   - 人数、抵达日、返程日均可用左右按钮增减；全局重置、设置、旅册、定位、地图样式与北向按钮都有真实操作闭环。

4. **其他直连与节点能力**
   - iOS 可直连铁路 12306 去返程班次、余票与席别价格。
   - 托管智能向导可优先走伴随服务，节点缺失时使用构建注入的 GLM 配置；用户也可填写自己的 OpenAI 兼容 Base URL、模型和 Key。
   - 高德 Web 服务可由节点或构建配置补充地点，坐标按 GCJ-02 → WGS84 语义转换。
   - Backend 已有艺龙开放平台、万邦携程目录、携程/同程浏览器会话与携程航班适配器；未配置商家凭据的通道会显示 `disabled`。

## 本轮实测

- iOS 单元测试：**68/68**，0 失败。
- iOS XCUITest：**16/16**，0 失败。覆盖三档拖拽、操作后自动适配、人数/日期按钮、完整方案编辑、保存、分享和全局地图按钮。
- Backend：**46/46**，0 失败。
- 飞猪真实网络：原生 `URLSession` 查询宁波（NGB）→天津（TSN）、2026-09-09，得到具体航班与大于零的数字起价。
- RollingGo 真实网络：iOS 构建注入的配置查询天津、2026-09-09 至 2026-09-11，得到至少一家带 `.live` 数字每晚价的酒店。
- 模拟器构建后的 `Info.plist` 已断言三个默认配置字段均非空；检查过程未输出其值。

## 仍需如实标注的边界

- 发布 IPA 无签名，需要用户自签后侧载。客户端内置 Key 可以从 IPA 中提取，应只使用可轮换、可限额的发布凭据。
- 飞猪和 RollingGo 都是查询当刻的展示起价；舱位、房型、库存、税费、早餐和退改以提交订单前的渠道页面为准。
- 去哪儿登录航班、携程航班、携程酒店与同程酒店仍受用户会话和页面验证影响。艺龙开放平台与万邦目录没有本机商家凭据，因此尚未做生产联网验收。
- 当前高德 Key 若仍为非“Web 服务”类型会返回 `USERKEY_PLAT_NOMATCH (10009)`；此时 App 使用 Apple Maps，不把高德写成成功。
- 本轮没有完成真机、弱网、大字体和长期 Cookie 稳定性测试；模拟器自动化通过不能替代这些验收。
- Android 0.4 尚未追平 iOS 0.7 的景点挑选、自然语言向导、原生价格直连、面板交互、编辑、门票和 PDF/ICS。

## 下一步顺序

1. Android 先补共享价格契约、飞猪/12306/RollingGo 直连和景点挑选，再补地图面板与编辑，避免只复制 UI。
2. iOS 增加儿童年龄、房间数、床型/早餐/取消政策归一，以及酒店与交通联合评分权重。
3. 完成去哪儿/携程登录会话的真实数字验收、价格历史和变价提醒。
4. 把规划决策逐步下沉到 Backend 共享契约，让 iOS、Android 与 Web 使用同一份可解释方案。
5. 补多城市、中途换住处、天气/闭馆风险、方案对比、文本/链接导入、分享协作和足迹。

## 常用验证命令

```sh
xcodegen generate --spec project.yml

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project AnyTravel.xcodeproj -scheme AnyTravel \
  -destination 'platform=iOS Simulator,id=989F27BF-D650-4580-8AC5-D681FA908DBC' \
  -derivedDataPath /tmp/AnyTravel-0.7-FullTests

cd Backend && npm test
```
