import type { TransportOption } from "./types";
import codes from "../../Backend/src/lib/flight-city-codes.json";

export interface FlightResearch {
  format: "anytravel-flight-research-v1";
  origin: string; destination: string; date: string; capturedAt: string; sourceURL: string;
  flights: { number: string; departure: string; arrival: string; price: number; from: string; to: string; nextDay?: boolean }[];
}
export function flightSearchURL(origin: string, destination: string, date: string) {
  const code = (value: string) => Object.entries(codes).find(([alias]) => value.includes(alias))?.[1];
  const from = code(origin), to = code(destination);
  if (!from || !to) return "https://m.ctrip.com/html5/flight/";
  return `https://m.ctrip.com/html5/flight/taro/first?${new URLSearchParams({ dcode: from, acode: to, ddate: date })}`;
}

/** A dated user-reviewed web search is a reference, never a live API or booking. */
export function importFlightResearch(value: unknown, expected: { origin: string; destination: string; date: string; direction: "outbound" | "return" }, now = new Date()): TransportOption[] {
  const data = value as FlightResearch;
  const city = (s: string) => String(s).trim().replace(/市$/, "");
  if (data?.format !== "anytravel-flight-research-v1" || city(data.origin) !== city(expected.origin) || city(data.destination) !== city(expected.destination) || data.date !== expected.date) throw new Error("查询结果的城市或日期与当前这一程不同，请核对后再导入。");
  const captured = Date.parse(data.capturedAt);
  if (!Number.isFinite(captured) || captured > now.getTime() + 60_000) throw new Error("查询时间无效，请填写实际查询时间。");
  let source: URL;
  try { source = new URL(data.sourceURL); } catch { throw new Error("请填写实际查询网页的完整链接。"); }
  if (source.protocol !== "https:" || source.username || source.password) throw new Error("来源必须是完整的 HTTPS 网页链接。");
  if (!Array.isArray(data.flights) || !data.flights.length || data.flights.length > 50) throw new Error("一次可导入 1—50 个航班。");
  const seen = new Set<string>();
  return data.flights.map(row => {
    if (!/^[A-Z0-9]{2}\d{2,4}$/i.test(row.number || "") || !/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(row.departure || "") || !/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(row.arrival || "") || !Number.isFinite(row.price) || row.price <= 0 || row.price > 100_000) throw new Error("航班号、时刻或价格有误；每行应为航班号、起飞时间、到达时间、成人票价、出发机场、到达机场。");
    const departureTime = new Date(`${data.date}T${row.departure}:00+08:00`);
    const arrivalTime = new Date(Date.parse(`${data.date}T${row.arrival}:00+08:00`) + (row.nextDay ? 86_400_000 : 0));
    if (!Number.isFinite(departureTime.getTime()) || arrivalTime <= departureTime) throw new Error("到达早于出发。跨日航班请在到达时刻后标注 +1。");
    const id = `web-research-${expected.direction}-${data.date}-${row.number.toUpperCase()}-${row.departure}`;
    if (seen.has(id)) throw new Error("同一航班重复出现，请保留一条核对后的记录。"); seen.add(id);
    return { id, mode: "flight", direction: expected.direction, title: `${row.number.toUpperCase()} · ${data.origin}→${data.destination}`, originName: `${data.origin} ${String(row.from || "机场待核对").slice(0,80)}`, destinationName: `${data.destination} ${String(row.to || "机场待核对").slice(0,80)}`, departureTime, arrivalTime, durationMinutes: (arrivalTime.getTime() - departureTime.getTime()) / 60_000,
      quotes: [{ provider: "web-research", providerTitle: "网页查询记录", kind: "indicative", unit: "perPerson", amountCNY: row.price, capturedAt: data.capturedAt, bookingURL: source.href, sourceLabel: source.hostname, isStale: now.getTime() - captured > 6 * 3600_000, note: "用户核对的网页查询记录，非实时库存；价格可能未含机建燃油费，儿童票、行李及退改请在原网站复核。" }], availability: "网页查询记录 · 库存待复核", recommendationReasons: [], isRecommended: false };
  });
}

export function researchFromRows(text: string, metadata: Omit<FlightResearch, "format" | "flights">): FlightResearch {
  return { ...metadata, format: "anytravel-flight-research-v1", flights: text.trim().split(/\n+/).filter(Boolean).map(line => {
    const [number, departure, arrival = "", price, from, to] = line.split(/[|｜\t]/).map(s => s.trim());
    return { number, departure, arrival: arrival.replace(/\s*\+1(?:天)?$/, ""), nextDay: /\+1(?:天)?$/.test(arrival), price: Number(price?.replace(/[¥￥,]/g, "")), from, to };
  }) };
}
