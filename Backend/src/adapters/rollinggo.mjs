import {
  parseMCPPayload,
  quoteForRequestedHotel
} from "../lib/rollinggo-parser.mjs";
import { isoNow } from "../lib/normalize.mjs";

const MAX_CANDIDATE_QUERIES = 8;

export class RollingGoAdapter {
  name = "rollinggo";

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
    const body = {
      jsonrpc: "2.0",
      method: "tools/call",
      params: {
        name: "searchHotels",
        arguments: {
          originQuery: `查找${hotel.name}，${request.adults}人，${stayNights}晚`,
          place: hotel.name,
          placeType: "酒店",
          checkInParam: { checkInDate: request.checkIn, stayNights },
          size: 3
        }
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
    const payload = parseMCPPayload(await response.text());
    return { hotelObjects: collectHotelObjects(payload) };
  }
}

function collectHotelObjects(value, output = []) {
  if (Array.isArray(value)) {
    for (const item of value) collectHotelObjects(item, output);
  } else if (value && typeof value === "object") {
    const hasName = ["name", "hotelName", "nameCn", "hotel_name"].some((key) => value[key]);
    const hasPrice = ["displayPrice", "minPrice", "price", "lowestPrice", "totalPrice"].some((key) => value[key] != null);
    if (hasName && hasPrice) output.push(value);
    for (const nested of Object.values(value)) collectHotelObjects(nested, output);
  }
  return output;
}

function daysBetween(start, end) {
  return Math.round((Date.parse(`${end}T00:00:00Z`) - Date.parse(`${start}T00:00:00Z`)) / 86_400_000);
}
