import { createHash } from "node:crypto";
import { gcj02ToWGS84 } from "../amap-service.mjs";
import { parseCNY } from "../lib/normalize.mjs";

const DEFAULT_ENDPOINT = "https://api.elong.com/rest";
const DEFAULT_VERSION = "1.70";
const MAX_CITY_PAGES = 30;
const CITY_PAGE_SIZE = 200;
const HOTEL_PAGE_SIZE = 2_000;
const MAX_DYNAMIC_HOTELS = 60;
const MAX_DETAIL_HOTELS = 40;

export class ElongHotelAdapter {
  name = "elong-open-api";

  constructor(options = {}) {
    this.env = options.env || process.env;
    this.fetchImpl = options.fetchImpl || globalThis.fetch;
    this.now = options.now || (() => new Date());
  }

  async discover(request) {
    let configuration;
    try {
      configuration = readConfiguration(this.env);
    } catch (error) {
      return {
        hotels: [],
        diagnostics: [{ provider: this.name, status: "failed", detail: error.message }]
      };
    }
    if (!configuration) {
      return {
        hotels: [],
        diagnostics: [{
          provider: this.name,
          status: "disabled",
          detail: "需要 ELONG_USER、ELONG_APP_KEY 与 ELONG_SECRET_KEY"
        }]
      };
    }

    const capturedAt = this.now().toISOString();
    try {
      const city = await this.#resolveCity(request.destination, configuration);
      if (!city) {
        return {
          hotels: [],
          diagnostics: [{ provider: this.name, status: "city_id_missing" }]
        };
      }

      const hotelRows = await this.#hotelList(city.cityID, configuration);
      if (!hotelRows.length) {
        return {
          hotels: [],
          diagnostics: [{
            provider: this.name,
            status: "no_visible_cards",
            detail: `艺龙开放平台没有返回${city.cityName}的有效酒店`
          }]
        };
      }

      const requestedSize = Math.min(Math.max(Number(request.size || 20), 1), 20);
      const dynamicCandidates = hotelRows.slice(0, Math.min(MAX_DYNAMIC_HOTELS, Math.max(requestedSize * 3, 30)));
      const dynamicByID = await this.#dynamicRates(dynamicCandidates, request, configuration);
      const ranked = [...dynamicCandidates].sort((lhs, rhs) => {
        const lhsAmount = dynamicByID.get(lhs.hotelID)?.amountCNY ?? Number.MAX_SAFE_INTEGER;
        const rhsAmount = dynamicByID.get(rhs.hotelID)?.amountCNY ?? Number.MAX_SAFE_INTEGER;
        return lhsAmount - rhsAmount || lhs.name.localeCompare(rhs.name, "zh-CN");
      });
      const detailTargets = ranked.slice(0, Math.min(MAX_DETAIL_HOTELS, Math.max(requestedSize * 2, 20)));
      const details = await mapWithConcurrency(detailTargets, 6, async (hotel) => {
        try {
          const payload = await this.#call("hotel.static.info", {
            HotelId: hotel.hotelID,
            Options: "1,4"
          }, configuration);
          return [hotel.hotelID, normalizeStaticInfo(payload?.Result, hotel)];
        } catch {
          return [hotel.hotelID, normalizeStaticInfo(null, hotel)];
        }
      });
      const detailByID = new Map(details);

