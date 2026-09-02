export function parseCtripFlightCards(cards, context) {
  const options = [];
  for (const rawCard of cards) {
    const text = String(typeof rawCard === "string" ? rawCard : rawCard?.text || "").trim();
    if (!text || /售罄|已售完|暂无报价/.test(text)) continue;
    const times = [...text.matchAll(/(?<!\d)([01]?\d|2[0-3]):([0-5]\d)(?!\d)/g)]
      .map((match) => `${match[1].padStart(2, "0")}:${match[2]}`);
    if (times.length < 2) continue;
    const airportMatches = [...text.matchAll(/([\p{Script=Han}A-Za-z0-9·]{2,24}(?:国际)?机场(?:[\p{Script=Han}]?[Tt]\d)?)/gu)]
      .map((match) => match[1].trim());
    const airline = extractAirline(text);
    if (!airline) continue;
    const flightNumber = text.match(/\b([A-Z0-9]{2}\s?\d{3,4})\b/i)?.[1]?.replace(/\s+/g, "").toUpperCase() || null;
    const prices = [...text.matchAll(/[¥￥]\s*([\d,]{2,})/g)]
      .map((match) => Number(match[1].replace(/,/g, "")))
      .filter((value) => Number.isFinite(value) && value >= 100 && value <= 200_000);
    const amountCNY = prices.at(-1) ?? null;
    const cabin = text.match(/超级经济舱|超值经济舱|经济舱|公务舱|商务舱|头等舱/)?.[0] || "舱位待确认";
    const departureTime = dateTimeISO(context.date, times[0]);
    const arrivalTime = arrivalDateTimeISO(context.date, times[0], times[1], /\+1|次日|翌日/.test(text));
    const durationMinutes = durationFromText(text)
      ?? Math.max(Math.round((Date.parse(arrivalTime) - Date.parse(departureTime)) / 60_000), 1);
    options.push({
      provider: "ctrip",
      source: "ctrip-session",
      mode: "flight",
      direction: context.direction,
      serviceNumber: flightNumber || airline,
      originName: airportMatches[0] || context.originName,
      destinationName: airportMatches[1] || context.destinationName,
      departureTime,
      arrivalTime,
      durationMinutes,
      amountCNY,
      fareName: cabin,
      availability: amountCNY == null ? "价格待页面确认" : "当前可选",
      bookingURL: context.bookingURL,
      capturedAt: context.capturedAt,
      note: `${context.direction === "return" ? "返程" : "去程"}携程登录会话当前展示；航班、舱位、税费与库存以提交前页面为准`
    });
  }

  const unique = new Map();
  for (const option of options) {
    const key = [option.direction, option.serviceNumber, option.departureTime, option.arrivalTime, option.fareName].join("|");
    const previous = unique.get(key);
    if (!previous || option.amountCNY != null && (previous.amountCNY == null || option.amountCNY < previous.amountCNY)) {
      unique.set(key, option);
    }
  }
  return [...unique.values()].sort((lhs, rhs) => {
    const lhsAmount = lhs.amountCNY ?? Number.MAX_SAFE_INTEGER;
    const rhsAmount = rhs.amountCNY ?? Number.MAX_SAFE_INTEGER;
    return lhsAmount - rhsAmount || lhs.departureTime.localeCompare(rhs.departureTime);
  });
}

function extractAirline(text) {
  const lines = text.split(/\n+/).map((line) => line.trim()).filter(Boolean);
  const explicit = lines.find((line) =>
    /航空|国航|海航|厦航|深航|川航|春秋|吉祥|华夏|联合航空/.test(line)
      && !/[¥￥]/.test(line)
  );
  if (explicit) {
    return explicit
      .replace(/\b[A-Z0-9]{2}\s?\d{3,4}\b/ig, "")
      .replace(/共享|实际承运|波音|空客|中型机|大型机|小型机/g, "")
      .trim()
      .slice(0, 40) || explicit.slice(0, 40);
  }
  const compact = text.replace(/\s+/g, " ");
  return compact.match(/([\p{Script=Han}A-Za-z·]{2,24}(?:航空|国航|海航|厦航|深航|川航))/u)?.[1] || null;
}

function durationFromText(text) {
  const chinese = text.match(/(?:(\d+)\s*(?:小时|时)\s*)?(\d+)\s*分(?:钟)?/)
    || text.match(/(\d+)\s*(?:小时|时)/);
  if (chinese) {
    const minutes = Number(chinese[1] || 0) * 60 + Number(chinese[2] || 0);
    if (minutes >= 20 && minutes <= 2_000) return minutes;
  }
  const latin = text.match(/(?:(\d+)\s*h\s*)?(\d+)\s*m/i) || text.match(/(\d+)\s*h/i);
  if (latin) {
    const minutes = Number(latin[1] || 0) * 60 + Number(latin[2] || 0);
    if (minutes >= 20 && minutes <= 2_000) return minutes;
  }
  return null;
}

function dateTimeISO(date, time) {
  return new Date(`${date}T${time}:00+08:00`).toISOString();
}

function arrivalDateTimeISO(date, departureTime, arrivalTime, forceNextDay) {
  const departure = new Date(`${date}T${departureTime}:00+08:00`);
  const arrival = new Date(`${date}T${arrivalTime}:00+08:00`);
  if (forceNextDay || arrival < departure) arrival.setUTCMinutes(arrival.getUTCMinutes() + 24 * 60);
  return arrival.toISOString();
}
