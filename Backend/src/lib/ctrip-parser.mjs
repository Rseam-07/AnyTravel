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

export function parseCtripCatalogCards(cards, fallbackBookingURL, capturedAt) {
  const result = new Map();
  for (const card of cards) {
    const rawText = typeof card === "string" ? card : card?.text;
    const text = String(rawText || "").replace(/\s+/g, " ").trim();
    if (!text) continue;
    const name = extractHotelName(text);
    if (!name) continue;
    const bookingURL = typeof card === "object" && card?.href ? card.href : fallbackBookingURL;
    const prices = extractVisiblePrices(text);
    const amountCNY = prices.at(-1) ?? null;
    const providerHotelID = hotelIDFromURL(bookingURL) || `ctrip-${normalizeHotelName(name)}`;
    const listing = {
      providerHotelID,
      provider: "ctrip",
      source: "ctrip-session",
      name,
      address: extractAddress(text, name),
      bookingURL,
      amenities: [],
      tags: extractCatalogTags(text),
      amountCNY,
      unit: "perNight",
      kind: amountCNY == null ? "checkOnProvider" : "live",
      capturedAt,
      note: amountCNY == null
        ? "携程登录会话已找到这家住宿；数字价格需在渠道页继续确认"
        : "携程页面当前起价；房型、早餐、税费和退改以结算页为准"
    };
    const previous = result.get(providerHotelID);
    if (!previous || previous.amountCNY == null || amountCNY != null && amountCNY < previous.amountCNY) {
      result.set(providerHotelID, listing);
    }
  }
  return [...result.values()];
}

function extractHotelName(text) {
  const match = text.match(/^(.{2,70}?(?:酒店|宾馆|旅馆|客栈|民宿|公寓)(?:[（(].*?[）)])?)(?=\s|\d\.\d|$)/);
  if (match) return match[1].trim();
  return text.split(/\d\.\d|超棒|很好|不错|¥|￥/)[0]?.trim().slice(0, 70) || null;
}

function extractVisiblePrices(text) {
  const withoutReviewCounts = text
    .replace(/\d{1,3}(?:,\d{3})+\s*条点评/g, "")
    .replace(/\d+\s*条点评/g, "");
  return [...withoutReviewCounts.matchAll(/[¥￥]\s*([\d,]{2,})/g)]
    .map((match) => Number(match[1].replace(/,/g, "")))
    .filter((value) => Number.isFinite(value) && value >= 20 && value <= 100_000);
}

function extractAddress(text, name) {
  const remainder = text.slice(text.indexOf(name) + name.length).trim();
  const match = remainder.match(/(?:距[^¥￥]{0,50})?([\p{Script=Han}A-Za-z0-9]{2,40}(?:路|街|巷|大道|镇|村|号|区)[^¥￥\d]{0,18})/u);
  return match?.[1]?.trim() || "";
}

function extractCatalogTags(text) {
  const patterns = ["免费取消", "含早", "近地铁", "亲子", "宠物友好", "停车", "接送机"];
  return patterns.filter((value) => text.includes(value));
}

function hotelIDFromURL(value) {
  if (!value) return null;
  try {
    const url = new URL(value, "https://hotels.ctrip.com/");
    return url.pathname.match(/(?:hotels|detail)\/(?:detail\/)?(\d+)/)?.[1]
      || url.searchParams.get("hotelid")
      || url.searchParams.get("hotelId");
  } catch { return null; }
}