      const hotels = detailTargets
        .map((hotel) => listingFromElong({
          hotel,
          detail: detailByID.get(hotel.hotelID),
          dynamic: dynamicByID.get(hotel.hotelID),
          request,
          capturedAt,
          bookingBaseURL: this.env.ELONG_BOOKING_BASE_URL
        }))
        .filter(Boolean)
        .slice(0, requestedSize);
      const pricedCount = hotels.filter((hotel) => hotel.amountCNY != null).length;
      return {
        hotels,
        diagnostics: [{
          provider: this.name,
          status: hotels.length ? "ok" : "no_matching_quotes",
          resultCount: hotels.length,
          pricedCount,
          cityID: city.cityID,
          capturedAt,
          detail: pricedCount
            ? `已读取指定入住日期的实时最低价：${pricedCount} 家`
            : "酒店目录已返回，但当前日期没有可售最低价"
        }]
      };
    } catch (error) {
      return {
        hotels: [],
        diagnostics: [{
          provider: this.name,
          status: elongFailureStatus(error),
          detail: error.message
        }]
      };
    }
  }

  async #resolveCity(destination, configuration) {
    const wanted = normalizeCityName(destination);
    if (!wanted) return null;
    for (let pageIndex = 1; pageIndex <= MAX_CITY_PAGES; pageIndex += 1) {
      const payload = await this.#call("hotel.static.city", {
        CountryType: 1,
        CityIdType: 1,
        IsNeedLocation: false,
        PageSize: CITY_PAGE_SIZE,
        PageIndex: pageIndex
      }, configuration);
      const result = payload?.Result || {};
      const cities = Array.isArray(result.Citys) ? result.Citys : [];
      const match = cities.find((city) => normalizeCityName(city.CityName) === wanted);
      if (match) {
        const cityID = String(match.CityId ?? match.CityID ?? "").trim();
        if (cityID) return { cityID, cityName: String(match.CityName || destination).trim() };
      }
      const count = Number(result.Count || 0);
      if (!cities.length || cities.length < CITY_PAGE_SIZE || pageIndex * CITY_PAGE_SIZE >= count) break;
    }
    return null;
  }

  async #hotelList(cityID, configuration) {
    const payload = await this.#call("hotel.static.list", {
      CityId: cityID,
      PageSize: HOTEL_PAGE_SIZE,
      PageIndex: 1
    }, configuration);
    const result = payload?.Result || {};
    const rows = Array.isArray(result.Hotels)
      ? result.Hotels
      : Array.isArray(result.HotelIds) ? result.HotelIds : [];
    const seen = new Set();
    return rows.map((row) => {
      const hotelID = String(row?.HotelId ?? row?.HotelID ?? "").trim();
      const name = String(row?.HotelName ?? row?.Name ?? "").trim();
      const status = row?.HotelStatus == null ? 0 : Number(row.HotelStatus);
      if (!hotelID || name.length < 2 || status !== 0 || seen.has(hotelID)) return null;
      seen.add(hotelID);
      return { hotelID, name };
    }).filter(Boolean);
  }

  async #dynamicRates(hotels, request, configuration) {
    const batches = chunk(hotels, 10);
    const responses = await mapWithConcurrency(batches, 3, async (batch) => {
      try {
        return await this.#call("hotel.detail", {
          ArrivalDate: request.checkIn,
          DepartureDate: request.checkOut,
          HotelIds: batch.map((hotel) => hotel.hotelID).join(","),
          PaymentType: "All",
          NumberOfAdults: Math.min(Math.max(Number(request.adults || 1), 1), 8),
          NumberOfRooms: Math.min(Math.max(Number(request.rooms || 1), 1), 4),
          Options: "4,13"
        }, configuration);
      } catch (error) {
        return { __error: error };
      }
    });
    const result = new Map();
    let firstError = null;
    for (const payload of responses) {
      if (payload?.__error) {
        firstError ||= payload.__error;
        continue;
      }
      for (const row of payload?.Result?.Hotels || []) {
        const hotelID = String(row?.HotelId ?? row?.HotelID ?? "").trim();
        if (!hotelID) continue;
        const currency = String(row.CurrencyCode || "RMB").toUpperCase();
        const amountCNY = ["RMB", "CNY"].includes(currency) ? parseCNY(row.LowRate) : null;
        result.set(hotelID, { amountCNY, currency, raw: row });
      }
    }
    if (!result.size && firstError) throw firstError;
    return result;
  }

  async #call(method, request, configuration) {
    const timestamp = String(Math.floor(this.now().getTime() / 1_000));
    const data = JSON.stringify({
      Version: configuration.version,
      Local: "zh_CN",
      Request: request
    });
    const endpoint = new URL(configuration.endpoint);
    endpoint.searchParams.set("timestamp", timestamp);
    endpoint.searchParams.set("format", "json");
    endpoint.searchParams.set("method", method);
    endpoint.searchParams.set("signature", elongSignature({
      timestamp,
      data,
      appKey: configuration.appKey,
      secretKey: configuration.secretKey
    }));
    endpoint.searchParams.set("user", configuration.user);
    endpoint.searchParams.set("data", data);

    const response = await this.fetchImpl(endpoint, {
      headers: {
        accept: "application/json",
        "accept-encoding": "br, gzip"
      },
      signal: AbortSignal.timeout(20_000)
    });
    if (!response.ok) throw new Error(`艺龙开放平台 HTTP ${response.status}`);
    const payload = await response.json();
    if (String(payload?.Code) !== "0") {
      const detail = payload?.Result?.ErrorMessage || payload?.Result?.Message || payload?.Message || `Code ${payload?.Code ?? "unknown"}`;
      const error = new Error(`艺龙开放平台 ${method}：${detail}`);
      error.code = String(payload?.Code ?? "unknown");
      error.guid = payload?.Guid;
      throw error;
    }
    return payload;
  }
}

