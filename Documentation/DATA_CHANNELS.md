# AnyTravel 数据渠道

AnyTravel 把每个来源做成独立适配器。某个渠道没有返回时，其他渠道和地图路线仍然可以继续工作；前端只把带价格与抓取时间的结果标成实时价。

## 地点、住宿位置与市内路线

App 直接使用 Apple MapKit：`MKLocalSearch` 搜索目的地、景点、酒店、民宿、机场和车站，`MKDirections` 计算当前日的真实路段。MapKit 返回的住宿网站会作为“住宿官网”入口保留，但是否为物业直营网站仍由用户在打开后判断。

iOS 还会在伴随服务已接通时请求高德 Web 服务地点搜索。节点使用官方 v5 文本搜索，并请求 `show_fields=business`，因此可在高德返回时带回今日/每周营业时间、评分与人均消费。节点保留 GCJ-02 原始坐标，并把近似反算的 WGS84 坐标连同 `sourceCRS`、`outputCRS` 一起返回；客户端只接受坐标语义完整、范围有效的候选，并明确标成“高德地图 · Web服务”。高德失败不会阻断 MapKit 结果。`AMAP_API_KEY` 必须是控制台中平台类型为“Web 服务”的 Key；当前提供的 Key 在联网验证中返回 `USERKEY_PLAT_NOMATCH (10009)`，因此尚未把它标记为可用来源。

