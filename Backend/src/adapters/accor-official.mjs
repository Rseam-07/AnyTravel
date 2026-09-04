import { isoNow, normalizeHotelName, parseCNY } from "../lib/normalize.mjs";

// Search-only values published in all.accor.com's current frontend. Deployments
// can override them if the public web configuration rotates.
const ALGOLIA_APP_ID = "TEBW21BCFZ";
const ALGOLIA_SEARCH_KEY = "1a6f0c3b77791a299d98f6b981f2715d";
const ALGOLIA_INDEX_EN = "prod_hotels_en";
const ALGOLIA_INDEX_ZH = "prod_hotels_zh";
const BFF_API_KEY = "l7xx5b9f4a053aaf43d8bc05bcc266dd8532";
const BFF_ENDPOINT = "https://api.accor.com/bff/v1/graphql";
const MAX_RATE_LOOKUPS = 10;

const HOTEL_OFFERS_QUERY = `
query HotelPageHot(
  $hotelOffersHotelId: String!, $dateIn: Date!, $dateOut: Date!,
  $nbAdults: PositiveInt!, $childrenAges: [NonNegativeInt!],
  $countryMarket: String!, $currency: String!,
  $offersSelectionFilters: OffersSelectionFilters,
  $use: BestOfferUse, $selectionStep: Int,
  $concession: BestOfferConcession, $hideMemberRate: Boolean,
  $selection: [OfferSelectionInput!]
) {
  hotelOffers(
    hotelId: $hotelOffersHotelId, dateIn: $dateIn, dateOut: $dateOut,
    nbAdults: $nbAdults, childrenAges: $childrenAges,
    countryMarket: $countryMarket, currency: $currency,
    use: $use, concession: $concession, hideMemberRate: $hideMemberRate
  ) {
    offersSelection(selectionStep: $selectionStep, filters: $offersSelectionFilters, selection: $selection) {
      offers {
        accommodation { code }
        pricing { currency main { formattedAmount amount simplifiedPolicies { cancellation { code label } } } }
        mealPlan { code label }
        rate { id label }
      }
    }
    availability { status reasons { code label } }
  }
}`;

/** Account-free Accor catalog plus public rates for the requested dates. */
export class AccorOfficialAdapter {
  name = "accor-official";

  constructor(options = {}) {
    this.fetchImpl = options.fetchImpl || globalThis.fetch;
    this.algoliaAppID = options.algoliaAppID || process.env.ACCOR_ALGOLIA_APP_ID || ALGOLIA_APP_ID;
    this.algoliaSearchKey = options.algoliaSearchKey || process.env.ACCOR_ALGOLIA_SEARCH_KEY || ALGOLIA_SEARCH_KEY;
    this.bffAPIKey = options.bffAPIKey || process.env.ACCOR_BFF_API_KEY || BFF_API_KEY;
    this.bffEndpoint = options.bffEndpoint || process.env.ACCOR_BFF_ENDPOINT || BFF_ENDPOINT;
    this.now = options.now || (() => new Date());
    this.cache = new Map();
  }

  async discover(request) {
    try {
      const hotels = await this.#listings(request);
      const pricedCount = hotels.filter((hotel) => hotel.amountCNY != null).length;
      return {
        hotels,
        diagnostics: [{
          provider: this.name,
          status: hotels.length ? "ok" : "no_visible_cards",
          resultCount: hotels.length,
          pricedCount,
          capturedAt: hotels[0]?.capturedAt || this.now().toISOString(),
          detail: pricedCount
            ? "Accor 官网已按所选入住日期返回公开房价"
            : "Accor 官网已返回酒店目录；当前日期未见可售报价"
        }]
      };
    } catch (error) {
      return { hotels: [], diagnostics: [{ provider: this.name, status: "failed", detail: error.message }] };
    }
  }

  async search(request) {
    try {
      const listings = await this.#listings({ ...request, size: Math.min(Number(request.size || 20), MAX_RATE_LOOKUPS) });
      const quotes = [];
      const matched = new Set();
      for (const listing of listings) {
        if (listing.amountCNY == null) continue;
        const candidate = strongCandidateMatch(listing.name, request.hotels || []);
        if (!candidate || matched.has(candidate.id)) continue;
        matched.add(candidate.id);
        quotes.push({
          hotelID: candidate.id,
          hotelName: candidate.name,
          provider: "official",
          source: this.name,
          amountCNY: listing.amountCNY,
          totalAmountCNY: listing.totalAmountCNY,
          unit: "perNight",
          kind: "live",
          capturedAt: listing.capturedAt,
          bookingURL: listing.bookingURL,
          note: listing.note,
          roomName: listing.roomName,
          mealPlan: listing.mealPlan,
          cancellationPolicy: listing.cancellationPolicy,
          availability: listing.availability
        });
      }
      return {
        quotes,
        diagnostics: [{
          provider: this.name,
          status: quotes.length ? "ok" : "no_matching_quotes",
          resultCount: listings.length,
          matchedCount: quotes.length,
          capturedAt: listings[0]?.capturedAt || this.now().toISOString()
        }]
      };
    } catch (error) {
      return { quotes: [], diagnostics: [{ provider: this.name, status: "failed", detail: error.message }] };
    }
  }

