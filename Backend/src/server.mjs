import http from "node:http";
import { AMapError, searchAMapPlaces } from "./amap-service.mjs";
import { AssistantError, interpretAssistantRequest } from "./assistant-service.mjs";
import { GeocodeError, geocodeCity } from "./geocode-service.mjs";
import { OverpassError, searchPlacesAround } from "./overpass-service.mjs";
import {
  RequestError,
  searchAccommodationCatalog,
  searchAccommodationQuotes,
  searchTransportOptions
} from "./quote-service.mjs";
import { QunarTicketError, searchQunarTicketQuotes } from "./qunar-ticket-service.mjs";

const port = Number(process.env.PORT || 8787);
const host = process.env.HOST || "127.0.0.1";
const rateBuckets = new Map();

const server = http.createServer(async (request, response) => {
  setSecurityHeaders(response);
  if (request.method === "OPTIONS") {
    response.writeHead(204).end();
    return;
  }

  try {
    enforceRateLimit(request);
    if (request.method === "GET" && request.url === "/health") {
      sendJSON(response, 200, {
        status: "ok",
        service: "anytravel-companion",
        assistant: process.env.ZAI_API_KEY ? "configured" : "disabled",
        amap: process.env.AMAP_API_KEY ? "configured" : "disabled",
        oneBoundCtrip: process.env.ONEBOUND_API_KEY && process.env.ONEBOUND_API_SECRET ? "configured" : "disabled",
        ctripSession: process.env.CTRIP_SCRAPER_ENABLED === "true" ? "configured" : "disabled",
        ctripFlights: (process.env.CTRIP_FLIGHT_SCRAPER_ENABLED ?? process.env.CTRIP_SCRAPER_ENABLED) === "true"
          ? "configured"
          : "disabled",
        tongchengSession: process.env.TONGCHENG_SCRAPER_ENABLED === "true" ? "configured" : "disabled",
        elongOpenAPI: process.env.ELONG_USER && process.env.ELONG_APP_KEY && process.env.ELONG_SECRET_KEY
          ? "configured"
          : "disabled",
        qunarTickets: "public",
        time: new Date().toISOString()
      });
      return;
    }
    if (request.method === "POST" && request.url === "/v1/assistant/interpret") {
      const body = await readJSON(request);
      sendJSON(response, 200, await interpretAssistantRequest(body));
      return;
    }
    if (request.method === "POST" && request.url === "/v1/places/search") {
      const body = await readJSON(request);
      sendJSON(response, 200, await searchAMapPlaces(body));
      return;
    }
    if (request.method === "POST" && request.url === "/v1/places/poi") {
      const body = await readJSON(request);
      sendJSON(response, 200, await searchPlacesAround(body));
      return;
    }
    if (request.method === "POST" && request.url === "/v1/places/geocode") {
      const body = await readJSON(request);
      sendJSON(response, 200, await geocodeCity(body));
      return;
    }
    if (request.method === "POST" && request.url === "/v1/quotes/accommodations") {
      const body = await readJSON(request);
      sendJSON(response, 200, await searchAccommodationQuotes(body));
      return;
    }
    if (request.method === "POST" && request.url === "/v1/accommodations/search") {
      const body = await readJSON(request);
      sendJSON(response, 200, await searchAccommodationCatalog(body));
      return;
    }
    if (request.method === "POST" && request.url === "/v1/quotes/transport") {
      const body = await readJSON(request);
      sendJSON(response, 200, await searchTransportOptions(body));
      return;
    }
    if (request.method === "POST" && request.url === "/v1/quotes/tickets") {
      const body = await readJSON(request);
      sendJSON(response, 200, await searchQunarTicketQuotes(body));
      return;
    }
    sendJSON(response, 404, { error: "not_found" });
  } catch (error) {
    const status = error instanceof RequestError || error instanceof QunarTicketError
      ? 400
      : error instanceof AssistantError
        ? error.status
        : error instanceof AMapError
          ? error.status
        : error instanceof OverpassError ? 400
        : error instanceof GeocodeError ? 400
        : error.code === "RATE_LIMIT" ? 429 : 500;
    sendJSON(response, status, {
      error: error instanceof AssistantError || error instanceof AMapError || error instanceof OverpassError || error instanceof GeocodeError
        ? error.code
        : status === 500 ? "internal_error" : error.message,
      message: error instanceof AssistantError || error instanceof AMapError || error instanceof OverpassError || error instanceof GeocodeError ? error.message : undefined
    });
  }
});

server.listen(port, host, () => {
  process.stdout.write(`AnyTravel pricing node listening on http://${host}:${port}\n`);
});

function setSecurityHeaders(response) {
  response.setHeader("content-type", "application/json; charset=utf-8");
  response.setHeader("cache-control", "no-store");
  response.setHeader("x-content-type-options", "nosniff");
  response.setHeader("access-control-allow-origin", "*");
  response.setHeader("access-control-allow-headers", "content-type");
  response.setHeader("access-control-allow-methods", "GET, POST, OPTIONS");
}

function enforceRateLimit(request) {
  const ip = request.socket.remoteAddress || "unknown";
  const now = Date.now();
  const bucket = rateBuckets.get(ip) || { startsAt: now, count: 0 };
  if (now - bucket.startsAt >= 60_000) {
    bucket.startsAt = now;
    bucket.count = 0;
  }
  bucket.count += 1;
  rateBuckets.set(ip, bucket);
  if (bucket.count > 30) {
    const error = new Error("rate_limit");
    error.code = "RATE_LIMIT";
    throw error;
  }
}

async function readJSON(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 256_000) throw new RequestError("body_too_large");
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString("utf8")); }
  catch { throw new RequestError("invalid_json"); }
}

function sendJSON(response, status, body) {
  response.writeHead(status);
  response.end(JSON.stringify(body));
}
