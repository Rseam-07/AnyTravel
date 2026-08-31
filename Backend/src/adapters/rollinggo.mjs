import { isoNow, matchRequestedHotel, parseCNY } from "../lib/normalize.mjs";

export class RollingGoAdapter {
  name = "rollinggo";

  async search(request) {
    const apiKey = process.env.ROLLINGGO_API_KEY;
    if (!apiKey) return { quotes: [], diagnostics: [{ provider: this.name, status: "disabled" }] };

    const stayNights = Math.max(daysBetween(request.checkIn, request.checkOut), 1);
    const body = {
      jsonrpc: "2.0",
      method: "tools/call",
      params: {
        name: "searchHotels",
        arguments: {
          originQuery: `${request.destination}酒店，${request.adults}人，${stayNights}晚`,
          place: request.destination,
          placeType: "城市",
          checkInParam: { checkInDate: request.checkIn, stayNights },
          size: 20
        }
      },
      id: Date.now()
    };

    try {
      const response = await fetch(process.env.ROLLINGGO_ENDPOINT || "https://mcp.rollinggo.cn/mcp", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          accept: "application/json, text/event-stream",
          authorization: `Bearer ${apiKey}`
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(25_000)
      });
      const text = await response.text();
      if (!response.ok) {
        return { quotes: [], diagnostics: [{ provider: this.name, status: "failed", detail: `HTTP ${response.status}` }] };
      }
      const payload = parseMCPPayload(text);
      const hotelObjects = collectHotelObjects(payload);
      const capturedAt = isoNow();
      const quotes = hotelObjects.flatMap((hotel) => {
        const name = firstValue(hotel, ["name", "hotelName", "nameCn", "hotel_name"]);
        const amount = parseCNY(firstValue(hotel, ["displayPrice", "minPrice", "price", "lowestPrice", "totalPrice"]));
        if (!name || !amount) return [];
        const requested = matchRequestedHotel(name, request.hotels);
        if (!requested) return [];
        const bookingURL = firstValue(hotel, ["bookingUrl", "bookingURL", "url"]);
        return [{
          hotelID: requested.id,
          hotelName: requested.name,
          provider: "rollinggo",
          amountCNY: amount,
          unit: "perNight",
          kind: "live",
          capturedAt,
          bookingURL: validURL(bookingURL),
          note: "实时展示价；选定房型后仍需再次锁价确认"
        }];
      });
      return { quotes, diagnostics: [{ provider: this.name, status: "ok", resultCount: hotelObjects.length, capturedAt }] };
    } catch (error) {
      return { quotes: [], diagnostics: [{ provider: this.name, status: "failed", detail: error.message }] };
    }
  }
}

function parseMCPPayload(text) {
  const dataLines = text.split(/\r?\n/).filter((line) => line.startsWith("data:"));
  const raw = dataLines.length ? dataLines.at(-1).slice(5).trim() : text.trim();
  const outer = JSON.parse(raw);
  const content = outer?.result?.content;
  if (!Array.isArray(content)) return outer;
  const parsed = content.map((item) => {
    if (item?.type !== "text" || typeof item.text !== "string") return item;
    try { return JSON.parse(item.text); } catch { return item.text; }
  });
  return parsed;
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

function firstValue(object, keys) {
  for (const key of keys) if (object?.[key] != null) return object[key];
  return null;
}

function validURL(value) {
  try { return new URL(value).href; } catch { return null; }
}

function daysBetween(start, end) {
  return Math.round((Date.parse(`${end}T00:00:00Z`) - Date.parse(`${start}T00:00:00Z`)) / 86_400_000);
}
