import { CtripAdapter } from "./adapters/ctrip.mjs";
import { RollingGoAdapter } from "./adapters/rollinggo.mjs";
import { Railway12306Adapter } from "./adapters/railway12306.mjs";

const cache = new Map();
const adapters = [new RollingGoAdapter(), new CtripAdapter()];
const transportAdapters = [new Railway12306Adapter()];

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
    quotes: deduplicateQuotes(quotes),
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
    options,
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
  if (!Array.isArray(request.modes) || request.modes.some((mode) => !["train", "flight"].includes(mode))) {
    throw new RequestError("modes must contain train or flight");
  }
  request.adults = Math.min(Math.max(Number(request.adults || 1), 1), 8);
}

function deduplicateQuotes(quotes) {
  const map = new Map();
  for (const quote of quotes) {
    const key = `${quote.hotelID}|${quote.provider}|${quote.unit}`;
    const previous = map.get(key);
    if (!previous || quote.amountCNY < previous.amountCNY) map.set(key, quote);
  }
  return [...map.values()].sort((a, b) => a.amountCNY - b.amountCNY);
}

export class RequestError extends Error {}
