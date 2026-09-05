# AnyTravel 伴随服务

这个伴随服务把 App 的候选酒店统一交给多个价格源，也负责托管自然语言行程控制器。浏览器 Cookie 与需要商家身份的凭据留在自建节点。iOS 与 Android 0.8.2 的发布构建另可从 Git 忽略的本机配置注入 RollingGo、高德与智谱默认 Key，让用户不运行节点也能使用基础价格与智能向导；公开仓库不保存这些明文值。

## 启动

```sh
cd Backend
npm install
npx playwright install chromium
cp .env.example .env
set -a; source .env; set +a
npm start
```

健康检查：`curl http://127.0.0.1:8787/health`。除了服务本身、托管智能向导与高德地点之外，还会逐项报告 `ctripSession`、`ctripFlights`、`tongchengSession`、`elongOpenAPI`、`oneBoundCtrip`、`accorOfficial` 与 `hiltonOfficial` 的状态，方便确认哪些通道真的接上了。在 AnyTravel 的“旅途偏好与价格渠道”中填写这个地址；真机需填写电脑在同一局域网内的 IP，例如 `http://192.168.1.10:8787/`。
服务默认只监听本机。需要让同一局域网中的 iPhone 访问时，把 `.env` 中的 `HOST` 改为 `0.0.0.0`，并只在可信网络中运行。

## 数据源

