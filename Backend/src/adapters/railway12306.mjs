import {
  availabilitySummary,
  findStation,
  parseStationNames,
  parseTicketPrice,
  parseTrainRow
} from "../lib/railway-parser.mjs";

const stationURL = "https://kyfw.12306.cn/otn/resources/js/framework/station_name.js";
const baseURL = "https://kyfw.12306.cn/otn";
const browserHeaders = {
  "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/140 Safari/537.36",
  "accept-language": "zh-CN,zh;q=0.9",
  referer: `${baseURL}/leftTicket/init`
};

let stationCache;

export class Railway12306Adapter {
  async search(request) {
    if (!request.modes?.includes("train")) return { options: [], diagnostics: [] };
    try {
      const stations = await loadStations();
      const from = findStation(stations, request.origin);
      const to = findStation(stations, request.destination);
      if (!from || !to) {
        return {
          options: [],
          diagnostics: [{ provider: "12306", status: "station_not_found", detail: `${request.origin} → ${request.destination}` }]
        };
      }

      const journeys = buildJourneyQueries(request, from, to);
      const settled = await Promise.allSettled(journeys.map(searchJourney));
      const options = [];
      const diagnostics = [];
      for (let index = 0; index < settled.length; index += 1) {
        const result = settled[index];
        const journey = journeys[index];
        const label = journey.direction === "return" ? "返程" : "去程";
        if (result.status === "fulfilled") {
          options.push(...result.value);
          diagnostics.push({ provider: "12306", status: "ok", detail: `${label} ${result.value.length} 列` });
        } else {
          diagnostics.push({
            provider: "12306",
            status: "failed",
            detail: `${label}查询失败：${result.reason?.message || String(result.reason)}`
          });
        }
      }
      return { options, diagnostics };
    } catch (error) {
      return {
        options: [],
        diagnostics: [{ provider: "12306", status: "failed", detail: error.message }]
      };
    }
  }
}

export function buildJourneyQueries(request, from, to) {
  const journeys = [{
    direction: "outbound",
    date: request.departureDate,
    from,
    to
  }];
  if (request.returnDate) {
    journeys.push({
      direction: "return",
      date: request.returnDate,
      from: to,
      to: from
    });
  }
  return journeys;
}

async function searchJourney(journey) {
  const cookies = await createAnonymousSession(journey.from, journey.to, journey.date);
  const query = new URL(`${baseURL}/leftTicket/query`);
  query.searchParams.set("leftTicketDTO.train_date", journey.date);
  query.searchParams.set("leftTicketDTO.from_station", journey.from.code);
  query.searchParams.set("leftTicketDTO.to_station", journey.to.code);
  query.searchParams.set("purpose_codes", "ADULT");
  const payload = await fetchJSON(query, cookies);
  const stationMap = payload?.data?.map || {};
  const trains = (payload?.data?.result || [])
    .map((row) => parseTrainRow(row, stationMap))
    .filter((train) => train?.canBuy)
    .sort((a, b) => compareTrains(a, b, journey.from, journey.to))
    .slice(0, Math.min(Number(process.env.RAILWAY_RESULT_LIMIT || 8), 12));

  return Promise.all(trains.map(async (train) => {
    const priceURL = new URL(`${baseURL}/leftTicket/queryTicketPrice`);
    priceURL.searchParams.set("train_no", train.trainNo);
    priceURL.searchParams.set("from_station_no", train.fromStationNo);
    priceURL.searchParams.set("to_station_no", train.toStationNo);
    priceURL.searchParams.set("seat_types", train.seatTypes);
    priceURL.searchParams.set("train_date", journey.date);
    try {
      const price = parseTicketPrice(await fetchJSON(priceURL, cookies));
      return toOption(train, price, journey);
    } catch {
      return toOption(train, null, journey);
    }
  }));
}

async function loadStations() {
  if (stationCache?.expiresAt > Date.now()) return stationCache.value;
  const response = await fetch(stationURL, { headers: browserHeaders, signal: AbortSignal.timeout(12_000) });
  if (!response.ok) throw new Error(`station_list_http_${response.status}`);
  const value = parseStationNames(await response.text());
  stationCache = { value, expiresAt: Date.now() + 24 * 60 * 60 * 1000 };
  return value;
}

