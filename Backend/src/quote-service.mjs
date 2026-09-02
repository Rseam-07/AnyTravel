import { CtripAdapter } from "./adapters/ctrip.mjs";
import { CtripFlightAdapter } from "./adapters/ctrip-flight.mjs";
import { ElongHotelAdapter } from "./adapters/elong.mjs";
import { OneBoundCtripAdapter } from "./adapters/onebound-ctrip.mjs";
import { RollingGoAdapter } from "./adapters/rollinggo.mjs";
import { Railway12306Adapter } from "./adapters/railway12306.mjs";
import { TongchengAdapter } from "./adapters/tongcheng.mjs";
import {
  deduplicateAccommodationQuotes,
  mergeAccommodationCatalogResults
} from "./lib/accommodation-merge.mjs";
import { mergeTransportOptions } from "./lib/transport-merge.mjs";

const cache = new Map();
const rollingGoAdapter = new RollingGoAdapter();
const ctripAdapter = new CtripAdapter();
const tongchengAdapter = new TongchengAdapter();
const adapters = [rollingGoAdapter, ctripAdapter, tongchengAdapter];
const catalogAdapters = [
  rollingGoAdapter,
  ctripAdapter,
  tongchengAdapter,
  new OneBoundCtripAdapter(),
  new ElongHotelAdapter()
];
const transportAdapters = [new Railway12306Adapter(), new CtripFlightAdapter()];

export async function searchAccommodationCatalog(request) {
  validateCatalogRequest(request);
  const normalizedRequest = {
    ...request,
    adults: Math.min(Math.max(Number(request.adults || 1), 1), 8),
    rooms: Math.min(Math.max(Number(request.rooms || 1), 1), 4),
    size: Math.min(Math.max(Number(request.size || 20), 1), 20),
    anchors: [...new Set(
      (Array.isArray(request.anchors) ? request.anchors : [])
        .map((value) => String(value || "").trim().slice(0, 120))
        .filter(Boolean)
    )].slice(0, 3)
  };
  const key = `catalog:${JSON.stringify(normalizedRequest)}`;
  const cached = cache.get(key);
  if (cached && cached.expiresAt > Date.now()) return { ...cached.value, cached: true };
  const settled = await Promise.allSettled(
    catalogAdapters.map((adapter) => adapter.discover(normalizedRequest))
  );
  const listings = [];
  const diagnostics = [];
  for (let index = 0; index < settled.length; index += 1) {
    const result = settled[index];
    if (result.status === "fulfilled") {
      listings.push(...result.value.hotels);
      diagnostics.push(...result.value.diagnostics);
    } else {
      diagnostics.push({
        provider: catalogAdapters[index]?.name || "unknown",
        status: "failed",
        detail: result.reason?.message || String(result.reason)
      });
    }
  }
  const value = {
    hotels: mergeAccommodationCatalogResults(listings, 60),
    diagnostics,
    capturedAt: new Date().toISOString(),
    cached: false
  };
  const ttl = Math.max(Number(process.env.CATALOG_CACHE_TTL_SECONDS || 900), 60) * 1000;
  cache.set(key, { value, expiresAt: Date.now() + ttl });
  return value;
}

export async function searchAccommodationQuotes(request) {
  validateRequest(request);
  const key = JSON.stringify(request);
  const cached = cache.get(key);
  if (cached && cached.expiresAt > Date.now()) return { ...cached.value, cached: true };

  const settled = await Promise.allSettled(adapters.map((adapter) => adapter.search(request)));
  const quotes = [];
  const diagnostics = [];
  for (const result of settled) {
    if (result.status === "fulfilled") {
      quotes.push(...result.value.quotes);
      diagnostics.push(...result.value.diagnostics);
    } else {
      diagnostics.push({ provider: "unknown", status: "failed", detail: result.reason?.message || String(result.reason) });
    }
  }
  const value = {
    quotes: deduplicateAccommodationQuotes(quotes),
    diagnostics,
    capturedAt: new Date().toISOString(),
    cached: false
  };
  const ttl = Math.max(Number(process.env.CACHE_TTL_SECONDS || 600), 30) * 1000;
  cache.set(key, { value, expiresAt: Date.now() + ttl });
  return value;
}