export function elongSignature({ timestamp, data, appKey, secretKey }) {
  const inner = md5(`${data}${appKey}`);
  return md5(`${timestamp}${inner}${secretKey}`);
}

export function listingFromElong({
  hotel,
  detail,
  dynamic,
  request,
  capturedAt,
  bookingBaseURL
}) {
  const name = String(detail?.name || hotel?.name || "").trim();
  if (!hotel?.hotelID || name.length < 2) return null;
  const amountCNY = dynamic?.amountCNY ?? null;
  return {
    providerHotelID: hotel.hotelID,
    provider: "tongcheng",
    source: "elong-open-api",
    name,
    brand: detail?.brand || null,
    address: detail?.address || "",
    latitude: detail?.latitude ?? null,
    longitude: detail?.longitude ?? null,
    starRating: detail?.starRating ?? null,
    guestRating: null,
    description: detail?.description || null,
    imageURL: detail?.imageURL || null,
    bookingURL: elongBookingURL(hotel.hotelID, request, bookingBaseURL),
    amenities: detail?.amenities || [],
    tags: ["艺龙开放平台", ...(detail?.tags || [])],
    amountCNY,
    unit: "perNight",
    kind: amountCNY == null ? "checkOnProvider" : "live",
    capturedAt,
    note: amountCNY == null
      ? "艺龙开放平台酒店目录；当前入住日期暂无可售最低价"
      : "艺龙开放平台指定入住日期实时最低价；房型、库存、税费与退改请在结算页复核",
    availability: amountCNY == null ? "当前条件暂无可售最低价" : "指定日期可售"
  };
}

function readConfiguration(env) {
  const user = String(env.ELONG_USER || "").trim();
  const appKey = String(env.ELONG_APP_KEY || "").trim();
  const secretKey = String(env.ELONG_SECRET_KEY || "").trim();
  if (!user || !appKey || !secretKey) return null;
  const endpoint = String(env.ELONG_ENDPOINT || DEFAULT_ENDPOINT).trim();
  const parsed = new URL(endpoint);
  if (parsed.protocol !== "https:") throw new Error("ELONG_ENDPOINT 必须使用 HTTPS");
  return {
    user,
    appKey,
    secretKey,
    endpoint: parsed.href,
    version: String(env.ELONG_VERSION || DEFAULT_VERSION).trim()
  };
}