- `ROLLINGGO_API_KEY`：优先实时源。`/v1/accommodations/search` 会先查目的地城市，再以最多三个行程景点为锚点并行补充目录；每次遵守 `searchHotels` 的 `size <= 20`，去重后最多返回 40 家。随后 `/v1/quotes/accommodations` 可对 App 候选逐店查询最多 12 家，只接收名称强匹配结果。`lowestPrice` 直接按每晚最低价处理，只有字段或文案明确为总价时才按晚数换算。
- 雅高集团官网是无需合作方凭据的品牌直连补充源：节点读取 `all.accor.com` 当前公开目录，并以所选入住日期、离店日期和人数查询公开房价响应；最多核对 10 家，保留每晚价、总价、房型、餐食、取消政策、抓取时间和官网购买链接。网页契约变化时只报告该来源失败，不影响 RollingGo。
- 希尔顿中国官网公开目录会补充品牌酒店、地址、坐标、卖点和官网深链。目录 `minPrice` 只标“官网公开起价/参考价”，因为它不能证明属于选择日期；官网深链会带入日期和人数供用户复核。
- `CTRIP_SCRAPER_ENABLED=true`：使用持久化 Chromium 会话读取携程搜索结果。先运行 `npm run login:ctrip`，由用户在携程页面自行登录；Cookie 只保存在 `Backend/.data/ctrip-profile`，该目录不会提交到 Git。
- 携程先通过公开酒店联想端点把每个 App 候选解析为酒店 ID，再打开带真实日期的目标酒店列表；只接受名称强匹配的数字价格，并保存抓取时间。列表中的“起”价会明确标注，房型、早餐、税费和退改仍以结算页为准。
- `CTRIP_FLIGHT_SCRAPER_ENABLED=true`（缺省时回退到 `CTRIP_SCRAPER_ENABLED`）：用同一个持久化会话读取携程航班列表页，把城市映射为机场三字码后分别查询去程与返程的展示航班卡。同样只读查询、只接受数字展示价，购买回到携程页面。当前配置下默认关闭，未启用时健康检查显示 `disabled`。
- `TONGCHENG_SCRAPER_ENABLED=true`：使用同样的本地会话读取同程/艺龙移动酒店列表。先运行 `npm run login:tongcheng`；节点通过公开城市选择页取得城市编码，再按入住/离店日期打开公开列表。只在酒店名强匹配且页面出现数字价格时返回实时价。
- 同程页面若显示“登录查看低价”，节点返回 `login_required`；若平台要求安全验证或提示账号异常，则返回 `verification_required`。这些状态不会被改写成空的“实时价”。
- `ELONG_USER`、`ELONG_APP_KEY` 与 `ELONG_SECRET_KEY`：艺龙开放平台酒店通道。节点依次调用 `hotel.static.city`、`hotel.static.list`、`hotel.static.info` 和 `hotel.detail`，把城市内容 ID、有效酒店、酒店详情与指定入住/离店日期的 `LowRate` 合并成同程旅行报价卡。接口使用官方 `md5(timestamp + md5(data + appkey) + secretKey)` 签名，生产环境还需要把服务端公网 IP 加入艺龙白名单；未配置凭据时健康检查明确显示 `disabled`。
- 艺龙开放平台动态搜索按中国大陆每次最多 10 个酒店 ID 分批，并只把 `RMB/CNY` 的数字 `LowRate` 标记为实时每晚价。没有可售价格的酒店仍可补充目录，但不会伪装成实时价。
- `ONEBOUND_API_KEY` 与 `ONEBOUND_API_SECRET`：万邦（OneBound）携程目录通道 `item_search_hotel`，只用于补充携程酒店目录与参考价。该接口不保证按指定入住日期报价，因此只有明确数字且口径一致时才标为参考价，绝不冒充实时价；未配置凭据时健康检查显示 `disabled`。
- Playwright 自带浏览器不可用时，可用 `PLAYWRIGHT_CHANNEL=chrome` 或 `PLAYWRIGHT_EXECUTABLE_PATH=/绝对路径` 指向本机浏览器；这只是选择浏览器程序，不关闭或规避平台验证。
- `/v1/quotes/transport` 会通过铁路 12306 的公开查询页面分别读取去程与返程的可购车次、发到时间、余票和展示票价。两边并行查询，单边失败不会遮住另一边；它只查询，不提交订单，购买链接始终指向铁路 12306。结果默认缓存 5 分钟。
- `/v1/quotes/tickets` 会按 App 已选的主要游览点查询去哪儿门票公开列表，只回填名称强匹配的当前展示起价、抓取时间与详情购买页。付费街区、道路、书店、商场、公园、开放湖区、博物馆、广场、普通地标、餐饮与夜间活动会被拒绝，避免把导览、餐食或观景套餐误写成入场费。公开列表不锁定指定日期、票种或库存，因此返回说明会要求在购买页复核。
- `DEEPSEEK_API_KEY`、`DEEPSEEK_BASE_URL` 与 `DEEPSEEK_MODEL`：为 `POST /v1/assistant/interpret` 提供首选智能向导；默认模型是 `deepseek-chat`。未配置 DeepSeek 时可用 `ZAI_API_KEY`、`ZAI_BASE_URL` 与 `ZAI_MODEL` 作为兼容回退。两条路径都只允许返回白名单内的路线动作，服务端会再次校验地点名、预算和枚举值。
- `AMAP_API_KEY`：供高德 Web 服务 v5 地点适配器使用。它必须是在高德控制台创建的“Web 服务”Key；节点请求 `show_fields=business` 以取得可用的营业时间、评分与消费字段。iOS SDK Key 会返回平台不匹配，不能混用。

住宿目录接口是 `POST /v1/accommodations/search`，逐店报价接口是 `POST /v1/quotes/accommodations`，交通接口是 `POST /v1/quotes/transport`，景点门票接口是 `POST /v1/quotes/tickets`。接口都会返回 `diagnostics`，某个渠道失败时其他数据仍能继续返回。

地点补充接口是 `POST /v1/places/search`。高德原始 GCJ-02 坐标与反算后的 WGS84 坐标语义都会随响应保留；只有 Web 服务 Key 验证通过后，客户端才应把这些候选合并进主地图。

住宿目录请求示例：

```sh
curl -sS http://127.0.0.1:8787/v1/accommodations/search \
  -H 'content-type: application/json' \
  --data '{
    "destination":"苏州市",
    "checkIn":"2026-09-10",
    "checkOut":"2026-09-12",
    "adults":2,
    "rooms":1,
    "size":20,
    "anchors":["拙政园","金鸡湖","虎丘山"]
  }'
```

