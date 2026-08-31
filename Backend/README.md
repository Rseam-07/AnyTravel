# AnyTravel 报价节点

这个伴随服务把 App 的候选酒店统一交给多个价格源，并返回同一种 JSON。密钥、浏览器 Cookie 和抓取逻辑留在自建节点，iOS App 不内置供应商密钥。

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

- `ROLLINGGO_API_KEY`：优先实时源。节点调用 RollingGo 的 `searchHotels` MCP 工具，并把返回的酒店名、展示价和预订链接归一化。
- `CTRIP_SCRAPER_ENABLED=true`：使用持久化 Chromium 会话读取携程搜索结果。先运行 `npm run login:ctrip`，由用户在携程页面自行登录；Cookie 只保存在 `Backend/.data/ctrip-profile`，该目录不会提交到 Git。
- 携程解析只接受能与 App 候选酒店名称匹配的结果，并保存抓取时间。列表中的“起”价会明确标注，房型、早餐、税费和退改仍以结算页为准。
- `/v1/quotes/transport` 会通过铁路 12306 的公开查询页面读取可购车次、发到时间、余票和展示票价。它只查询，不提交订单；购买链接始终指向铁路 12306。结果默认缓存 5 分钟。

住宿接口是 `POST /v1/quotes/accommodations`，交通接口是 `POST /v1/quotes/transport`。两者都会返回 `diagnostics`，某个渠道失败时其他渠道仍能继续返回。

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
      "name":"苏州园林附近酒店",
      "latitude":31.32,
      "longitude":120.62
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

返回的铁路列表保留适配器排序：主站对主站优先，其次是高铁/动车、白天班次和较短耗时。App 不会再按最低价重新打乱车站优先级。

单元测试：`npm test`。服务默认缓存相同请求 10 分钟并限制每个 IP 每分钟 30 次请求，避免用户滚动卡片时重复抓取。

## 当前验证边界

- 2026-08-31 已联网验证“上海→苏州”：节点返回上海站至苏州站车次、发到时间、余票与二等座价格。
- 携程匿名搜索当日会进入登录页；因此实时采集必须先运行 `npm run login:ctrip`，不能把匿名失败写成实时成功。
- RollingGo 未配置密钥时会返回 `disabled` 诊断，不会生成占位价格。
- 去哪儿与航班实时适配器尚未落地，iOS 端只展示明确的渠道查询入口。
