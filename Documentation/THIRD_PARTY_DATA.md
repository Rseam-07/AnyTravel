# 目的地资料来源与归属

AnyTravel 的内置目的地资料用于候选景点、公开热度排序、建议停留时长和空间编排。它是可重现的资料快照，不表示实时票价、余票、营业或预约状态。

- OpenStreetMap contributors，[ODbL 与版权说明](https://www.openstreetmap.org/copyright)。
- Wikidata contributors，[CC0 1.0](https://www.wikidata.org/wiki/Wikidata:Licensing)。
- Data by Audiala — [audiala.com](https://audiala.com/)，[CC BY 4.0 开放资料库](https://github.com/audiala/open-data)。
- `88250/city-geo`，城市中心坐标用于空间归属，[Mulan PSL v2](https://github.com/88250/city-geo)。
- 文化和旅游部[全国 A 级旅游景区数据](https://sjfw.mct.gov.cn/site/dataservice/base)、[2024 年 2 月新增 5A 名单](https://app.www.gov.cn/govdata/gov/202402/11/512030/article.html)与[2024 年 12 月新增 5A 名单](https://zwgk.mct.gov.cn/zfxxgkml/zykf/202412/t20241227_957450.html)，仅用于代表性景区身份和排序校验。
- 高德地图公开地点页仅用于少量 5A 景区的坐标交叉核对，不复制其地图瓦片、价格或受限内容。
- 雅高与希尔顿的公开网站响应仅在用户发起住宿查询时即时读取，不写入目的地知识库；雅高适配流程参考 MIT 许可的 [puneet-mehta/accor-mcp](https://github.com/puneet-mehta/accor-mcp)。价格、房态与网站契约可能变化，应用会保留抓取时间和来源链接。

Web、iOS 和 Android 共用由 `Web/scripts/assemble-knowledge.mjs` 生成的同一份城市快照。当前快照覆盖 162 个目的地，其中 141 个位于中国，共 1,234 个候选地点与 867 个去重来源。重新采集时会先经过城市归属、设施/事件排除、重复地点和代表性地标校验，再复制到两端资源目录。