  async #listings(request) {
    const size = Math.min(Math.max(Number(request.size || 20), 1), MAX_RATE_LOOKUPS);
    const cacheKey = JSON.stringify({
      destination: request.destination,
      checkIn: request.checkIn,
      checkOut: request.checkOut,
      adults: request.adults,
      rooms: request.rooms,
      size
    });
    const cached = this.cache.get(cacheKey);
    if (cached?.expiresAt > Date.now()) return cached.value;

    const rows = await this.#catalog(request.destination, size);
    const capturedAt = this.now().toISOString();
    const nights = numberOfNights(request.checkIn, request.checkOut);
    const values = await Promise.all(rows.map(async (row) => {
      const rate = await this.#rate(row.objectID, request).catch(() => null);
      return listingFromAccor(row, rate, request, nights, capturedAt);
    }));
    const listings = values.filter(Boolean);
    this.cache.set(cacheKey, { value: listings, expiresAt: Date.now() + 10 * 60_000 });
    return listings;
  }

  async #catalog(destination, size) {
    const query = String(destination || "").trim();
    const index = /[\u3400-\u9fff]/u.test(query) ? ALGOLIA_INDEX_ZH : ALGOLIA_INDEX_EN;
    const endpoint = `https://${this.algoliaAppID}-dsn.algolia.net/1/indexes/${index}/query`;
    const response = await this.fetchImpl(endpoint, {
      method: "POST",
      headers: {
        "x-algolia-application-id": this.algoliaAppID,
        "x-algolia-api-key": this.algoliaSearchKey,
        "content-type": "application/json",
        origin: "https://all.accor.com",
        referer: "https://all.accor.com/"
      },
      body: JSON.stringify({
        query,
        hitsPerPage: size,
        attributesToRetrieve: [
          "objectID", "name", "brandLabel", "brand", "city", "country", "stars", "rating",
          "localization", "freeAmenities", "paidAmenities", "mediaCatalog", "medias", "description",
          "enhancedDescription", "labels", "thematics"
        ],
        filters: "status:OPEN"
      }),
      signal: AbortSignal.timeout(12_000)
    });
    if (!response.ok) throw new Error(`Accor catalog HTTP ${response.status}`);
    const payload = await response.json();
    return Array.isArray(payload?.hits) ? payload.hits : [];
  }

  async #rate(hotelID, request) {
    const response = await this.fetchImpl(this.bffEndpoint, {
      method: "POST",
      headers: {
        apikey: this.bffAPIKey,
        "app-id": "all.accor",
        "app-version": "1.39.1",
        clientid: "all.accor",
        lang: "zh",
        "content-type": "application/json",
        origin: "https://all.accor.com",
        referer: "https://all.accor.com/"
      },
      body: JSON.stringify({
        operationName: "HotelPageHot",
        query: HOTEL_OFFERS_QUERY,
        variables: {
          hotelOffersHotelId: hotelID,
          dateIn: request.checkIn,
          dateOut: request.checkOut,
          nbAdults: Math.min(Math.max(Number(request.adults || 1), 1), 8),
          childrenAges: [],
          selectionStep: 0,
          countryMarket: "CN",
          currency: "CNY",
          offersSelectionFilters: { cancellationPolicies: null, isAccessible: false, mealPlans: null },
          concession: null,
          use: "NIGHT",
          hideMemberRate: false,
          selection: []
        }
      }),
      signal: AbortSignal.timeout(12_000)
    });
    if (!response.ok) throw new Error(`Accor rate HTTP ${response.status}`);
    const payload = await response.json();
    if (payload?.errors?.length) throw new Error(String(payload.errors[0]?.message || "Accor rate error"));
    const hotelOffers = payload?.data?.hotelOffers;
    const offers = Array.isArray(hotelOffers?.offersSelection?.offers) ? hotelOffers.offersSelection.offers : [];
    const best = offers
      .filter((offer) => Number(offer?.pricing?.main?.amount) > 0)
      .sort((lhs, rhs) => lhs.pricing.main.amount - rhs.pricing.main.amount)[0] || null;
    return {
      available: hotelOffers?.availability?.status === "AVAILABLE" && best != null,
      availability: hotelOffers?.availability?.status || null,
      reason: hotelOffers?.availability?.reasons?.map((item) => item?.label).filter(Boolean).join(" · ") || null,
      offer: best
    };
  }
}

