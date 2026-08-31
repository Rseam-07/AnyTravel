import { matchRequestedHotel, normalizeHotelName } from "./normalize.mjs";

export function selectCtripHotelSuggestion(payload, requestedHotelName, expectedCityID) {
  const requested = normalizeHotelName(requestedHotelName);
  if (!requested) return null;
  const rows = payload?.Response?.searchResults;
  if (!Array.isArray(rows)) return null;

  for (const row of rows) {
    if (row?.type !== "Hotel" || !row.id) continue;
    if (Number.isFinite(Number(expectedCityID)) && Number(row.cityId) !== Number(expectedCityID)) continue;
    const visibleName = String(row.word || row.displayName || "").split(",")[0].trim();
    const candidate = normalizeHotelName(visibleName);
    const shorter = Math.min(candidate.length, requested.length);
    const longer = Math.max(candidate.length, requested.length);
    const isStrongMatch = candidate === requested
      || (shorter >= 4 && shorter / Math.max(longer, 1) >= 0.72
        && (candidate.includes(requested) || requested.includes(candidate)));
    if (isStrongMatch) {
      return { id: String(row.id), name: visibleName, cityID: Number(row.cityId) };
    }
  }
  return null;
}

export function parseCtripCardTexts(cardTexts, requestedHotels, bookingURL, capturedAt) {
  const quotes = [];
  for (const rawText of cardTexts) {
    const text = String(rawText ?? "").replace(/\s+/g, " ").trim();
    if (!text) continue;
    const name = extractHotelName(text);
    if (!name) continue;
    const requested = matchRequestedHotel(name, requestedHotels);
    if (!requested) continue;

    const withoutReviewCounts = text
      .replace(/\d{1,3}(?:,\d{3})+\s*条点评/g, "")
      .replace(/\d+\s*条点评/g, "");
    const prices = [...withoutReviewCounts.matchAll(/[¥￥]\s*([\d,]{2,})/g)]
      .map((match) => Number(match[1].replace(/,/g, "")))
      .filter((value) => Number.isFinite(value) && value >= 20);
    if (!prices.length) continue;

    const currentPrice = prices.at(-1);
    const originalPrice = prices.length > 1 ? prices[0] : null;
    quotes.push({
      hotelID: requested.id,
      hotelName: requested.name,
      provider: "ctrip",
      amountCNY: currentPrice,
      unit: "perNight",
      kind: "live",
      capturedAt,
      bookingURL,
      note: originalPrice && originalPrice > currentPrice
        ? `页面起价，划线价¥${originalPrice}；房型、早餐和退改以结算页为准`
        : "页面起价；房型、早餐、税费和退改以结算页为准"
    });
  }

  const lowestByHotel = new Map();
  for (const quote of quotes) {
    const previous = lowestByHotel.get(quote.hotelID);
    if (!previous || quote.amountCNY < previous.amountCNY) lowestByHotel.set(quote.hotelID, quote);
  }
  return [...lowestByHotel.values()];
}

function extractHotelName(text) {
  const match = text.match(/^(.{2,70}?(?:酒店|宾馆|旅馆|客栈|民宿|公寓)(?:[（(].*?[）)])?)(?=\s|\d\.\d|$)/);
  if (match) return match[1].trim();
  return text.split(/\d\.\d|超棒|很好|不错|¥|￥/)[0]?.trim().slice(0, 70) || null;
}