function normalizeStaticInfo(result, fallback) {
  const detail = result?.Detail || result?.Hotel || result || {};
  const longitude = finiteNumber(detail.GoogleLon);
  const latitude = finiteNumber(detail.GoogleLat);
  const coordinate = longitude != null && latitude != null
    ? gcj02ToWGS84(longitude, latitude)
    : null;
  const images = Array.isArray(result?.Images) ? result.Images : [];
  return {
    name: String(detail.HotelName || fallback.name || "").trim(),
    brand: optionalText(detail.BrandName || detail.GroupName),
    address: String(detail.Address || "").trim(),
    latitude: coordinate?.latitude ?? null,
    longitude: coordinate?.longitude ?? null,
    starRating: positiveNumber(detail.StarRate) || positiveNumber(detail.Category),
    description: stripHTML(detail.IntroEditor || detail.Description),
    imageURL: firstImageURL(images),
    amenities: facilityNames(detail),
    tags: hotelTypeNames(detail.HotelTypes)
  };
}

function firstImageURL(images) {
  const candidates = [];
  visitValues(images, (key, value) => {
    if (/url|path/i.test(key) && typeof value === "string") candidates.push(value);
  });
  return candidates.map(safeHTTPURL).find(Boolean) || null;
}

function facilityNames(detail) {
  const groups = [
    detail.GeneralFacilities,
    detail.RecreationFacilities,
    detail.ServiceFacilities
  ];
  const result = [];
  visitValues(groups, (key, value) => {
    if (/name|facilityname|description/i.test(key) && typeof value === "string") {
      const text = stripHTML(value);
      if (text && text.length <= 30) result.push(text);
    }
  });
  return [...new Set(result)].slice(0, 12);
}

function hotelTypeNames(value) {
  const types = Array.isArray(value) ? value : [];
  return [...new Set(types.map((item) => String(item?.Name || item?.HotelTypeName || "").trim()).filter(Boolean))].slice(0, 6);
}

function elongBookingURL(hotelID, request, baseURL) {
  const base = String(baseURL || "https://m.elong.com/hotel/detail").trim();
  try {
    const url = new URL(base);
    url.searchParams.set("hotelid", hotelID);
    if (request?.checkIn) url.searchParams.set("inDate", request.checkIn);
    if (request?.checkOut) url.searchParams.set("outDate", request.checkOut);
    return url.href;
  } catch {
    return null;
  }
}

function visitValues(value, visitor) {
  if (Array.isArray(value)) {
    for (const item of value) visitValues(item, visitor);
    return;
  }
  if (!value || typeof value !== "object") return;
  for (const [key, nested] of Object.entries(value)) {
    visitor(key, nested);
    visitValues(nested, visitor);
  }
}

function normalizeCityName(value) {
  return String(value || "")
    .normalize("NFKC")
    .trim()
    .replace(/(?:特别行政区|市|地区|自治州|盟)$/u, "")
    .replace(/\s+/g, "")
    .toLowerCase();
}

function elongFailureStatus(error) {
  const text = String(error?.message || "");
  if (/白名单|whitelist|ip/i.test(text)) return "ip_whitelist_required";
  if (/signature|签名/i.test(text)) return "credential_rejected";
  return "failed";
}

function stripHTML(value) {
  const text = String(value || "")
    .replace(/<br\s*\/?\s*>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/\s+/g, " ")
    .trim();
  return text || null;
}

function safeHTTPURL(value) {
  try {
    const url = new URL(String(value || ""));
    return ["http:", "https:"].includes(url.protocol) ? url.href : null;
  } catch {
    return null;
  }
}

function positiveNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : null;
}

function finiteNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function optionalText(value) {
  const text = String(value || "").trim();
  return text || null;
}

function md5(value) {
  return createHash("md5").update(String(value), "utf8").digest("hex");
}

function chunk(values, size) {
  const result = [];
  for (let index = 0; index < values.length; index += size) result.push(values.slice(index, index + size));
  return result;
}

async function mapWithConcurrency(values, concurrency, operation) {
  const result = new Array(values.length);
  let nextIndex = 0;
  async function worker() {
    while (nextIndex < values.length) {
      const index = nextIndex;
      nextIndex += 1;
      result[index] = await operation(values[index], index);
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, values.length) }, worker));
  return result;
}