export function listingFromAccor(row, rate, request, nights, capturedAt = isoNow()) {
  const id = String(row?.objectID || "").trim();
  const name = String(row?.name || "").trim();
  if (!id || name.length < 2) return null;
  const address = row?.localization?.address || {};
  const gps = row?.localization?.gps || {};
  const totalAmountCNY = rate?.available ? parseCNY(rate.offer?.pricing?.main?.amount) : null;
  const amountCNY = totalAmountCNY == null ? null : Math.max(1, Math.round(totalAmountCNY / Math.max(nights, 1)));
  const mealPlan = optionalText(rate?.offer?.mealPlan?.label);
  return {
    providerHotelID: `accor-${id}`,
    provider: "official",
    source: "accor-official",
    name,
    brand: optionalText(row?.brandLabel || row?.brand),
    address: [address?.street || address?.line1, address?.city, address?.zipCode].filter(Boolean).join("，"),
    latitude: finiteCoordinate(gps?.lat, -90, 90),
    longitude: finiteCoordinate(gps?.lng, -180, 180),
    starRating: finiteNumber(row?.stars),
    guestRating: finiteNumber(row?.rating?.score),
    description: optionalText(row?.enhancedDescription || row?.description),
    imageURL: validHTTPURL(row?.mediaCatalog?.["1024x768"] || row?.medias?.dmUrlCrop3by2),
    amenities: uniqueStrings([...(row?.freeAmenities || []), ...(row?.paidAmenities || [])]),
    tags: uniqueStrings([...(row?.labels || []), ...(row?.thematics || [])]),
    amountCNY,
    totalAmountCNY,
    unit: "perNight",
    kind: amountCNY == null ? "checkOnProvider" : "live",
    capturedAt,
    bookingURL: accorBookingURL(id, request),
    note: amountCNY == null
      ? "前往 Accor 官网查看所选日期房型"
      : `Accor 官网所选日期公开价${mealPlan ? ` · ${mealPlan}` : ""}；结算前请复核税费与库存`,
    roomName: optionalText(rate?.offer?.accommodation?.code),
    mealPlan,
    cancellationPolicy: optionalText(rate?.offer?.pricing?.main?.simplifiedPolicies?.cancellation?.label),
    availability: amountCNY == null ? optionalText(rate?.reason || rate?.availability) : "所选日期有公开报价"
  };
}

function accorBookingURL(hotelID, request) {
  const url = new URL("https://all.accor.com/ssr/app/accor/rates");
  url.searchParams.set("hotelCode", hotelID);
  if (request?.checkIn) url.searchParams.set("checkIn", request.checkIn);
  if (request?.checkOut) url.searchParams.set("checkOut", request.checkOut);
  url.searchParams.set("numberOfRooms", String(Math.min(Math.max(Number(request?.rooms || 1), 1), 4)));
  url.searchParams.set("adults", String(Math.min(Math.max(Number(request?.adults || 1), 1), 8)));
  return url.toString();
}

function numberOfNights(checkIn, checkOut) {
  const value = Math.round((Date.parse(`${checkOut}T00:00:00Z`) - Date.parse(`${checkIn}T00:00:00Z`)) / 86_400_000);
  return Number.isFinite(value) && value > 0 ? value : 1;
}

function strongCandidateMatch(name, candidates) {
  const normalized = normalizeHotelName(name);
  if (!normalized) return null;
  return candidates.find((candidate) => {
    const wanted = normalizeHotelName(candidate?.name);
    return wanted && (normalized === wanted
      || (Math.min(normalized.length, wanted.length) >= 5
        && (normalized.includes(wanted) || wanted.includes(normalized))));
  }) || null;
}

function finiteCoordinate(value, minimum, maximum) {
  const number = Number(value);
  return Number.isFinite(number) && number >= minimum && number <= maximum ? number : null;
}

function finiteNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function validHTTPURL(value) {
  if (!value) return null;
  try {
    const url = new URL(String(value).startsWith("//") ? `https:${value}` : String(value));
    return ["http:", "https:"].includes(url.protocol) ? url.toString() : null;
  } catch { return null; }
}

function optionalText(value) {
  const text = String(value ?? "").trim();
  return text || null;
}

function uniqueStrings(values) {
  return [...new Set((Array.isArray(values) ? values : [])
    .map((item) => optionalText(item?.label ?? item?.value ?? item?.name ?? item))
    .filter(Boolean))].slice(0, 24);
}