export async function searchTransportOptions(request) {
  validateTransportRequest(request);
  const key = `transport:${JSON.stringify(request)}`;
  const cached = cache.get(key);
  if (cached && cached.expiresAt > Date.now()) return { ...cached.value, cached: true };

  const settled = await Promise.allSettled(transportAdapters.map((adapter) => adapter.search(request)));
  const options = [];
  const diagnostics = [];
  for (const result of settled) {
    if (result.status === "fulfilled") {
      options.push(...result.value.options);
      diagnostics.push(...result.value.diagnostics);
    } else {
      diagnostics.push({ provider: "unknown", status: "failed", detail: result.reason?.message || String(result.reason) });
    }
  }
  const value = {
    options: mergeTransportOptions(options),
    diagnostics,
    capturedAt: new Date().toISOString(),
    cached: false
  };
  const ttl = Math.max(Number(process.env.TRANSPORT_CACHE_TTL_SECONDS || 300), 30) * 1000;
  cache.set(key, { value, expiresAt: Date.now() + ttl });
  return value;
}

function validateRequest(request) {
  if (!request || typeof request !== "object") throw new RequestError("JSON body is required");
  for (const key of ["destination", "checkIn", "checkOut"]) {
    if (!request[key] || typeof request[key] !== "string") throw new RequestError(`${key} is required`);
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(request.checkIn) || !/^\d{4}-\d{2}-\d{2}$/.test(request.checkOut)) {
    throw new RequestError("Dates must use YYYY-MM-DD");
  }
  if (Date.parse(request.checkOut) <= Date.parse(request.checkIn)) throw new RequestError("checkOut must be after checkIn");
  if (!Array.isArray(request.hotels) || request.hotels.length === 0 || request.hotels.length > 30) {
    throw new RequestError("hotels must contain 1 to 30 candidates");
  }
  for (const hotel of request.hotels) {
    if (!hotel.id || !hotel.name) throw new RequestError("Every hotel needs id and name");
  }
}

function validateCatalogRequest(request) {
  if (!request || typeof request !== "object") throw new RequestError("JSON body is required");
  for (const key of ["destination", "checkIn", "checkOut"]) {
    if (!request[key] || typeof request[key] !== "string") throw new RequestError(`${key} is required`);
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(request.checkIn) || !/^\d{4}-\d{2}-\d{2}$/.test(request.checkOut)) {
    throw new RequestError("Dates must use YYYY-MM-DD");
  }
  if (Date.parse(request.checkOut) <= Date.parse(request.checkIn)) throw new RequestError("checkOut must be after checkIn");
  if (request.anchors != null && !Array.isArray(request.anchors)) {
    throw new RequestError("anchors must be an array when provided");
  }
}

function validateTransportRequest(request) {
  if (!request || typeof request !== "object") throw new RequestError("JSON body is required");
  for (const key of ["origin", "destination", "departureDate"]) {
    if (!request[key] || typeof request[key] !== "string") throw new RequestError(`${key} is required`);
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(request.departureDate)) {
    throw new RequestError("departureDate must use YYYY-MM-DD");
  }
  if (request.returnDate && !/^\d{4}-\d{2}-\d{2}$/.test(request.returnDate)) {
    throw new RequestError("returnDate must use YYYY-MM-DD");
  }
  if (request.returnDate && Date.parse(request.returnDate) < Date.parse(request.departureDate)) {
    throw new RequestError("returnDate must not be before departureDate");
  }
  if (!Array.isArray(request.modes) || request.modes.some((mode) => !["train", "flight"].includes(mode))) {
    throw new RequestError("modes must contain train or flight");
  }
  request.adults = Math.min(Math.max(Number(request.adults || 1), 1), 8);
}

export class RequestError extends Error {}
