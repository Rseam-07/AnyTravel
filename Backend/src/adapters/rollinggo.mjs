import {
  catalogHotelFromObject,
  parseMCPPayload,
  quoteForRequestedHotel
} from "../lib/rollinggo-parser.mjs";
import { isoNow } from "../lib/normalize.mjs";

const MAX_CANDIDATE_QUERIES = 12;

export class RollingGoAdapter {
  name = "rollinggo";

  async discover(request) {
    const apiKey = process.env.ROLLINGGO_API_KEY;
    if (!apiKey) return { hotels: [], diagnostics: [{ provider: this.name, status: "disabled" }] };
    const stayNights = Math.max(daysBetween(request.checkIn, request.checkOut), 1);
    const capturedAt = isoNow();
    try {
      const adultCount = Math.min(Math.max(Number(request.adults || 2), 1), 8);
      const requestedSize = Math.min(Math.max(Number(request.size || 20), 1), 20);
      const querySpecs = [{
        originQuery: `查找${request.destination}适合${adultCount}人入住的酒店、民宿和公寓，比较${stayNights}晚实时价格`,
        place: request.destination,
        placeType: "城市",
        size: requestedSize
      }];
      for (const anchor of (request.anchors || []).slice(0, 3)) {
        querySpecs.push({
          originQuery: `查找靠近${request.destination}${anchor}、适合${adultCount}人入住的酒店和民宿，比较${stayNights}晚实时价格`,
          place: anchor,
          placeType: "景点",
          size: Math.min(requestedSize, 10)
        });
      }
      const settled = await Promise.allSettled(querySpecs.map((spec, index) => this.#callSearch({
        apiKey,
        requestID: Date.now() + index,
        argumentsValue: {
          ...spec,
          checkInParam: {
            checkInDate: request.checkIn,
            stayNights,
            adultCount
          }
        }
      })));
      const seen = new Set();
      const payloads = settled
        .filter((result) => result.status === "fulfilled")
        .map((result) => result.value);
      const failedCount = settled.length - payloads.length;
      const hotels = collectHotelObjects(payloads)
        .map((hotel) => catalogHotelFromObject(hotel, stayNights, capturedAt))
        .filter(Boolean)
        .map((hotel) => ({ ...hotel, provider: this.name, source: this.name }))
        .filter((hotel) => {
          const key = `${hotel.name}|${hotel.latitude.toFixed(4)}|${hotel.longitude.toFixed(4)}`;
          if (seen.has(key)) return false;
          seen.add(key);
          return true;
        })
        .slice(0, 40);
      return {
        hotels,
        diagnostics: [{
          provider: this.name,
          status: hotels.length ? (failedCount ? "partial" : "ok") : "no_matching_quotes",
          queryCount: querySpecs.length,
          failedCount,
          resultCount: hotels.length,
          capturedAt
        }]
      };
    } catch (error) {
      return { hotels: [], diagnostics: [{ provider: this.name, status: "failed", detail: error.message }] };
    }
  }

  async search(request) {
    const apiKey = process.env.ROLLINGGO_API_KEY;
    if (!apiKey) return { quotes: [], diagnostics: [{ provider: this.name, status: "disabled" }] };

    const stayNights = Math.max(daysBetween(request.checkIn, request.checkOut), 1);
    const candidates = request.hotels.slice(0, MAX_CANDIDATE_QUERIES);
    const settled = await Promise.allSettled(
      candidates.map((hotel, index) => this.#searchCandidate({
        hotel,
        request,
        stayNights,
        apiKey,
        requestID: Date.now() + index
      }))
    );

    const capturedAt = isoNow();
    const quotes = [];
    let resultCount = 0;
    let failedCount = 0;

    for (let index = 0; index < settled.length; index += 1) {
      const result = settled[index];
      if (result.status === "rejected") {
        failedCount += 1;
        continue;
      }
      resultCount += result.value.hotelObjects.length;
      const quote = quoteForRequestedHotel(
        result.value.hotelObjects,
        candidates[index],
        stayNights,
        capturedAt
      );
      if (quote) quotes.push(quote);
    }

    const status = failedCount === candidates.length ? "failed" : "ok";
    return {
      quotes,
      diagnostics: [{
        provider: this.name,
        status,
        queryCount: candidates.length,
        failedCount,
        resultCount,
        matchedCount: quotes.length,
        capturedAt
      }]
    };
  }

  async #searchCandidate({ hotel, request, stayNights, apiKey, requestID }) {
    const payload = await this.#callSearch({
      apiKey,
      requestID,
      argumentsValue: {
        originQuery: `查找${hotel.name}，${request.adults}人，${stayNights}晚`,
        place: hotel.name,
        placeType: "酒店",
        checkInParam: {
          checkInDate: request.checkIn,
          stayNights,
          adultCount: Math.min(Math.max(Number(request.adults || 2), 1), 8)
        },
        size: 3
      }
    });
    return { hotelObjects: collectHotelObjects(payload) };
  }

  async #callSearch({ apiKey, requestID, argumentsValue }) {
    const body = {
      jsonrpc: "2.0",
      method: "tools/call",
      params: {
        name: "searchHotels",
        arguments: argumentsValue
      },
      id: requestID
    };

    const response = await fetch(process.env.ROLLINGGO_ENDPOINT || "https://mcp.rollinggo.cn/mcp", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        accept: "application/json, text/event-stream",
        authorization: `Bearer ${apiKey}`
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(22_000)
    });

    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return parseMCPPayload(await response.text());
  }
}

function collectHotelObjects(value, output = []) {
  if (Array.isArray(value)) {
    for (const item of value) collectHotelObjects(item, output);
  } else if (value && typeof value === "object") {
    const hasName = ["name", "hotelName", "nameCn", "hotel_name"].some((key) => value[key]);
    const hasPrice = ["displayPrice", "minPrice", "price", "lowestPrice", "totalPrice"].some((key) => value[key] != null);
    const hasLocation = ["latitude", "lat", "hotelLat", "hotelLatitude"].some((key) => value[key] != null)
      && ["longitude", "lng", "lon", "hotelLng", "hotelLongitude"].some((key) => value[key] != null);
    const hasHotelMetadata = ["address", "hotelAddress", "brand", "starRating", "amenities"].some((key) => value[key] != null);
    if (hasName && (hasPrice || hasLocation || hasHotelMetadata)) output.push(value);
    for (const nested of Object.values(value)) collectHotelObjects(nested, output);
  }
  return output;
}

function daysBetween(start, end) {
  return Math.round((Date.parse(`${end}T00:00:00Z`) - Date.parse(`${start}T00:00:00Z`)) / 86_400_000);
}
