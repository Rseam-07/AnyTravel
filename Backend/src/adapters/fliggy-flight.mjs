import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { networkUserAgent } from "../network-identity.mjs";

const cityCodes = JSON.parse(readFileSync(new URL("../lib/flight-city-codes.json", import.meta.url), "utf8"));
const appKey = "12574478"; // Public H5 application identifier, not an account credential.
const api = "mtop.trip.flight.flightSearch";
const bookingPage = "https://h5.m.taobao.com/trip/flight/search/index.html";

export function flightCityCode(city) {
  const value = String(city || "").trim();
  if (/^[A-Za-z]{3}$/.test(value)) return value.toUpperCase();
  return Object.entries(cityCodes).find(([alias]) => value.includes(alias))?.[1] ?? null;
}

export class FliggyFlightAdapter {
  name = "fliggy";
  constructor({ search = searchFlightPage, now = () => new Date() } = {}) {
    this.searchPage = search;
    this.now = now;
  }

  async search(request) {
    if (!request.modes?.includes("flight")) return { options: [], diagnostics: [] };
    const from = flightCityCode(request.origin), to = flightCityCode(request.destination);
    if (!from || !to || from === to) return {
      options: [], diagnostics: [{ provider: this.name, status: "city_id_missing", detail: "当前城市组合暂无可查询的独立航线" }]
    };
    const journeys = [{ from, to, date: request.departureDate, direction: "outbound" }];
    if (request.returnDate) journeys.push({ from: to, to: from, date: request.returnDate, direction: "return" });
    const results = await Promise.allSettled(journeys.map(journey => this.searchPage(journey)));
    const options = [], diagnostics = [];
    for (let index = 0; index < journeys.length; index++) {
      const journey = journeys[index], result = results[index];
      const label = journey.direction === "return" ? "返程" : "去程";
      if (result.status === "rejected") {
        diagnostics.push({ provider: this.name, status: "failed", detail: `${label}暂未取得航班报价，可稍后重试或前往飞猪查询` });
        continue;
      }
      const link = new URL(bookingPage);
      link.search = new URLSearchParams({ depCityCode: journey.from, arrCityCode: journey.to, depDate: journey.date }).toString();
      const capturedAt = this.now().toISOString();
      const rows = result.value.offers.length ? result.value.offers : result.value.lowestPrice > 0
        ? [{ price: result.value.lowestPrice }] : [];
      for (const row of rows.slice(0, 8)) {
        options.push({
          provider: this.name, source: "飞猪公开航班页", mode: "flight", direction: journey.direction,
          serviceNumber: row.flightNumber || "当日起价",
          originName: row.departureAirport || (journey.direction === "outbound" ? request.origin : request.destination),
          destinationName: row.arrivalAirport || (journey.direction === "outbound" ? request.destination : request.origin),
          departureTime: row.departureTime ? `${journey.date}T${row.departureTime}:00+08:00` : null,
          arrivalTime: arrivalTime(journey.date, row),
          durationMinutes: row.durationMinutes ?? null,
          amountCNY: row.price, unit: "perPerson", kind: "live", capturedAt,
          bookingURL: link.href, fareName: "单程展示起价",
          availability: "舱位以飞猪结算页为准",
          note: "选定日期的航班搜索起价；税费、行李额、舱位与退改条件须在付款前核对。选中不代表已订票。"
        });
      }
      diagnostics.push({ provider: this.name, status: rows.length ? "ok" : "no_matching_quotes", detail: `${label} ${rows.length} 个报价` });
    }
    return { options, diagnostics };
  }
}

function arrivalTime(date, row) {
  if (!row.departureTime || !row.arrivalTime) return null;
  const departure = Date.parse(`${date}T${row.departureTime}:00+08:00`);
  let arrival = Date.parse(`${date}T${row.arrivalTime}:00+08:00`);
  if (row.durationMinutes > 0) {
    // Keep the provider clock but disambiguate flights landing on a later day.
    while (arrival < departure + row.durationMinutes * 60_000 - 60_000) arrival += 86_400_000;
  } else if (arrival < departure) arrival += 86_400_000;
  return Number.isFinite(arrival) ? new Date(arrival).toISOString() : null;
}

