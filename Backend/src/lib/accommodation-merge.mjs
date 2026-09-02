import { isoNow, parseCNY } from "./normalize.mjs";

const lodgingWords = /酒店|宾馆|旅馆|客栈|民宿|公寓酒店|服务公寓|青年旅舍|青旅|度假村/g;

export function mergeAccommodationCatalogResults(listings, limit = 60) {
  const entities = [];
  for (const rawListing of listings) {
    const listing = normalizeCatalogListing(rawListing);
    if (!listing) continue;
    const existing = entities.find((candidate) => isSameAccommodation(candidate, listing));
    if (existing) mergeListingIntoEntity(existing, listing);
    else entities.push(entityFromListing(listing));
  }

  return entities
    .map(finalizeEntity)
    .sort((lhs, rhs) => {
      const lhsPriced = lhs.offers.some((offer) => offer.amountCNY != null) ? 1 : 0;
      const rhsPriced = rhs.offers.some((offer) => offer.amountCNY != null) ? 1 : 0;
      return rhsPriced - lhsPriced
        || rhs.sources.length - lhs.sources.length
        || (bestAmount(lhs.offers) ?? Number.MAX_SAFE_INTEGER)
          - (bestAmount(rhs.offers) ?? Number.MAX_SAFE_INTEGER)
        || lhs.name.localeCompare(rhs.name, "zh-CN");
    })
    .slice(0, Math.max(1, Number(limit) || 60));
}

export function deduplicateAccommodationQuotes(quotes) {
  const result = new Map();
  for (const rawQuote of quotes) {
    const quote = normalizeOffer(rawQuote);
    if (!quote || !rawQuote.hotelID && !rawQuote.hotelName) continue;
    const hotelKey = rawQuote.hotelID || normalizeAccommodationName(rawQuote.hotelName);
    const key = [
      hotelKey,
      quote.provider,
      quote.unit,
      normalizeText(quote.roomName),
      normalizeText(quote.mealPlan),
      normalizeText(quote.cancellationPolicy)
    ].join("|");
    const previous = result.get(key);
    if (!previous || preferOffer(quote, previous)) {
      result.set(key, { ...rawQuote, ...quote });
    }
  }
  return [...result.values()].sort((lhs, rhs) => {
    const lhsAmount = Number.isFinite(lhs.amountCNY) ? lhs.amountCNY : Number.MAX_SAFE_INTEGER;
    const rhsAmount = Number.isFinite(rhs.amountCNY) ? rhs.amountCNY : Number.MAX_SAFE_INTEGER;
    return lhsAmount - rhsAmount || String(lhs.provider).localeCompare(String(rhs.provider));
  });
}

export function normalizeCatalogListing(rawListing) {
  if (!rawListing || typeof rawListing !== "object") return null;
  const name = String(rawListing.name || rawListing.hotelName || rawListing.title || "").trim();
  if (name.length < 2) return null;
  const provider = String(rawListing.provider || "unknown").trim().toLowerCase();
  const source = String(rawListing.source || provider).trim().toLowerCase();
  const latitude = finiteCoordinate(rawListing.latitude ?? rawListing.lat, -90, 90);
  const longitude = finiteCoordinate(rawListing.longitude ?? rawListing.lng ?? rawListing.lon, -180, 180);
  const amountCNY = parseCNY(rawListing.amountCNY ?? rawListing.price);
  const capturedAt = validISODate(rawListing.capturedAt) || isoNow();
  const bookingURL = safeHTTPURL(rawListing.bookingURL || rawListing.detailURL || rawListing.detail_url);
  const offer = normalizeOffer({
    provider,
    source,
    amountCNY,
    unit: rawListing.unit || "perNight",
    kind: rawListing.kind || (amountCNY == null ? "checkOnProvider" : "live"),
    capturedAt,
    bookingURL,
    note: rawListing.note || "价格、房型与库存请在渠道结算页复核",
    roomName: rawListing.roomName,
    bedType: rawListing.bedType,
    mealPlan: rawListing.mealPlan,
    cancellationPolicy: rawListing.cancellationPolicy,
    taxesIncluded: rawListing.taxesIncluded,
    availability: rawListing.availability,
    totalAmountCNY: rawListing.totalAmountCNY
  });
  return {
    providerHotelID: String(rawListing.providerHotelID || rawListing.hotelID || rawListing.num_iid || "").trim(),
    provider,
    source,
    name,
    brand: optionalText(rawListing.brand),
    address: String(rawListing.address || "").trim(),
    latitude,
    longitude,
    starRating: finiteNumber(rawListing.starRating ?? rawListing.star),
    guestRating: finiteNumber(rawListing.guestRating ?? rawListing.rating ?? rawListing.score),
    description: optionalText(rawListing.description),
    imageURL: safeHTTPURL(rawListing.imageURL || rawListing.pic_url || rawListing.picURL),
    amenities: uniqueStrings(rawListing.amenities),
    tags: uniqueStrings(rawListing.tags),
    offer
  };
}

