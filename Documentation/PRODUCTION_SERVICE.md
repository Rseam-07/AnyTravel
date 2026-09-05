# AnyTravel 1.0 公共服务部署

1.0 的网页、iOS 和 Android 使用同一个公开 HTTPS 服务。Web 静态资源也由该服务提供，因此网页不需要跨域配置；移动端只保存公开服务地址。酒店渠道、地图 Web 服务和智能向导的凭据只存在于服务端环境变量中。

## 部署镜像

仓库根目录的 `Dockerfile` 分两阶段构建：先生成 Web 生产资源，再生成只包含 Backend 运行依赖和 Web `dist` 的 Node 22 镜像。`.dockerignore` 会排除所有本机凭据、登录会话、安装包和构建缓存。默认监听 `0.0.0.0:8787`，平台也可以通过 `PORT` 覆盖端口。

生产平台至少需要提供：

- `ROLLINGGO_API_KEY`：默认住宿实时目录与价格。
- `ZAI_API_KEY` 或 `DEEPSEEK_API_KEY`：默认自然语言向导。
- `AMAP_API_KEY`：高德地点补充；没有它时仍有内置资料与 OSM。
- `TRUST_PROXY=true`：仅当托管平台会清理并重写 `X-Forwarded-For` 时设置，用于按真实访问者限流。

携程、同程等需要持久浏览器会话的来源还需要持久磁盘和浏览器运行环境。它们不是公共服务首次上线的硬依赖；RollingGo、12306、飞猪公开航班、品牌官网与去哪儿门票构成默认查询链路。平台应设置实例数量、月度预算、并发和出站流量告警，不能用一个无限额供应商 Key 直接暴露服务。

部署后先检查：

```sh
curl https://你的域名/health
curl https://你的域名/
```

健康响应必须包含 `service: anytravel-companion`、`status: ok` 和 `schemaVersion: 1`。`configured` 只表示服务端接入了凭据，实际有房、有票仍以每次查询结果为准。

## 写入三端默认地址

把确认可用的根地址写入 `Config/ServiceDefaults.json` 的 `serviceBaseURL`，例如 `https://travel.example.com/`。不要在这里写 token、查询参数或账号信息。Web 构建会把它作为兜底地址；同源部署时 Web 自动使用当前站点。iOS 和 Android Release 从同一文件读取地址。

提交发布前运行：

```sh
node scripts/verify-1.0-release.mjs
```

门禁会拒绝空地址、HTTP、localhost、被 Git 跟踪的私密配置、客户端 Release 凭据、错误服务身份，以及未接通默认住宿、向导、铁路或航班的公网节点。当前没有真实公网地址时，门禁失败是正确结果，不能为了生成安装包跳过。

## 回滚

每次服务发布保留上一个镜像摘要。先在临时域名完成健康检查和一条不含个人信息的苏州查价烟测，再切换正式流量。异常时回滚服务镜像，不需要让用户重新安装客户端；如服务地址本身失效，则发布仅修改 `ServiceDefaults.json` 的补丁版本。