async function createAnonymousSession(from, to, date) {
  const initURL = new URL(`${baseURL}/leftTicket/init`);
  initURL.searchParams.set("linktypeid", "dc");
  initURL.searchParams.set("fs", `${from.name},${from.code}`);
  initURL.searchParams.set("ts", `${to.name},${to.code}`);
  initURL.searchParams.set("date", date);
  initURL.searchParams.set("flag", "N,N,Y");
  const response = await fetch(initURL, {
    headers: browserHeaders,
    redirect: "follow",
    signal: AbortSignal.timeout(12_000)
  });
  if (!response.ok) throw new Error(`session_http_${response.status}`);
  await response.arrayBuffer();
  const setCookies = response.headers.getSetCookie?.() || [response.headers.get("set-cookie")].filter(Boolean);
  return setCookies.map((cookie) => cookie.split(";", 1)[0]).join("; ");
}

async function fetchJSON(url, cookies) {
  const response = await fetch(url, {
    headers: { ...browserHeaders, cookie: cookies },
    redirect: "follow",
    signal: AbortSignal.timeout(15_000)
  });
  if (!response.ok) throw new Error(`http_${response.status}`);
  const contentType = response.headers.get("content-type") || "";
  if (!contentType.includes("json")) throw new Error("unexpected_non_json_response");
  const payload = await response.json();
  if (!payload?.status) throw new Error(payload?.messages || "provider_rejected_query");
  return payload;
}

function compareTrains(a, b, from, to) {
  const stationPenalty = (value) => (value.fromCode === from.code ? 0 : 1) + (value.toCode === to.code ? 0 : 1);
  const prefixScore = (value) => /^[GDC]/u.test(value.serviceNumber) ? 0 : 1;
  const daytimeScore = (value) => value.departureTime >= "06:00" && value.departureTime <= "20:30" ? 0 : 1;
  return stationPenalty(a) - stationPenalty(b)
    || prefixScore(a) - prefixScore(b)
    || daytimeScore(a) - daytimeScore(b)
    || (a.durationMinutes ?? 9_999) - (b.durationMinutes ?? 9_999)
    || a.departureTime.localeCompare(b.departureTime);
}

function toOption(train, price, journey) {
  const capturedAt = new Date().toISOString();
  const bookingURL = new URL(`${baseURL}/leftTicket/init`);
  bookingURL.searchParams.set("linktypeid", "dc");
  bookingURL.searchParams.set("fs", `${journey.from.name},${journey.from.code}`);
  bookingURL.searchParams.set("ts", `${journey.to.name},${journey.to.code}`);
  bookingURL.searchParams.set("date", journey.date);
  bookingURL.searchParams.set("flag", "N,N,Y");
  return {
    provider: "12306",
    mode: "train",
    direction: journey.direction,
    serviceNumber: train.serviceNumber,
    originName: train.fromName,
    destinationName: train.toName,
    departureTime: dateTimeISO(journey.date, train.departureTime),
    arrivalTime: arrivalDateTimeISO(journey.date, train.departureTime, train.arrivalTime),
    durationMinutes: train.durationMinutes,
    amountCNY: price?.amountCNY ?? null,
    fareName: price?.fareName ?? "票价待页面确认",
    availability: availabilitySummary(train.availability),
    bookingURL: bookingURL.toString(),
    capturedAt,
    note: `${journey.direction === "return" ? "返程" : "去程"}余票和票价来自铁路12306公开查询页，提交订单前请再次确认`
  };
}

function dateTimeISO(date, time) {
  const local = new Date(`${date}T${time}:00+08:00`);
  return local.toISOString();
}

function arrivalDateTimeISO(date, departureTime, arrivalTime) {
  const departure = new Date(`${date}T${departureTime}:00+08:00`);
  const arrival = new Date(`${date}T${arrivalTime}:00+08:00`);
  if (arrival < departure) arrival.setUTCMinutes(arrival.getUTCMinutes() + 24 * 60);
  return arrival.toISOString();
}