export function normalizeAccommodationName(value = "") {
  return String(value)
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[（）()【】\[\]·•・\s_\-—]/g, "")
    .replace(lodgingWords, "")
    .replace(/(?:有限)?公司/g, "")
    .trim();
}

export function isSameAccommodation(lhs, rhs) {
  const lhsName = normalizeAccommodationName(lhs.name);
  const rhsName = normalizeAccommodationName(rhs.name);
  if (!lhsName || !rhsName) return false;
  const lhsBranch = branchQualifier(lhs.name);
  const rhsBranch = branchQualifier(rhs.name);
  if (lhsBranch && rhsBranch && lhsBranch !== rhsBranch) return false;
  if (lhsName === rhsName) return true;

  const nameSimilarity = diceSimilarity(lhsName, rhsName);
  const distance = coordinateDistanceMeters(lhs, rhs);
  if (distance != null && distance <= 320 && nameSimilarity >= 0.55) return true;

  const lhsAddress = normalizeAddress(lhs.address);
  const rhsAddress = normalizeAddress(rhs.address);
  const addressSimilarity = lhsAddress && rhsAddress ? diceSimilarity(lhsAddress, rhsAddress) : 0;
  return nameSimilarity >= 0.76 && addressSimilarity >= 0.48;
}

function entityFromListing(listing) {
  return {
    ...listing,
    offers: listing.offer ? [listing.offer] : [],
    sources: [listing.source],
    providerHotelIDs: listing.providerHotelID ? { [listing.source]: listing.providerHotelID } : {}
  };
}

function mergeListingIntoEntity(entity, listing) {
  if (listing.name.length > entity.name.length && normalizeAccommodationName(listing.name).length >= normalizeAccommodationName(entity.name).length) {
    entity.name = listing.name;
  }
  if ((!entity.address || listing.address.length > entity.address.length) && listing.address) entity.address = listing.address;
  if (entity.latitude == null && listing.latitude != null) entity.latitude = listing.latitude;
  if (entity.longitude == null && listing.longitude != null) entity.longitude = listing.longitude;
  entity.brand ||= listing.brand;
  entity.starRating = richerNumber(entity.starRating, listing.starRating);
  entity.guestRating = richerNumber(entity.guestRating, listing.guestRating);
  entity.description ||= listing.description;
  entity.imageURL ||= listing.imageURL;
  entity.amenities = uniqueStrings([...(entity.amenities || []), ...(listing.amenities || [])]);
  entity.tags = uniqueStrings([...(entity.tags || []), ...(listing.tags || [])]);
  if (!entity.sources.includes(listing.source)) entity.sources.push(listing.source);
  if (listing.providerHotelID) entity.providerHotelIDs[listing.source] = listing.providerHotelID;
  if (listing.offer) mergeOffer(entity.offers, listing.offer);
}

