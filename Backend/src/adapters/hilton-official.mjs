import { isoNow, normalizeHotelName, parseCNY } from "../lib/normalize.mjs";
import { networkUserAgent } from "../network-identity.mjs";

const DEFAULT_ENDPOINT = "https://console-lls.hilton.com.cn/cgi/api/app/hotel/zh-CN/search";
const MAX_RESULTS = 30;

/** Reads the public hotel-search payload used by Hilton China's website. */
export class HiltonOfficialAdapter {
  name = "hilton-official";

  constructor(options = {}) {
    this.fetchImpl = options.fetchImpl || globalThis.fetch;
    this.endpoint = options.endpoint || process.env.HILTON_OFFICIAL_ENDPOINT || DEFAULT_ENDPOINT;
    this.now = options.now || (() => new Date());
  }

  async discover(request) {
    try {
      const payload = await this.#fetch(request.destination);
      const capturedAt = this.now().toISOString();
      const hotels = listingsFromHiltonPayload(payload, request, capturedAt)
        .slice(0, Math.min(Number(request.size || 20), MAX_RESULTS));
      return {
        hotels,
        diagnostics: [{
          provider: this.name,
          status: hotels.length ? "ok" : "no_visible_cards",
          resultCount: hotels.length,
          pricedCount: hotels.filter((hotel) => hotel.amountCNY != null).length,
          capturedAt,
          detail: "官网公开起价标为参考价；购买链接已带入行程日期"
        }]
      };
    } catch (error) {
      return { hotels: [], diagnostics: [{ provider: this.name, status: "failed", detail: error.message }] };
    }
  }

  async search(request) {
    try {
      const payload = await this.#fetch(request.destination);
      const capturedAt = this.now().toISOString();
      const listings = listingsFromHiltonPayload(payload, request, capturedAt);
      const quotes = [];
      const matched = new Set();
      for (const listing of listings) {
        const candidate = strongCandidateMatch(listing.name, request.hotels || []);
        if (!candidate || matched.has(candidate.id) || listing.amountCNY == null) continue;
        matched.add(candidate.id);
        quotes.push({
          hotelID: candidate.id,
          hotelName: candidate.name,
          provider: "official",
          source: this.name,
          amountCNY: listing.amountCNY,
          unit: "perNight",
          kind: "indicative",
          capturedAt,
          bookingURL: listing.bookingURL,
          note: "希尔顿官网当前公开起价；已带入行程日期，进入官网后复核对应日期房型与库存",
          availability: "官网公开起价"
        });
      }
      return {
        quotes,
        diagnostics: [{
          provider: this.name,
          status: quotes.length ? "ok" : "no_matching_quotes",
          resultCount: listings.length,
          matchedCount: quotes.length,
          capturedAt
        }]
      };
    } catch (error) {
      return { quotes: [], diagnostics: [{ provider: this.name, status: "failed", detail: error.message }] };
    }
  }

  async #fetch(keyword) {
    const url = new URL(this.endpoint);
    url.searchParams.set("keywords", String(keyword || "").trim());
    const response = await this.fetchImpl(url, {
      headers: {
        accept: "application/json",
        "accept-language": "zh-CN,zh;q=0.9",
        "user-agent": networkUserAgent
      },
      signal: AbortSignal.timeout(12_000)
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const payload = await response.json();
    if (payload?.success === false || Number(payload?.code || 200) >= 400) {
      throw new Error(String(payload?.message || `Hilton API ${payload?.code || "error"}`));
    }
    return payload;
  }
}

export function listingsFromHiltonPayload(payload, request, capturedAt = isoNow()) {
  const rows = Array.isArray(payload?.data?.hotels)
    ? payload.data.hotels
    : Array.isArray(payload?.hotels) ? payload.hotels : [];
  const seen = new Set();
  return rows.map((row) => {
    const name = String(row?.hotelName || row?.name || "").trim();
    const hotelCode = String(row?.hotelCode || row?.id || "").trim();
    if (name.length < 2 || !hotelCode || seen.has(hotelCode)) return null;
    seen.add(hotelCode);
    const coordinate = row?.location?.coordinate || row?.coordinate || {};
    const amountCNY = parseCNY(row?.minPrice);
    const tags = (Array.isArray(row?.tags) ? row.tags : [])
      .map((tag) => String(tag?.tagName || tag?.name || tag || "").trim())
      .filter(Boolean);
    return {
      providerHotelID: `hilton-${hotelCode}`,
      provider: "official",
      source: "hilton-official",
      name,
      brand: hiltonBrandName(row?.brandCode),
      address: String(row?.location?.address || row?.address || "").trim(),
      latitude: finiteCoordinate(coordinate.latitude ?? coordinate.lat, -90, 90),
      longitude: finiteCoordinate(coordinate.longitude ?? coordinate.lng, -180, 180),
      description: String(row?.hotelDesc || "").trim() || null,
      imageURL: validHTTPURL(row?.masterCover?.url),
      amenities: Array.isArray(row?.amenities) ? row.amenities.map(String).slice(0, 16) : [],
      tags: [...new Set([
        ...(Array.isArray(row?.sellingPoints) ? row.sellingPoints.map(String) : []),
        ...tags
      ])].slice(0, 16),
      amountCNY,
      unit: "perNight",
      kind: amountCNY == null ? "checkOnProvider" : "indicative",
      capturedAt,
      bookingURL: hiltonBookingURL(hotelCode, request),
      note: amountCNY == null
        ? "前往希尔顿官网查看所选日期房型"
        : "希尔顿官网当前公开起价；购买页已带入行程日期，请在官网复核",
      availability: amountCNY == null ? null : "官网公开起价"
    };
  }).filter(Boolean);
}

function hiltonBookingURL(hotelCode, request) {
  const url = new URL("https://www.hilton.com/zh-hans/book/reservation/deeplink/");
  url.searchParams.set("ctyhocn", hotelCode);
  if (request?.checkIn) url.searchParams.set("arrivalDate", request.checkIn);
  if (request?.checkOut) url.searchParams.set("departureDate", request.checkOut);
  url.searchParams.set("room1NumAdults", String(Math.min(Math.max(Number(request?.adults || 1), 1), 8)));
  url.searchParams.set("numRooms", String(Math.min(Math.max(Number(request?.rooms || 1), 1), 4)));
  return url.toString();
}

function strongCandidateMatch(name, candidates) {
  const normalized = normalizeHotelName(name);
  if (!normalized) return null;
  return candidates.find((candidate) => {
    const wanted = normalizeHotelName(candidate?.name);
    if (!wanted) return false;
    return normalized === wanted
      || (Math.min(normalized.length, wanted.length) >= 5
        && (normalized.includes(wanted) || wanted.includes(normalized)));
  }) || null;
}

function finiteCoordinate(value, minimum, maximum) {
  const number = Number(value);
  return Number.isFinite(number) && number >= minimum && number <= maximum ? number : null;
}

function validHTTPURL(value) {
  try {
    const url = new URL(String(value || ""));
    return ["http:", "https:"].includes(url.protocol) ? url.toString() : null;
  } catch {
    return null;
  }
}

function hiltonBrandName(code) {
  const brands = {
    WA: "华尔道夫", CH: "康莱德", LX: "LXR", HI: "希尔顿",
    QQ: "嘉悦里", DT: "希尔顿逸林", UP: "格芮精选", PY: "启缤精选",
    ES: "希尔顿安泊", HT: "希尔顿欢朋", GI: "希尔顿花园",
    HW: "欣庭", RU: "欢朋", UA: "希尔顿惠庭"
  };
  return brands[String(code || "").toUpperCase()] || "希尔顿集团";
}
