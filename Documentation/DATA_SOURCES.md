# AnyTravel 地图数据来源

更新日期：2026-08-31

## Apple Maps / MapKit

- 用途：iOS 主地图、目的地解析、景点与住宿候选、路线和预计时间。
- 输出：`CLLocationCoordinate2D` 与 `MKRoute`，直接用于 MapKit 呈现。
- 失败处理：地点为空、路线失败与权限问题必须在界面显示；不能把估算值写成实时结果。

## 高德 Web 服务

- 官方端点：`https://restapi.amap.com/v3/place/text`，由伴随服务的 `POST /v1/places/search` 代理。
- 凭据：只读 `Backend/.env` 中的 `AMAP_API_KEY`。必须使用高德控制台的“Web 服务”Key；iOS SDK Key 不兼容 REST 请求。
- 坐标：高德返回 GCJ-02。伴随服务保留原始坐标与坐标系字段，并输出三次迭代近似反算的 WGS84 坐标；数据对象会同时标注 `sourceCRS` 和 `outputCRS`。
- 质量门槛：在正式合并到 iOS 主地图前，至少用三个已知地标与 MapKit 搜索结果交叉核对。当前提供的 Key 于 2026-08-31 返回 `USERKEY_PLAT_NOMATCH (10009)`，因此本版不会把高德结果冒充为已接通数据。

## 可追溯性约定

所有外部地点响应必须保留来源、抓取时间和坐标语义。任何价格、余票和地点源都可单独失败，其他来源仍可继续返回；未知坐标系、缺失名称或越界经纬度直接丢弃并进入诊断信息。
