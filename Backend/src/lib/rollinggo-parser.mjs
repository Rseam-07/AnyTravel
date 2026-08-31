import { normalizeHotelName, parseCNY } from "./normalize.mjs";

export function parseMCPPayload(text) {
  const dataLines = text.split(/\r?\n/).filter((line) => line.startsWith("data:"));
  const raw = dataLines.length ? dataLines.at(-1).slice(5).trim() : text.trim();
  const outer = JSON.parse(raw);
  const content = outer?.result?.content;
  if (!Array.isArray(content)) return outer;
  return content.map((item) => {
    if (item?.type !== "text" || typeof item.text !== "string") return item;
    try { return JSON.parse(item.text); } catch { return item.text; }
  });
}

export function quoteForRequestedHotel(hotelObjects, requestedHotel, stayNights, capturedAt) {
  const hotel = hotelObjects.find((candidate) => isStrongHotelMatch(
    firstValue(candidate, ["name", "hotelName", "nameCn", "hotel_name"]),
    requestedHotel.name
  ));
  if (!hotel) return null;

  const price = extractPrice(hotel, stayNights);
  if (!price) return null;

  return {
    hotelID: requestedHotel.id,
    hotelName: requestedHotel.name,
    provider: "rollinggo",
    amountCNY: price.amountCNY,
    unit: "perNight",
    kind: "live",
    capturedAt,
    bookingURL: validURL(firstValue(hotel, ["bookingUrl", "bookingURL", "url"])),
    note: price.wasStayTotal
      ? `RollingGo实时展示价；${stayNights}晚总价已换算为每晚，选定房型后仍需锁价确认`
      : "RollingGo实时展示价；选定房型后仍需锁价确认"
  };
}

export function extractPrice(hotel, stayNights) {
  const structured = hotel?.price;
  if (structured && typeof structured === "object") {
    const amount = parseCNY(
      firstValue(structured, ["lowestPrice", "totalPrice", "displayPrice", "minPrice", "price", "message"])
    );
    if (!amount) return null;
    const message = String(structured.message || "");
    const wasStayTotal = /总价/.test(message) || structured.lowestPrice != null || structured.totalPrice != null;
    return {
      amountCNY: wasStayTotal ? Math.max(Math.round(amount / Math.max(stayNights, 1)), 1) : amount,
      wasStayTotal
    };
  }

  const amount = parseCNY(firstValue(hotel, ["displayPrice", "minPrice", "price", "lowestPrice", "totalPrice"]));
  return amount ? { amountCNY: amount, wasStayTotal: false } : null;
}

function isStrongHotelMatch(candidateName, requestedName) {
  const candidate = normalizeHotelName(candidateName);
  const requested = normalizeHotelName(requestedName);
  if (!candidate || !requested) return false;
  if (candidate === requested) return true;
  const shorterLength = Math.min(candidate.length, requested.length);
  return shorterLength >= 4 && (candidate.includes(requested) || requested.includes(candidate));
}

function firstValue(object, keys) {
  for (const key of keys) if (object?.[key] != null) return object[key];
  return null;
}

function validURL(value) {
  try { return new URL(value).href; } catch { return null; }
}
