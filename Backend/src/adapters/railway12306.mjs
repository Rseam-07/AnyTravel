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

      const cookies = await createAnonymousSession(from, to, request.departureDate);
      const query = new URL(`${baseURL}/leftTicket/query`);
      query.searchParams.set("leftTicketDTO.train_date", request.departureDate);
      query.searchParams.set("leftTicketDTO.from_station", from.code);
      query.searchParams.set("leftTicketDTO.to_station", to.code);
      query.searchParams.set("purpose_codes", "ADULT");
      const payload = await fetchJSON(query, cookies);
      const stationMap = payload?.data?.map || {};
      const trains = (payload?.data?.result || [])
        .map((row) => parseTrainRow(row, stationMap))
        .filter((train) => train?.canBuy)
        .sort((a, b) => compareTrains(a, b, from, to))
        .slice(0, Math.min(Number(process.env.RAILWAY_RESULT_LIMIT || 8), 12));

      const priced = await Promise.all(trains.map(async (train) => {
        const priceURL = new URL(`${baseURL}/leftTicket/queryTicketPrice`);
        priceURL.searchParams.set("train_no", train.trainNo);
        priceURL.searchParams.set("from_station_no", train.fromStationNo);
        priceURL.searchParams.set("to_station_no", train.toStationNo);
        priceURL.searchParams.set("seat_types", train.seatTypes);
        priceURL.searchParams.set("train_date", request.departureDate);
        try {
          const price = parseTicketPrice(await fetchJSON(priceURL, cookies));
          return toOption(train, price, request, from, to);
        } catch {
          return toOption(train, null, request, from, to);
        }
      }));

      return {
        options: priced,
        diagnostics: [{ provider: "12306", status: "ok", detail: `${priced.length} trains returned` }]
      };
    } catch (error) {
      return {
        options: [],
        diagnostics: [{ provider: "12306", status: "failed", detail: error.message }]
      };
    }
  }
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

function toOption(train, price, request, from, to) {
  const capturedAt = new Date().toISOString();
  const bookingURL = new URL(`${baseURL}/leftTicket/init`);
  bookingURL.searchParams.set("linktypeid", "dc");
  bookingURL.searchParams.set("fs", `${from.name},${from.code}`);
  bookingURL.searchParams.set("ts", `${to.name},${to.code}`);
  bookingURL.searchParams.set("date", request.departureDate);
  bookingURL.searchParams.set("flag", "N,N,Y");
  return {
    provider: "12306",
    mode: "train",
    serviceNumber: train.serviceNumber,
    originName: train.fromName,
    destinationName: train.toName,
    departureTime: dateTimeISO(request.departureDate, train.departureTime),
    arrivalTime: arrivalDateTimeISO(request.departureDate, train.departureTime, train.arrivalTime),
    durationMinutes: train.durationMinutes,
    amountCNY: price?.amountCNY ?? null,
    fareName: price?.fareName ?? "票价待页面确认",
    availability: availabilitySummary(train.availability),
    bookingURL: bookingURL.toString(),
    capturedAt,
    note: "余票和票价来自铁路12306公开查询页，提交订单前请再次确认"
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