接口字段以[高德 Web 服务新版 POI 搜索文档](https://lbs.amap.com/api/webservice/guide/api-advanced/newpoisearch)为准。营业时间会参与排程，但节假日、预约批次和临时闭馆仍需复核。

官方资料：[MKLocalSearch](https://developer.apple.com/documentation/mapkit/mklocalsearch)、[MKDirections](https://developer.apple.com/documentation/mapkit/mkdirections)。

### 机场/车站与住宿之间的接驳

iOS 0.5.3 会在用户选定大交通和住宿后，用 `MKDirections` 分别查询去程枢纽→住宿、住宿→返程枢纽的公共交通、驾车与步行路线。卡片保留 MapKit 返回的耗时和距离；公交费用按当地常见里程票制与同行人数估算，打车费用按里程和行车时间估算，均不写成平台实时报价。

如果 MapKit 没有返回公共交通路线，但已经取得驾车或步行距离，App 会保留一张明确写着“距离估算”的公交卡，并提醒出发前复核。它不会绘制虚构的公交折线，也不会优先于已经取得的真实驾车路线。用户选中的往返接驳会分别写入费用表和本机旅册；接驳金额从原有市内交通额度中扣除，避免重复计算。

2026-08-31 联网验收“苏州站→苏州吴宫泛太平洋酒店”时，MapKit 返回驾车 18 分钟、6.98 公里，步行 98 分钟、6.27 公里；公共交通在当前运行环境返回无可用路线，App 因而展示带复核提示的距离估算卡。

## 住宿价格

### RollingGo

`Backend/src/adapters/rollinggo.mjs` 调用 RollingGo 酒店 MCP 的 `searchHotels` 工具。配置 `ROLLINGGO_API_KEY` 后才启用。目录搜索先查目的地城市，再以每天的代表景点为锚点补查最多三次；每个请求遵守公开工具的 `size <= 20`，合并名称与坐标后最多保留 40 家。逐店报价最多并行处理 12 家，只接受完整酒店名相等或互相包含的强匹配。`lowestPrice` 与 `minPrice` 按每晚最低价处理，只有字段或文案明确写为“总价/合计”时才按住宿晚数换算。

2026-09-01 联网实查苏州城市及拙政园、金鸡湖、虎丘山三个景点锚点，4 个请求全部成功，合并去重后返回 18 家带价格酒店。这个数字只记录当次覆盖范围，价格与可订状态仍以用户所选日期再次查询为准。

项目资料：[RollingGo 酒店 Skill CN](https://github.com/RollingGo-AI/rollinggo-hotel-skill-cn)。

### 携程

`Backend/src/adapters/ctrip.mjs` 使用 Playwright 持久化用户浏览器会话。节点先调用公开酒店联想端点，将每个 Apple Maps 候选严格解析为携程酒店 ID，再打开带真实日期且只指向该酒店的公开列表；运行 `npm run login:ctrip` 后，用户自行在携程页面完成登录。节点只接收名称强匹配的数字价格，不读取密码，也不会把评论数等数字误认成价格。

酒店卡片结构参考了当前公开的浏览器操作资料：[browser-harness 的携程酒店说明](https://github.com/browser-use/browser-harness/blob/main/agent-workspace/domain-skills/ctrip/hotels.md) 与 [OpenCLI 的携程浏览器适配说明](https://github.com/jackwener/OpenCLI/blob/main/docs/adapters/browser/ctrip.md)。

2026-08-31 的联网验收中，3 个苏州酒店候选均取得实时展示价和购买链接。2026-09-01 再次实查时，公开联想接口把“苏州吴宫泛太平洋酒店”解析为酒店 ID `346290`，目标列表只返回这一家，但当前持久会话显示“登录以查看会员价”，节点因而返回 `login_required`。未匹配或未登录的结果不会被错误贴到酒店卡片上。

### 同程旅行 / 艺龙

`Backend/src/adapters/tongcheng.mjs` 使用 Playwright 持久化用户浏览器会话。它通过公开移动首页选择城市，取得平台生成的城市编码，再把真实入住/离店日期带到酒店列表。解析器只接受酒店名称强匹配且卡片中出现明确人民币数字价格的结果，并保留早餐、免费取消等可见说明。

运行 `npm run login:tongcheng` 后由用户自行处理登录与平台验证。页面只写“登录查看低价”时返回 `login_required`；出现安全验证或账号异常时返回 `verification_required`；两种状态都不会产生伪造价格。2026-09-01 的正常 Chrome 实查已确认苏州城市编码 `1102` 和日期参数正确进入公开列表，但新会话触发平台验证，因此尚未宣称取得同程数字实时报价。

### 去哪儿、Trip.com 与住宿官网

App 已提供应用内登录、Cookie 会话复用和购买页入口。iOS 会在保存前确认对应平台域名已有有效 Cookie，并在 Cookie 失效后撤销会话状态。去哪儿当前公开桌面酒店搜索入口会回到综合首页，其开放平台主要面向酒店供应商，因此没有把它写成已验证的实时价格源。节点接口保留独立适配器位置，后续接入不会改变 iOS 数据模型。

平台资料：[去哪儿酒店开放平台](https://open.hotel.qunar.com/)、[携程开放平台](https://developer.ctrip.com/)、[携程商旅 OpenAPI](https://openapi.ctripbiz.com/)。

## 景点门票

`Backend/src/qunar-ticket-service.mjs` 读取去哪儿门票公开列表 JSON。节点先查目的地热门景点，再对未命中的用户地点做有限次数精确搜索；只有名称相等或高相似且地址不冲突时才回填。返回值保留公开页当前展示起价、抓取时间和景点详情购买链接，iOS 会同时把它写入地点卡、当日时间轴与多人费用表。公开列表不是指定日期的库存接口，因此计划日期、票种、优惠、预约批次和是否售罄必须在购买页再次确认。

2026-09-01 联网实查“苏州”取得 15 个景点；对当前行程中的拙政园、狮子林与虎丘山分别匹配到 `¥80`、`¥38.2` 和 `¥70` 的公开展示起价，并得到各自详情页。可复现的公开端点用法也见开源项目 [jingdianpachong 的去哪儿示例](https://github.com/impxiahuaxian/jingdianpachong/blob/main/qunar.py)。这些数字只说明抓取当刻的公开起价，不代表计划日期的最终成交价。

## 铁路

`Backend/src/adapters/railway12306.mjs` 读取铁路 12306 的公开车站表、余票查询和席别价格。它按抵达日查询出发地→目的地，再按返程日独立查询目的地→出发地；两次查询并行完成，单边失败时仍保留另一边的结果和方向诊断。每个方向都优先主站对主站的可购车次，返回车次、发到时刻、耗时、余票、二等座或其他可用席别价格。节点只读查询，不会代替用户提交订单；购买始终回到官方页面。

2026-08-31 的联网实查中，“上海→苏州”与“苏州→上海”分别返回 8 个可购车次，两边均取得席别价格与余票。App 依据 `direction` 将结果拆入去程和返程卡片，保存各自选择，并在费用表中分别计算。

铁路 12306 明确其网站与客户端为官方互联网售票渠道：[铁路 12306 公告](https://www.12306.cn/mormhweb/zxdt/202412/t20241211_43192.html)。开源实现调研包括 [Joooook/12306-mcp](https://github.com/Joooook/12306-mcp) 和 [mcp-server-12306 查询文档](https://github.com/drfccv/mcp-server-12306/blob/main/docs/query_tickets.md)。

## 航班

iOS 数据模型已支持航班卡、机场到住宿距离、报价和购买链接。0.5.0 仍只显示明确的渠道查询入口；真正的聚合实时价需要后续配置合作接口。Skyscanner 的 Live Prices 接口采用 create/poll 流程，并要求 API key，接入时应按其[航班实时价格说明](https://developers.skyscanner.net/docs/flights-live-prices/overview)和[认证说明](https://developers.skyscanner.net/docs/getting-started/authentication)实现。

## 智能向导

`POST /v1/assistant/interpret` 使用服务端环境变量中的 `ZAI_API_KEY`、`ZAI_BASE_URL` 和 `ZAI_MODEL` 调用智谱 OpenAI 兼容接口，默认模型为 `glm-5.3-flash`。上下文只包含当前行程条件与已有地点；服务端只接受目的地、出发地、日期、天数、人数、预算、节奏、市内/长途交通、兴趣、住宿价格/排序、聚焦/移除已有地点和生成方案等白名单动作，iOS 收到后还会再次校验名称、范围和枚举。

iOS 设置也支持用户自己的 OpenAI 兼容服务。Base URL 与模型名保存在本机偏好，自定义 API Key 使用 Keychain 的“仅此设备”保护，页面不会把已保存 Key 读回明文。托管服务不可用时，已经能由本机确定的“轻松一点”“公交优先”等指令仍会继续执行；无法确定的内容会保留为可恢复的提示。

## 返回给 App 的共同字段

住宿报价包含：候选酒店 ID/名称、渠道、人民币金额、每晚或总价口径、`live`/`indicative` 类型、抓取时间、购买 URL 和说明。

交通结果包含：方向、渠道、交通方式、班次号、始发与到达站、发到时间、耗时、价格、席别、余票、抓取时间和购买 URL。App 会把它与地图中的机场/车站及已选住宿匹配，再分别计算抵达和返程接驳距离。
