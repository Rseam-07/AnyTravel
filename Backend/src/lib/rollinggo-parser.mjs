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

export function catalogHotelFromObject(hotel, stayNights, capturedAt) {
  const name = String(firstValue(hotel, ["name", "hotelName", "nameCn", "hotel_name"]) || "").trim();
  const latitude = numberValue(firstValue(hotel, ["latitude", "lat", "hotelLat", "hotelLatitude"]));
  const longitude = numberValue(firstValue(hotel, ["longitude", "lng", "lon", "hotelLng", "hotelLongitude"]));
  if (!name || !Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  const price = extractPrice(hotel, stayNights);
  const amenities = arrayStrings(firstValue(hotel, ["amenities", "facilities", "facilityList", "services"]));
  const tags = arrayStrings(firstValue(hotel, ["tags", "labels", "themes"]));
  return {
    providerHotelID: String(firstValue(hotel, ["hotelId", "hotelID", "id", "hotel_id"]) || ""),
    name,
    brand: optionalString(firstValue(hotel, ["brand", "brandName", "hotelBrand"])),
    address: optionalString(firstValue(hotel, ["address", "hotelAddress", "addressCn"])) || "",
    latitude,
    longitude,
    starRating: numberValue(firstValue(hotel, ["starRating", "star", "starLevel"])),
    guestRating: numberValue(firstValue(hotel, ["rating", "guestRating", "score", "reviewScore"])),
    description: optionalString(firstValue(hotel, ["description", "summary", "introduction"])),
    imageURL: validURL(firstValue(hotel, ["imageUrl", "imageURL", "coverImage", "cover"])),
    bookingURL: validURL(firstValue(hotel, ["bookingUrl", "bookingURL", "url"])),
    amenities: amenities.slice(0, 12),
    tags: tags.slice(0, 10),
    amountCNY: price?.amountCNY ?? null,
    unit: "perNight",
    kind: price ? "live" : "checkOnProvider",
    capturedAt,
    note: price
      ? "RollingGo 实时展示价；选定房型后仍需锁价确认"
      : "RollingGo 已返回住宿资料，房价需选择房型后确认"
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
    // searchHotels defines lowestPrice/minPrice as the nightly floor. Only a
    // field or message explicitly labelled as total may be divided by nights.
    const wasStayTotal = /总价|合计/.test(message) || structured.totalPrice != null;
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

function optionalString(value) {
  const result = String(value ?? "").trim();
  return result || null;
}

function numberValue(value) {
  if (value == null || String(value).trim() === "") return null;
  const result = Number(value);
  return Number.isFinite(result) ? result : null;
}

function arrayStrings(value) {
  if (!Array.isArray(value)) return [];
  return value.map((item) => {
    if (typeof item === "string") return item.trim();
    return optionalString(item?.name ?? item?.title ?? item?.label);
  }).filter(Boolean);
}

function validURL(value) {
  try { return new URL(value).href; } catch { return null; }
}