逐店报价请求示例：

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

门票请求示例：

```sh
curl -sS http://127.0.0.1:8787/v1/quotes/tickets \
  -H 'content-type: application/json' \
  --data '{
    "destination":"苏州",
    "visitDate":"2026-09-10",
    "attractions":[{
      "id":"40C8AD84-D6EE-4A9B-A632-F06B39809451",
      "name":"拙政园",
      "address":"苏州市姑苏区东北街178号"
    }]
  }'
```

单元测试：`npm test`。服务默认缓存相同请求 10 分钟并限制每个 IP 每分钟 30 次请求，避免用户滚动卡片时重复抓取。

## 当前验证边界

- 2026-08-31 已联网验证“上海⇄苏州”：去程与返程各返回 8 个可购车次，两边均取得发到时间、余票与席别价格。
- 2026-09-01 已联网验证携程公开联想接口能把“苏州吴宫泛太平洋酒店”解析为酒店 ID `346290`，目标列表只返回这一家并保留入住/离店日期；当前持久会话显示“登录以查看会员价”，因此返回 `login_required`。实时采集前需运行 `npm run login:ctrip`，不能把未登录页面写成实时成功。
- 2026-09-01 已用正常 Chrome 验证同程/艺龙公开流程：选择“苏州”得到城市编码 `1102`，请求日期 `2026-09-15` 至 `2026-09-16` 被正确带入列表。新会话随后触发平台安全验证，因此本次没有数字报价；节点返回 `verification_required`，等待用户在持久会话中完成验证。
- 2026-09-01 已联网验证去哪儿门票公开列表：苏州返回 15 个景点，拙政园、狮子林和虎丘山当前展示起价分别为 `¥80`、`¥38.2`、`¥70`，三处均取得详情购买页。它们不是计划日期锁价，App 会明确要求复核票种和库存。
- 2026-09-01 已使用私有环境变量联网验证 RollingGo 目录：以苏州城市和拙政园、金鸡湖、虎丘山三个景点锚点并行查询，4 个请求全部成功，合并去重后返回 18 家带价格酒店。2026-09-03 又从 iOS 原生直连以天津指定入住/离店日期取得实时数字价格。价格会随日期和库存变化，因此不把测试数字写成长期报价；明文密钥未写入仓库，但发布 IPA 的默认通道配置可被客户端提取，需按可轮换凭据管理。
- 2026-08-31 已通过本机伴随服务联网验证 GLM-5.3-Flash：自然语言请求返回节奏、公交与已有地点聚焦动作，全部通过服务端白名单；模型 Key 未写入仓库或客户端。
- 当前收到的高德 Key 在官方 Web 服务请求中返回 `USERKEY_PLAT_NOMATCH (10009)`。地点端点会以 422 返回清楚诊断，iOS 随后继续使用 Apple Maps；换成“Web 服务”Key 后无需修改客户端。
- RollingGo 未配置密钥时会返回 `disabled` 诊断，不会生成占位价格。
- 去哪儿景点门票适配器已经落地；去哪儿酒店与航班仍只提供明确的渠道查询入口。同程酒店适配器已落地，但是否返回数字价格取决于本地登录会话和平台验证状态。
- 2026-09-05 后端单元测试为 53/53；RollingGo、雅高集团官网和希尔顿官网已经并入住宿聚合。雅高联网用例以所选日期取得大于零的每晚价、总价与官网购买入口；希尔顿目录价会明确标成参考价。艺龙开放平台、万邦携程目录与携程航班适配器已有解析级覆盖，但本机未配置 `ELONG_*`、`ONEBOUND_*` 凭据，也未运行携程航班采集，因此这些通道还没有联网数字报价验收；健康检查会如实显示 `disabled`。
- 2026-09-03 iOS 的应用内直连通道包括 12306、RollingGo、默认飞猪 H5 航班价，以及用户明确保存会话后的去哪儿航班价；它们可独立于本节点工作。本节点仍是携程、同程、艺龙、万邦与托管智能向导的承载方。
