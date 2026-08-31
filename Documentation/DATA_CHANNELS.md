# AnyTravel 数据渠道

AnyTravel 把每个来源做成独立适配器。某个渠道没有返回时，其他渠道和地图路线仍然可以继续工作；前端只把带价格与抓取时间的结果标成实时价。

## 地点、住宿位置与市内路线

App 直接使用 Apple MapKit：`MKLocalSearch` 搜索目的地、景点、酒店、民宿、机场和车站，`MKDirections` 计算当前日的真实路段。MapKit 返回的住宿网站会作为“住宿官网”入口保留，但是否为物业直营网站仍由用户在打开后判断。

官方资料：[MKLocalSearch](https://developer.apple.com/documentation/mapkit/mklocalsearch)、[MKDirections](https://developer.apple.com/documentation/mapkit/mkdirections)。

## 住宿价格

### RollingGo

`Backend/src/adapters/rollinggo.mjs` 调用 RollingGo 酒店 MCP 的 `searchHotels` 工具。配置 `ROLLINGGO_API_KEY` 后才启用；节点会为 App 先找到的候选逐店查询，最多并行处理 8 家，只接受完整酒店名相等或互相包含的强匹配。RollingGo 返回“多晚总价”时，节点会按住宿晚数换算为每晚价，再附上抓取时间与购买链接。

项目资料：[RollingGo hotel MCP CN](https://github.com/RollingGo-AI/RollingGo-hotel-MCP-CN)。

### 携程

`Backend/src/adapters/ctrip.mjs` 使用 Playwright 持久化用户浏览器会话。运行 `npm run login:ctrip` 后，用户自行在携程页面完成登录；节点随后读取公开搜索结果卡片，并只接收能与 App 酒店候选匹配的价格。它不会读取密码，也不会把评论数等数字误认成价格。

酒店卡片结构参考了当前公开的浏览器操作资料：[browser-harness 的携程酒店说明](https://github.com/browser-use/browser-harness/blob/main/agent-workspace/domain-skills/ctrip/hotels.md) 与 [ctrip-hotel-skill](https://github.com/biaowuqiong/ctrip-hotel-skill)。

2026-08-31 的联网验收中，3 个苏州酒店候选均取得实时展示价和购买链接。未匹配结果不会被错误贴到其他酒店卡片上。

### 去哪儿、Trip.com 与住宿官网

App 已提供应用内登录、Cookie 会话复用和购买页入口。iOS 0.5.0 会在保存前确认对应平台域名已有有效 Cookie，并在 Cookie 失效后撤销会话状态。去哪儿当前公开桌面酒店搜索入口会回到综合首页，其开放平台主要面向酒店供应商，因此没有把它写成已验证的实时价格源。节点接口保留独立适配器位置，后续接入不会改变 iOS 数据模型。

平台资料：[去哪儿酒店开放平台](https://open.hotel.qunar.com/)、[携程分销合作](https://pages.ctrip.com/public/dlhz.htm)。

## 铁路

`Backend/src/adapters/railway12306.mjs` 读取铁路 12306 的公开车站表、余票查询和席别价格。它按抵达日查询出发地→目的地，再按返程日独立查询目的地→出发地；两次查询并行完成，单边失败时仍保留另一边的结果和方向诊断。每个方向都优先主站对主站的可购车次，返回车次、发到时刻、耗时、余票、二等座或其他可用席别价格。节点只读查询，不会代替用户提交订单；购买始终回到官方页面。

2026-08-31 的联网实查中，“上海→苏州”与“苏州→上海”分别返回 8 个可购车次，两边均取得席别价格与余票。App 依据 `direction` 将结果拆入去程和返程卡片，保存各自选择，并在费用表中分别计算。

铁路 12306 明确其网站与客户端为官方互联网售票渠道：[铁路 12306 公告](https://www.12306.cn/mormhweb/zxdt/202412/t20241211_43192.html)。开源实现调研包括 [Joooook/12306-mcp](https://github.com/Joooook/12306-mcp) 和 [mcp-server-12306 查询文档](https://github.com/drfccv/mcp-server-12306/blob/main/docs/query_tickets.md)。

## 航班

iOS 数据模型已支持航班卡、机场到住宿距离、报价和购买链接。0.5.0 仍只显示明确的渠道查询入口；真正的聚合实时价需要后续配置合作接口。Skyscanner 的 Live Prices 接口采用 create/poll 流程，并要求 API key，接入时应按其[航班实时价格说明](https://developers.skyscanner.net/docs/flights-live-prices/overview)和[认证说明](https://developers.skyscanner.net/docs/getting-started/authentication)实现。

## 返回给 App 的共同字段

住宿报价包含：候选酒店 ID/名称、渠道、人民币金额、每晚或总价口径、`live`/`indicative` 类型、抓取时间、购买 URL 和说明。

交通结果包含：方向、渠道、交通方式、班次号、始发与到达站、发到时间、耗时、价格、席别、余票、抓取时间和购买 URL。App 会把它与地图中的机场/车站及已选住宿匹配，再分别计算抵达和返程接驳距离。