export function parseFlightPage(root) {
  if (!String(root?.ret).includes("SUCCESS") || ![true, "true", 1, "1"].includes(root?.data?.success)) return null;
  const offers = [], seen = new Set();
  for (const group of Array.isArray(root.data.items) ? root.data.items : []) {
    if (!["DIRECT", "TRANSFER", "TRANSFER_RECOMMEND", "STOP"].includes(group.itemType)) continue;
    for (const row of Array.isArray(group.itemDatas) ? group.itemDatas : []) {
      const price = Number(row.bestPrice);
      const departureTime = clock(row.depTime ?? row.depTimeShow), arrivalTime = clock(row.arrTime ?? row.arrTimeShow);
      if (!Number.isFinite(price) || price <= 0 || !departureTime || !arrivalTime) continue;
      const flightNumber = String(row.flightName ?? "");
      const identity = [flightNumber, departureTime, price, row.depAirportCode, row.arrAirportCode].join("|");
      if (seen.has(identity)) continue;
      seen.add(identity);
      const duration = Number(row.duration ?? row.flyTime ?? row.durationMinutes);
      offers.push({ price, flightNumber, departureTime, arrivalTime,
        departureAirport: airportName(row, "dep"), arrivalAirport: airportName(row, "arr"),
        durationMinutes: Number.isFinite(duration) && duration > 0 && duration <= 2880 ? duration : null });
    }
  }
  offers.sort((a, b) => a.price - b.price || a.departureTime.localeCompare(b.departureTime));
  const value = Number(root.data.lowestPrice);
  return { offers, lowestPrice: Number.isFinite(value) && value > 0 ? value : offers[0]?.price ?? null };
}

function clock(value) {
  const match = String(value || "").match(/(?:^|\s)([0-2]?\d):([0-5]\d)(?:$|\s)/);
  return match && Number(match[1]) < 24 ? `${match[1].padStart(2, "0")}:${match[2]}` : null;
}

function airportName(row, prefix) {
  const base = String(row[`${prefix}AirportName`] ?? row[`${prefix}AirportShortName`] ?? row[`${prefix}AirportShow`] ?? row[`${prefix}AirportCode`] ?? "");
  const terminal = String(row[`${prefix}AirportTerm`] ?? row[`${prefix}Terminal`] ?? "");
  return terminal && !base.includes(terminal) ? `${base} ${terminal}` : base;
}

/** Same anonymous H5 handshake as the mobile client. No account cookies are reused. */
export async function searchFlightPage({ from, to, date }, { fetchImpl = fetch, now = Date.now } = {}) {
  const data = JSON.stringify({ searchType: 1, depCityCode: from, arrCityCode: to, leaveDate: date,
    itineraryFilter: "0", leaveCabinClass: "0", useAcrossAgent: 1 });
  const cookies = new Map();
  for (let attempt = 0; attempt < 3; attempt++) {
    const token = (cookies.get("_m_h5_tk") || "").split("_")[0], timestamp = String(now());
    const sign = createHash("md5").update(`${token}&${timestamp}&${appKey}&${data}`).digest("hex");
    const url = new URL(`https://h5api.m.taobao.com/h5/${api}/1.0/`);
    url.search = new URLSearchParams({ jsv: "2.7.0", appKey, t: timestamp, sign, api, v: "1.0", type: "originaljson", dataType: "json", data }).toString();
    const response = await fetchImpl(url, { redirect: "error", signal: AbortSignal.timeout(25_000), headers: {
      "user-agent": networkUserAgent, referer: bookingPage, "accept-language": "zh-CN,zh;q=0.9",
      cookie: [...cookies].map(([key, value]) => `${key}=${value}`).join("; ")
    } });
    if (!response.ok) throw new Error("flight_source_unavailable");
    for (const line of response.headers.getSetCookie()) {
      const pair = line.split(";", 1)[0], equals = pair.indexOf("=");
      if (equals > 0 && ["_m_h5_tk", "_m_h5_tk_enc"].includes(pair.slice(0, equals))) cookies.set(pair.slice(0, equals), pair.slice(equals + 1));
    }
    const chunks = [];
    let size = 0;
    for await (const chunk of response.body ?? []) {
      size += chunk.length;
      if (size > 4 * 1024 * 1024) throw new Error("flight_response_too_large");
      chunks.push(chunk);
    }
    const root = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    const parsed = parseFlightPage(root);
    if (parsed) return parsed;
    // Verification or login requirements stop here. Retry only the normal token bootstrap.
    if (!/TOKEN_(?:EXOIRED|EXPIRED|EMPTY)|TOKEN.*过期/.test(String(root.ret))) break;
  }
  throw new Error("flight_source_unavailable");
}