function finalizeEntity(entity) {
  const offers = entity.offers.sort((lhs, rhs) => {
    const lhsAmount = lhs.amountCNY ?? Number.MAX_SAFE_INTEGER;
    const rhsAmount = rhs.amountCNY ?? Number.MAX_SAFE_INTEGER;
    return lhsAmount - rhsAmount || lhs.provider.localeCompare(rhs.provider);
  });
  const primaryOffer = offers[0] || null;
  const providerHotelID = Object.values(entity.providerHotelIDs)[0]
    || `catalog-${normalizeAccommodationName(entity.name).slice(0, 48)}`;
  return {
    entityKey: canonicalEntityKey(entity),
    providerHotelID,
    providerHotelIDs: entity.providerHotelIDs,
    provider: primaryOffer?.provider || entity.provider,
    sources: entity.sources.sort(),
    name: entity.name,
    brand: entity.brand ?? null,
    address: entity.address,
    latitude: entity.latitude,
    longitude: entity.longitude,
    starRating: entity.starRating ?? null,
    guestRating: entity.guestRating ?? null,
    description: entity.description ?? null,
    imageURL: entity.imageURL ?? null,
    bookingURL: primaryOffer?.bookingURL ?? null,
    amenities: entity.amenities || [],
    tags: entity.tags || [],
    amountCNY: primaryOffer?.amountCNY ?? null,
    unit: primaryOffer?.unit || "perNight",
    kind: primaryOffer?.kind || "checkOnProvider",
    capturedAt: primaryOffer?.capturedAt || isoNow(),
    note: primaryOffer?.note || "到渠道查看当前房型和价格",
    offers
  };
}

function mergeOffer(offers, offer) {
  const key = offerIdentity(offer);
  const index = offers.findIndex((candidate) => offerIdentity(candidate) === key);
  if (index < 0) offers.push(offer);
  else if (preferOffer(offer, offers[index])) offers[index] = offer;
}

function normalizeOffer(rawOffer) {
  if (!rawOffer || typeof rawOffer !== "object") return null;
  const provider = String(rawOffer.provider || "unknown").trim().toLowerCase();
  const amountCNY = parseCNY(rawOffer.amountCNY);
  return {
    provider,
    source: String(rawOffer.source || provider).trim().toLowerCase(),
    amountCNY,
    totalAmountCNY: parseCNY(rawOffer.totalAmountCNY),
    unit: ["perNight", "perPerson", "total"].includes(rawOffer.unit) ? rawOffer.unit : "perNight",
    kind: ["live", "indicative", "budgetEstimate", "demo", "requiresPartnerAccess", "checkOnProvider"].includes(rawOffer.kind)
      ? rawOffer.kind
      : (amountCNY == null ? "checkOnProvider" : "live"),
    capturedAt: validISODate(rawOffer.capturedAt) || isoNow(),
    bookingURL: safeHTTPURL(rawOffer.bookingURL),
    note: String(rawOffer.note || "价格、库存与退改请在结算页复核").trim(),
    roomName: optionalText(rawOffer.roomName),
    bedType: optionalText(rawOffer.bedType),
    mealPlan: optionalText(rawOffer.mealPlan),
    cancellationPolicy: optionalText(rawOffer.cancellationPolicy),
    taxesIncluded: typeof rawOffer.taxesIncluded === "boolean" ? rawOffer.taxesIncluded : null,
    availability: optionalText(rawOffer.availability)
  };
}

function offerIdentity(offer) {
  return [
    offer.provider,
    offer.unit,
    normalizeText(offer.roomName),
    normalizeText(offer.bedType),
    normalizeText(offer.mealPlan),
    normalizeText(offer.cancellationPolicy)
  ].join("|");
}

function preferOffer(candidate, previous) {
  if (candidate.amountCNY != null && previous.amountCNY == null) return true;
  if (candidate.amountCNY == null && previous.amountCNY != null) return false;
  if (candidate.amountCNY != null && previous.amountCNY != null && candidate.amountCNY !== previous.amountCNY) {
    return candidate.amountCNY < previous.amountCNY;
  }
  return Date.parse(candidate.capturedAt) > Date.parse(previous.capturedAt);
}

