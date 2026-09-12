# AnyTravel 公共服务部署

## 当前部署

- 网页：[GitHub Pages](https://rseam-07.github.io/AnyTravel/)。提交 main 后由 Actions 构建并发布。
- 接口：[Cloudflare Worker](https://anytravel-api.ny-ravel.workers.dev/health)。配置在 Backend/wrangler.jsonc。
- 三端默认地址保存在 Config/ServiceDefaults.json，只包含公开 HTTPS 地址。
- 供应商凭据保存在 Cloudflare Secrets。公开仓库、Pages 构建、分享链接均不包含供应商密钥。原有私有后端仓库继续保持私有。

采用 Workers Free 与 SQLite Durable Objects，当前未购买付费套餐。Workers AI 使用 @cf/qwen/qwen3-30b-a3b-fp8，通过绑定调用，无需再配置模型 Key。免费额度耗尽会返回错误，向导会回退到明确标注的本地规则。限额与价格以 [Workers](https://developers.cloudflare.com/workers/platform/pricing/)、[Workers AI](https://developers.cloudflare.com/workers-ai/platform/pricing/) 和 [Durable Objects](https://developers.cloudflare.com/durable-objects/platform/pricing/) 官方说明为准。

## 更新 Cloudflare 后端

在仓库根目录运行（Node 22）：

```sh
npm ci --prefix Backend
npm test --prefix Backend
Backend/node_modules/.bin/wrangler login
Backend/node_modules/.bin/wrangler deploy --config Backend/wrangler.jsonc
```

登录由账户拥有者在浏览器完成；不要把本地 OAuth token 放进 GitHub。Worker 更新目前由 Wrangler 发布，前端更新自动走 GitHub Actions。新增后端密钥用 wrangler secret put，以交互方式输入，不能作为命令参数或写进 wrangler.jsonc。

ROLLINGGO_API_KEY 用于住宿目录。AMAP_API_KEY 必须是 Web 服务类型；不兼容或不可用时回退到有来源标注的 OSM。Cloudflare 版本不运行需要持久浏览器登录会话的携程/同程采集通道，它们显示 disabled。其他来源失败不会丢弃已经取得的结果。

服务允许 https://rseam-07.github.io 的 CORS，接口按 IP 每分钟 30 次限流。健康检查的 configured/public 仅表示接入方式，不能作为当次查价成功的证据。

## 手册同步

SQLite Durable Object 持久保存共享副本；每本最多 32 MB，当前最多 100 本。票据随备份一起保存。分享码包含高熵访问令牌，数据库只存令牌摘要；没有令牌不能读写。更新以版本号进行原子检查，同时编辑返回 409，避免静默覆盖。分享码持有者可以读取和修改整本手册。

本机 IndexedDB 与云端副本独立，上传和拉取均由用户手动触发。断开本机连接不会删除云端数据或撤销旧分享码。单个 Node 部署则通过 HANDBOOK_SYNC_DIR 使用持久目录，只允许一个进程拥有该目录。

## 验证与回滚

```sh
ANYTRAVEL_SERVICE_URL=https://anytravel-api.ny-ravel.workers.dev node Backend/scripts/smoke-cloudflare.mjs
ANYTRAVEL_SERVICE_URL=https://anytravel-api.ny-ravel.workers.dev node Backend/scripts/smoke-cloudflare.mjs --live
```

基础烟测创建一份不含个人信息的测试手册，验证跨域、权限、分块存储和并发冲突。--live 还严格要求酒店、铁路、航班均返回数字报价且向导为云端模式；来源限制时该检查应失败，不能掩盖为通过。每次 smoke 会占用一个共享副本名额。

线上功能与限制见 [本次发布记录](WEB_RELEASE_2026-09-12.md)。跨端 1.0 的脚本只检查基础配置和服务身份，不能替代公开网页、真实报价和设备验收。

回滚使用 Cloudflare 控制台的 Worker 版本记录；前端回滚对应 Git 提交后重新运行 Pages 工作流。保留现有 Durable Object migration 历史，不能通过删除配置重建用户数据。

## 可选 Node/Docker 部署

根目录 Dockerfile 保留 Node 22 同源网页与接口部署方式。需要浏览器会话的可选通道必须在有持久磁盘和 Chromium 的平台运行。生产凭据注入环境变量；.dockerignore 排除本机凭据、会话和构建缓存。
