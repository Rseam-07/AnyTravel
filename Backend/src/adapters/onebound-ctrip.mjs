import { isoNow, parseCNY } from "../lib/normalize.mjs";

const defaultEndpoint = "https://api-gw.onebound.cn/xiecheng/item_search_hotel/";

export class OneBoundCtripAdapter {
  name = "onebound-ctrip";

  async discover(request) {
    const key = process.env.ONEBOUND_API_KEY;
    const secret = process.env.ONEBOUND_API_SECRET;
    if (!key || !secret) {
      return { hotels: [], diagnostics: [{ provider: this.name, status: "disabled" }] };
    }

    const capturedAt = isoNow();
    try {
      const endpoint = new URL(process.env.ONEBOUND_CTRIP_ENDPOINT || defaultEndpoint);
      endpoint.searchParams.set("key", key);
      endpoint.searchParams.set("secret", secret);
      endpoint.searchParams.set("q", catalogQuery(request));
      endpoint.searchParams.set("page", "1");
      endpoint.searchParams.set("city", cleanCity(request.destination));
      endpoint.searchParams.set("sort", "normal");
      endpoint.searchParams.set("cache", process.env.ONEBOUND_CACHE === "no" ? "no" : "yes");
      endpoint.searchParams.set("result_type", "json");
      endpoint.searchParams.set("lang", "cn");

      const response = await fetch(endpoint, {
        headers: {
          accept: "application/json",
          "accept-language": "zh-CN,zh;q=0.9"
        },
        signal: AbortSignal.timeout(20_000)
      });
      if (!response.ok) throw new Error(`http_${response.status}`);
      const payload = await response.json();
      if (payload?.error_code && String(payload.error_code) !== "0000") {
        return {
          hotels: [],
          diagnostics: [{
            provider: this.name,
            status: oneBoundStatus(payload.error_code),
            detail: String(payload.reason || payload.error || `error_${payload.error_code}`)
          }]
        };
      }

      const rows = Array.isArray(payload?.item)
        ? payload.item
        : Array.isArray(payload?.items) ? payload.items : [];
      const hotels = rows
        .map((row) => listingFromRow(row, capturedAt))
        .filter(Boolean)
        .slice(0, Math.min(Math.max(Number(request.size || 20), 1), 40));
      return {
        hotels,
        diagnostics: [{
          provider: this.name,
          status: hotels.length ? "ok" : "no_visible_cards",
          resultCount: hotels.length,
          capturedAt,
          detail: hotels.some((hotel) => hotel.amountCNY != null)
            ? "目录包含参考价；入住日期库存仍由渠道页复核"
            : "目录已返回；该接口未给出指定入住日期价格"
        }]
      };
    } catch (error) {
      return { hotels: [], diagnostics: [{ provider: this.name, status: "failed", detail: error.message }] };
    }
  }
}

export function listingFromOneBoundRow(row, capturedAt = isoNow()) {
  return listingFromRow(row, capturedAt);
}

function listingFromRow(row, capturedAt) {
  if (!row || typeof row !== "object") return null;
  const name = String(row.title || row.name || row.hotel_name || "").trim();
  if (name.length < 2) return null;
  const amountCNY = parseCNY(row.price);
  return {
    providerHotelID: String(row.num_iid || row.hotel_id || row.id || "").trim(),
    provider: "ctrip",
    source: "onebound-ctrip",
    name,
    address: String(row.address || "").trim(),
    starRating: finiteNumber(row.star),
    guestRating: finiteNumber(row.score || row.rating),
    imageURL: absoluteURL(row.pic_url || row.image),
    bookingURL: absoluteURL(row.detail_url || row.url),
    amenities: [],
    tags: ["携程目录"],
    amountCNY,
    unit: "perNight",
    kind: amountCNY == null ? "checkOnProvider" : "indicative",
    capturedAt,
    note: amountCNY == null
      ? "万邦携程目录；当前接口未按入住日期返回数字价格，请在携程页面核价"
      : "万邦携程目录参考价；未绑定入住日期，房型、库存与结算价请在携程页面复核"
  };
}

function catalogQuery(request) {
  const explicit = String(process.env.ONEBOUND_HOTEL_QUERY || "").trim();
  if (explicit) return explicit.replaceAll("{destination}", cleanCity(request.destination));
  const anchor = Array.isArray(request.anchors) ? String(request.anchors[0] || "").trim() : "";
  return anchor || `${cleanCity(request.destination)} 酒店`;
}

function cleanCity(value) {
  return String(value || "").trim().replace(/市$/, "");
}

function absoluteURL(value) {
  if (!value) return null;
  try {
    const text = String(value).startsWith("//") ? `https:${value}` : String(value);
    const url = new URL(text);
    return ["http:", "https:"].includes(url.protocol) ? url.toString() : null;
  } catch { return null; }
}

function finiteNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function oneBoundStatus(code) {
  switch (String(code)) {
  case "4004":
  case "4005": return "authentication_failed";
  case "4008":
  case "4013": return "rate_limited";
  case "4016": return "insufficient_balance";
  default: return "failed";
  }
}