function canonicalEntityKey(entity) {
  const coordinate = entity.latitude != null && entity.longitude != null
    ? `${entity.latitude.toFixed(3)},${entity.longitude.toFixed(3)}`
    : normalizeAddress(entity.address).slice(0, 40);
  return `${normalizeAccommodationName(entity.name)}|${coordinate}`;
}

function coordinateDistanceMeters(lhs, rhs) {
  if (![lhs.latitude, lhs.longitude, rhs.latitude, rhs.longitude].every(Number.isFinite)) return null;
  const radians = (degrees) => degrees * Math.PI / 180;
  const deltaLatitude = radians(rhs.latitude - lhs.latitude);
  const deltaLongitude = radians(rhs.longitude - lhs.longitude);
  const latitude1 = radians(lhs.latitude);
  const latitude2 = radians(rhs.latitude);
  const a = Math.sin(deltaLatitude / 2) ** 2
    + Math.cos(latitude1) * Math.cos(latitude2) * Math.sin(deltaLongitude / 2) ** 2;
  return 6_371_000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function branchQualifier(value) {
  const text = String(value || "").normalize("NFKC");
  const parenthetical = text.match(/[（(]([^）)]{1,24})[）)]/u)?.[1];
  if (parenthetical && /店|馆|楼|院|公寓|民宿/u.test(parenthetical)) return normalizeText(parenthetical);
  const trailing = text.match(/([\p{Script=Han}A-Za-z0-9]{2,18}(?:店|馆|楼|院))$/u)?.[1];
  return trailing ? normalizeText(trailing) : "";
}

function normalizeAddress(value = "") {
  return String(value)
    .normalize("NFKC")
    .toLowerCase()
    .replace(/中国|省|自治区|特别行政区/g, "")
    .replace(/[\s,，。·•・_\-—]/g, "")
    .trim();
}

function diceSimilarity(lhs, rhs) {
  if (lhs === rhs) return 1;
  if (!lhs || !rhs) return 0;
  if (lhs.length === 1 || rhs.length === 1) return lhs === rhs ? 1 : 0;
  const lhsBigrams = bigrams(lhs);
  const rhsBigrams = bigrams(rhs);
  let intersection = 0;
  const counts = new Map();
  for (const value of lhsBigrams) counts.set(value, (counts.get(value) || 0) + 1);
  for (const value of rhsBigrams) {
    const count = counts.get(value) || 0;
    if (count > 0) {
      intersection += 1;
      counts.set(value, count - 1);
    }
  }
  return 2 * intersection / (lhsBigrams.length + rhsBigrams.length);
}

function bigrams(value) {
  const characters = [...value];
  return characters.slice(0, -1).map((character, index) => character + characters[index + 1]);
}

function normalizeText(value) {
  return String(value || "").normalize("NFKC").toLowerCase().replace(/\s+/g, "").trim();
}

function uniqueStrings(value) {
  const values = Array.isArray(value) ? value : value == null ? [] : [value];
  return [...new Set(values.map((item) => optionalText(item?.name ?? item)).filter(Boolean))].slice(0, 30);
}

function safeHTTPURL(value) {
  if (!value) return null;
  try {
    const text = String(value).startsWith("//") ? `https:${value}` : String(value);
    const url = new URL(text);
    return ["http:", "https:"].includes(url.protocol) ? url.toString() : null;
  } catch { return null; }
}

function finiteCoordinate(value, minimum, maximum) {
  const number = Number(value);
  return Number.isFinite(number) && number >= minimum && number <= maximum ? number : null;
}

function finiteNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function richerNumber(current, candidate) {
  return current == null && candidate != null ? candidate : current;
}

function optionalText(value) {
  const text = String(value ?? "").trim();
  return text || null;
}

function validISODate(value) {
  if (!value || !Number.isFinite(Date.parse(value))) return null;
  return new Date(value).toISOString();
}

function bestAmount(offers) {
  const amounts = offers.map((offer) => offer.amountCNY).filter(Number.isFinite);
  return amounts.length ? Math.min(...amounts) : null;
}
