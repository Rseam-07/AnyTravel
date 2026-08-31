# AnyTravel 伴随服务

这个伴随服务把 App 的候选酒店统一交给多个价格源，也负责托管自然语言行程控制器。密钥、浏览器 Cookie 和抓取逻辑留在自建节点，iOS App 不内置供应商密钥。

## 启动

```sh
cd Backend
npm install
npx playwright install chromium
cp .env.example .env
set -a; source .env; set +a
npm start
```

健康检查：`curl http://127.0.0.1:8787/health`。在 AnyTravel 的“旅途偏好与价格渠道”中填写这个地址；真机需填写电脑在同一局域网内的 IP，例如 `http://192.168.1.10:8787/`。
服务默认只监听本机。需要让同一局域网中的 iPhone 访问时，把 `.env` 中的 `HOST` 改为 `0.0.0.0`，并只在可信网络中运行。

## 数据源

- `ROLLINGGO_API_KEY`：优先实时源。节点会对 App 给出的酒店候选逐店调用 RollingGo `searchHotels`，最多并行查询 8 家；只接收名称强匹配的酒店，把多晚总价换算成每晚口径，并保留预订链接和抓取时间。
- `CTRIP_SCRAPER_ENABLED=true`：使用持久化 Chromium 会话读取携程搜索结果。先运行 `npm run login:ctrip`，由用户在携程页面自行登录；Cookie 只保存在 `Backend/.data/ctrip-profile`，该目录不会提交到 Git。
- 携程解析只接受能与 App 候选酒店名称匹配的结果，并保存抓取时间。列表中的“起”价会明确标注，房型、早餐、税费和退改仍以结算页为准。
- `/v1/quotes/transport` 会通过铁路 12306 的公开查询页面分别读取去程与返程的可购车次、发到时间、余票和展示票价。两边并行查询，单边失败不会遮住另一边；它只查询，不提交订单，购买链接始终指向铁路 12306。结果默认缓存 5 分钟。
- `ZAI_API_KEY`、`ZAI_BASE_URL` 与 `ZAI_MODEL`：为 `POST /v1/assistant/interpret` 提供默认智能向导。当前默认模型为 `glm-5.3-flash`；模型只能返回白名单内的路线动作，服务端还会再次校验地点名、预算和枚举值。
- `AMAP_API_KEY`：预留给高德 Web 服务地点适配器。它必须是在高德控制台创建的“Web 服务”Key；iOS SDK Key 会返回平台不匹配，不能放进后端冒充使用。

住宿接口是 `POST /v1/quotes/accommodations`，交通接口是 `POST /v1/quotes/transport`。两者都会返回 `diagnostics`，某个渠道失败时其他渠道仍能继续返回。

地点补充接口是 `POST /v1/places/search`。高德原始 GCJ-02 坐标与反算后的 WGS84 坐标语义都会随响应保留；只有 Web 服务 Key 验证通过后，客户端才应把这些候选合并进主地图。

住宿请求示例：

```sh
curl -sS http://127.0.0.1:8787/v1/quotes/accommodations \
  -H 'content-type: application/json' \
  --data '{
    "destination":"苏州市",
    "checkIn":"2026-09-10",
    "checkOut":"2026-09-12",
    "adults":2,
    "rooms":1,
    "hotels":[{
      "id":"0F4A7E55-3F85-4A5F-B314-7788FAEAB627",
      "name":"苏州吴宫泛太平洋酒店",
      "latitude":31.286,
      "longitude":120.622
    }]
  }'
```

铁路请求示例：

```sh
curl -sS http://127.0.0.1:8787/v1/quotes/transport \
  -H 'content-type: application/json' \
  --data '{
    "origin":"上海",
    "destination":"苏州市",
    "departureDate":"2026-09-10",
    "returnDate":"2026-09-12",
    "adults":2,
    "modes":["train"]
  }'
```

返回的每个铁路结果都有 `direction`（`outbound` 或 `return`）。两个方向分别保留适配器排序：主站对主站优先，其次是高铁/动车、白天班次和较短耗时。App 不会再按最低价重新打乱车站优先级。

单元测试：`npm test`。服务默认缓存相同请求 10 分钟并限制每个 IP 每分钟 30 次请求，避免用户滚动卡片时重复抓取。

## 当前验证边界

- 2026-08-31 已联网验证“上海⇄苏州”：去程与返程各返回 8 个可购车次，两边均取得发到时间、余票与席别价格。
- 携程匿名搜索当日会进入登录页；因此实时采集必须先运行 `npm run login:ctrip`，不能把匿名失败写成实时成功。
- 2026-08-31 已使用私有环境变量联网验证 RollingGo：3 个苏州酒店候选均返回实时展示价和可购买链接，多晚总价正确换算为每晚；密钥未写入仓库或客户端。
- 2026-08-31 已通过本机伴随服务联网验证 GLM-5.3-Flash：自然语言请求返回节奏、公交与已有地点聚焦动作，全部通过服务端白名单；模型 Key 未写入仓库或客户端。
- 当前收到的高德 Key 在官方 Web 服务请求中返回 `USERKEY_PLAT_NOMATCH (10009)`。地点端点会以 422 返回清楚诊断，iOS 随后继续使用 Apple Maps；换成“Web 服务”Key 后无需修改客户端。
- RollingGo 未配置密钥时会返回 `disabled` 诊断，不会生成占位价格。
- 去哪儿与航班实时适配器尚未落地，iOS 端只展示明确的渠道查询入口。
