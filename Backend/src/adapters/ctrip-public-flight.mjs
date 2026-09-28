import { resolveCtripAirportCode } from "./ctrip-flight.mjs";
import { networkUserAgent } from "../network-identity.mjs";

/** Public, server-rendered search results, also visible in the normal mobile site.
 * No login session, private search endpoint, executable page code or challenge solving.
 * Every result must echo the requested city pair AND date before we accept it.
 */
export class CtripPublicFlightAdapter {
  name = "ctrip-public-flight";
  constructor({ fetchImpl, now = () => new Date() } = {}) {
    this.fetchImpl = fetchImpl || globalThis.fetch.bind(globalThis);
    this.now = now;
  }

  async search(request) {
    if (!request.modes?.includes("flight")) return { options: [], diagnostics: [] };
    const from = resolveCtripAirportCode(request.origin), to = resolveCtripAirportCode(request.destination);
    if (!from || !to || from === to) return { options: [], diagnostics: [{ provider: this.name, status: "city_id_missing", detail: "这组城市暂未匹配到独立航线，可在携程选择附近机场" }] };
    const journeys = [{ from, to, date: request.departureDate, direction: "outbound" }];
    if (request.returnDate) journeys.push({ from: to, to: from, date: request.returnDate, direction: "return" });
    const results = await Promise.allSettled(journeys.map(journey => this.searchJourney(journey)));
    const options = [], diagnostics = [];
    for (let i = 0; i < results.length; i++) {
      const result = results[i], label = journeys[i].direction === "outbound" ? "去程" : "返程";
      if (result.status === "fulfilled") {
        options.push(...result.value);
        diagnostics.push({ provider: this.name, status: result.value.length ? "ok" : "no_matching_quotes", detail: `${label} ${result.value.length} 班 · 携程公开搜索页 · 成人票面价，税费另核`, capturedAt: this.now().toISOString() });
      } else {
        const code = result.reason?.message;
        diagnostics.push({ provider: this.name, status: code === "verification_required" ? code : "failed", detail: `${label}${code === "date_mismatch" ? "页面日期与行程不一致，未采用其报价" : code === "verification_required" ? "需要在携程完成验证后查看" : "公开搜索页暂未返回可核验的报价，请打开携程继续查询"}` });
      }
    }
    return { options, diagnostics };
  }

  async searchJourney(journey) {
    const today = this.now().toLocaleDateString("en-CA", { timeZone: "Asia/Shanghai" });
    const offset = Math.round((Date.parse(journey.date) - Date.parse(today)) / 86_400_000);
    if (!Number.isInteger(offset) || offset < 0 || offset > 365) return [];
    const url = new URL(`https://m.ctrip.com/html5/flight/${journey.from}-${journey.to}-day-${offset}.html`);
    const response = await this.fetchImpl(url, { redirect: "error", signal: AbortSignal.timeout(18_000), headers: { accept: "text/html", "accept-language": "zh-CN,zh;q=0.9", "user-agent": networkUserAgent } });
    if (!response.ok) throw new Error("source_unavailable");
    const reader = response.body.getReader();
    const chunks = []; let length = 0;
    try {
      while (true) {
        const { done, value } = await reader.read(); if (done) break;
        length += value.length;
        if (length > 4 * 1024 * 1024) throw new Error("response_too_large");
        chunks.push(value);
      }
    } finally { await reader.cancel().catch(() => {}); }
    const html = Buffer.concat(chunks).toString("utf8");
    const marker = "window.__INITIAL_STATE__=";
    const start = html.indexOf(marker);
    if (start < 0) throw new Error(/安全验证|访问过于频繁|请完成验证/.test(html) ? "verification_required" : "source_unavailable");
    const end = html.indexOf(";(function()", start);
    if (end < 0) throw new Error("source_unavailable");
    const root = JSON.parse(html.slice(start + marker.length, end));
    return parseCtripPublicFlights(root.listData, journey, this.now().toISOString());
  }
}

const cityCode = code => ({ XIY: "SIA", PEK: "BJS", PKX: "BJS", TFU: "CTU", PVG: "SHA" })[String(code).toUpperCase()] || String(code).toUpperCase();
const dateTime = value => /^\d{4}-\d{2}-\d{2} [0-2]\d:[0-5]\d:[0-5]\d$/.test(value || "") ? `${value.replace(" ", "T")}+08:00` : null;

export function parseCtripPublicFlights(data, journey, capturedAt) {
  if (data?.ddate !== journey.date) throw new Error("date_mismatch");
  if (cityCode(data.dcode) !== cityCode(journey.from) || cityCode(data.acode) !== cityCode(journey.to)) throw new Error("route_mismatch");
  const link = new URL("https://m.ctrip.com/html5/flight/taro/first");
  link.search = new URLSearchParams({ dcode: journey.from, acode: journey.to, ddate: journey.date }).toString();
  const seen = new Set();
  return (Array.isArray(data.flights) ? data.flights : []).flatMap(row => {
    const legs = row.flightItem?.flights, policy = row.policy;
    if (!Array.isArray(legs) || !legs.length || policy?.departDate !== journey.date || policy.currency !== "CNY") return [];
    const departureTime = dateTime(legs[0].dtime), arrivalTime = dateTime(legs.at(-1).atime);
    const amount = Number(policy.price), duration = (Date.parse(arrivalTime) - Date.parse(departureTime)) / 60_000;
    const serviceNumber = legs.map(leg => leg.flightNo).filter(Boolean).join(" / ");
    if (!departureTime?.startsWith(journey.date) || !(duration > 0 && duration <= 2880) || !(amount > 0 && amount < 100_000) || !serviceNumber) return [];
    const identity = serviceNumber + departureTime;
    if (seen.has(identity)) return []; seen.add(identity);
    const transfers = legs.slice(0, -1).map(leg => leg.aport?.cityName || leg.aport?.name).filter(Boolean);
    const stops = legs.flatMap(leg => Array.isArray(leg.stops) ? leg.stops : []);
    const stopLabel = transfers.length ? `经 ${transfers.join("、")}中转` : stops.length ? "有经停" : "直飞";
    return [{ provider: "ctrip-public-flight", source: "携程公开航班搜索页", mode: "flight", direction: journey.direction,
      serviceNumber, originName: `${legs[0].dport?.cityName || data.dcityName} ${row.dport || legs[0].dport?.name || ""}`.trim(),
      destinationName: `${legs.at(-1).aport?.cityName || data.acityName} ${row.aport || legs.at(-1).aport?.name || ""}`.trim(),
      departureTime, arrivalTime, durationMinutes: duration, amountCNY: amount, unit: "perPerson", kind: "live", capturedAt,
      bookingURL: link.href, taxesIncluded: policy.isContainsTax === true,
      fareName: `成人单程${policy.isContainsTax === true ? "含税" : "未含税"}起价`, availability: `${stopLabel} · 库存以购买页为准`,
      note: `按所选日期读取公开搜索结果；${policy.isContainsTax === true ? "页面标注含税" : "页面标注未含税，机建燃油费另计"}。儿童票、行李额、退改及多人优惠请在携程复核。选中不代表购票。`
    }];
  }).sort((a, b) => a.amountCNY - b.amountCNY || a.departureTime.localeCompare(b.departureTime)).slice(0, 10);
}
