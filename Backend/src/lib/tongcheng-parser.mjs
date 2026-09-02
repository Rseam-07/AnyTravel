import { normalizeHotelName } from "./normalize.mjs";

export function parseTongchengCardTexts(cards, requestedHotels, fallbackBookingURL, capturedAt) {
  const quotes = [];
  for (const card of cards) {
    const rawText = typeof card === "string" ? card : card?.text;
    const bookingURL = typeof card === "object" && card?.href ? card.href : fallbackBookingURL;
    const text = String(rawText || "").trim();
    if (!text) continue;
    const name = extractHotelName(text);
    const requested = name ? strongMatch(name, requestedHotels) : null;
    if (!requested) continue;

    const withoutReviewCounts = text
      .replace(/\d{1,3}(?:,\d{3})+\s*(?:条)?点评/g, "")
      .replace(/\d+\s*(?:条)?点评/g, "");
    const prices = [...withoutReviewCounts.matchAll(/[¥￥]\s*([\d,]{2,})/g)]
      .map((match) => Number(match[1].replace(/,/g, "")))
      .filter((value) => Number.isFinite(value) && value >= 20 && value <= 100_000);
    if (!prices.length) continue;

    const currentPrice = prices.at(-1);
    const originalPrice = prices.length > 1 && prices[0] > currentPrice ? prices[0] : null;
    const policies = extractPolicyNotes(text);
    const notes = [
      originalPrice ? `页面起价，划线价¥${originalPrice}` : "页面起价",
      ...policies,
      "房型、早餐、税费和退改以结算页为准"
    ];
    quotes.push({
      hotelID: requested.id,
      hotelName: requested.name,
      provider: "tongcheng",
      amountCNY: currentPrice,
      unit: "perNight",
      kind: "live",
      capturedAt,
      bookingURL,
      note: [...new Set(notes)].join("；")
    });
  }

  const lowestByHotel = new Map();
  for (const quote of quotes) {
    const previous = lowestByHotel.get(quote.hotelID);
    if (!previous || quote.amountCNY < previous.amountCNY) lowestByHotel.set(quote.hotelID, quote);
  }
  return [...lowestByHotel.values()];
}

export function parseTongchengCatalogCards(cards, fallbackBookingURL, capturedAt) {
  const result = new Map();
  for (const card of cards) {
    const rawText = typeof card === "string" ? card : card?.text;
    const bookingURL = typeof card === "object" && card?.href ? card.href : fallbackBookingURL;
    const text = String(rawText || "").trim();
    if (!text) continue;
    const name = extractHotelName(text);
    if (!name) continue;
    const withoutReviewCounts = text
      .replace(/\d{1,3}(?:,\d{3})+\s*(?:条)?点评/g, "")
      .replace(/\d+\s*(?:条)?点评/g, "");
    const prices = [...withoutReviewCounts.matchAll(/[¥￥]\s*([\d,]{2,})/g)]
      .map((match) => Number(match[1].replace(/,/g, "")))
      .filter((value) => Number.isFinite(value) && value >= 20 && value <= 100_000);
    const amountCNY = prices.at(-1) ?? null;
    const providerHotelID = hotelIDFromURL(bookingURL) || `tongcheng-${normalizeHotelName(name)}`;
    const policies = extractPolicyNotes(text);
    const listing = {
      providerHotelID,
      provider: "tongcheng",
      source: "tongcheng-session",
      name,
      address: extractAddress(text, name),
      bookingURL,
      amenities: [],
      tags: policies,
      amountCNY,
      unit: "perNight",
      kind: amountCNY == null ? "checkOnProvider" : "live",
      capturedAt,
      note: amountCNY == null
        ? "同程登录会话已找到这家住宿；数字价格需在渠道页继续确认"
        : ["同程页面当前起价", ...policies, "房型、税费和退改以结算页为准"].join("；")
    };
    const previous = result.get(providerHotelID);
    if (!previous || previous.amountCNY == null || amountCNY != null && amountCNY < previous.amountCNY) {
      result.set(providerHotelID, listing);
    }
  }
  return [...result.values()];
}

function strongMatch(candidateName, requestedHotels) {
  const candidate = normalizeHotelName(candidateName);
  if (candidate.length < 3) return null;
  for (const hotel of requestedHotels) {
    const requested = normalizeHotelName(hotel.name);
    if (!requested) continue;
    if (candidate === requested) return hotel;
    const shorter = Math.min(candidate.length, requested.length);
    const longer = Math.max(candidate.length, requested.length);
    if (shorter >= 4 && shorter / longer >= 0.58
        && (candidate.includes(requested) || requested.includes(candidate))) {
      return hotel;
    }
  }
  return null;
}

function extractHotelName(text) {
  const lines = text.split(/\n+/).map((line) => line.trim()).filter(Boolean);
  const namedLine = lines.find((line) => /酒店|宾馆|旅馆|客栈|民宿|公寓/.test(line) && line.length <= 100);
  if (namedLine) return trimAfterMetadata(namedLine);
  const compact = text.replace(/\s+/g, " ").trim();
  const match = compact.match(/^(.{2,80}?(?:酒店|宾馆|旅馆|客栈|民宿|公寓)(?:[（(].*?[）)])?)(?=\s|\d(?:\.\d)?分|[¥￥]|$)/);
  return match ? match[1].trim() : null;
}

function trimAfterMetadata(value) {
  return value.split(/\s+(?=\d(?:\.\d)?分|[¥￥]|距|登录)/)[0].trim();
}

function extractPolicyNotes(text) {
  const notes = [];
  if (/免费取消|可免费取消/.test(text)) notes.push("页面标注免费取消");
  else if (/不可取消|取消收费/.test(text)) notes.push("页面标注取消受限");
  if (/含早|含早餐|双早|单早/.test(text)) notes.push("页面标注含早");
  else if (/无早|不含早/.test(text)) notes.push("页面标注不含早");
  return notes;
}

function extractAddress(text, name) {
  const compact = text.replace(/\s+/g, " ");
  const remainder = compact.slice(compact.indexOf(name) + name.length).trim();
  const match = remainder.match(/([\p{Script=Han}A-Za-z0-9]{2,40}(?:路|街|巷|大道|镇|村|号|区)[^¥￥\d]{0,18})/u);
  return match?.[1]?.trim() || "";
}

function hotelIDFromURL(value) {
  if (!value) return null;
  try {
    const url = new URL(value, "https://m.elong.com/");
    return url.searchParams.get("hotelid")
      || url.searchParams.get("hotelId")
      || url.pathname.match(/(?:hotel|detail)[\/-]?(\d{3,})/i)?.[1];
  } catch { return null; }
}
