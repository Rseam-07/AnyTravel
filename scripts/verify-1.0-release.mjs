import { readFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";

const root = new URL("../", import.meta.url);
const defaults = JSON.parse(await readFile(new URL("Config/ServiceDefaults.json", root), "utf8"));
const failures = [];
let serviceURL;
try {
  serviceURL = new URL(String(process.env.ANYTRAVEL_SERVICE_URL || defaults.serviceBaseURL || ""));
  if (serviceURL.protocol !== "https:") failures.push("默认服务必须使用 HTTPS");
  if (serviceURL.username || serviceURL.password || serviceURL.search || serviceURL.hash) failures.push("默认服务地址不能包含凭据、查询参数或片段");
  if (["localhost", "127.0.0.1", "::1"].includes(serviceURL.hostname)) failures.push("默认服务不能指向用户自己的设备");
} catch {
  failures.push("Config/ServiceDefaults.json 还没有真实的公网服务地址");
}

const tracked = execFileSync("git", ["ls-files"], { cwd: root }).toString().split("\n");
for (const forbidden of ["Backend/.env", "Config/Secrets.xcconfig", "Android/secrets.properties", "Web/.env.local"]) {
  if (tracked.includes(forbidden)) failures.push(`敏感配置被 Git 跟踪：${forbidden}`);
}
const releaseXCConfig = await readFile(new URL("Config/AnyTravelRelease.xcconfig", root), "utf8");
if (/Secrets\.xcconfig|=[ \t]*\S{12,}/.test(releaseXCConfig)) failures.push("iOS Release 配置可能包含客户端凭据");
const androidConfig = await readFile(new URL("Android/app/build.gradle.kts", root), "utf8");
for (const name of ["ROLLINGGO_API_KEY", "AMAP_API_KEY", "ZAI_API_KEY"]) {
  if (!androidConfig.includes(`buildConfigField(\"String\", \"${name}\", \"\\\"\\\"\")`)) failures.push(`Android Release 没有清空 ${name}`);
}

if (serviceURL?.protocol === "https:") {
  try {
    const healthURL = new URL("health", serviceURL.href.endsWith("/") ? serviceURL : new URL(serviceURL.href + "/"));
    const response = await fetch(healthURL, { signal: AbortSignal.timeout(10_000) });
    const health = response.ok ? await response.json() : {};
    if (health.service !== "anytravel-companion" || health.status !== "ok" || health.schemaVersion !== 1) {
      failures.push("公网地址没有返回 AnyTravel schemaVersion 1 健康信息");
    }
    if (health.rollinggo !== "configured") failures.push("公网服务尚未接通默认住宿报价");
    if (health.assistant !== "configured") failures.push("公网服务尚未接通默认智能向导");
    if (health.railway12306 !== "public" || health.fliggyFlights !== "public") failures.push("公网服务的铁路或航班查询未就绪");
  } catch {
    failures.push("公网服务无法在 10 秒内完成健康检查");
  }
}

if (failures.length) {
  console.error("AnyTravel 1.0 发布门禁未通过：");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}
console.log(`AnyTravel 1.0 发布门禁通过：${serviceURL.origin}`);
