import http from "node:http";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import { serveWeb } from "./web-host.mjs";
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

export function createApp({ env = process.env, webRoot = fileURLToPath(new URL("../../Web/dist", import.meta.url)) } = {}) {
const rateBuckets = new Map();
const server = http.createServer(async (request, response) => {
  setSecurityHeaders(request, response, env);
  if (request.method === "OPTIONS") {
    response.writeHead(204).end();
    return;
  }

  try {
    if (request.url?.startsWith("/v1/")) enforceRateLimit(request, rateBuckets, env);
    if (request.method === "GET" && request.url === "/health") {
      sendJSON(response, 200, {
        status: "ok",
        service: "anytravel-companion",
        schemaVersion: 1,
        rollinggo: env.ROLLINGGO_API_KEY ? "configured" : "disabled",
        railway12306: "public",
        fliggyFlights: "public",
        assistant: env.DEEPSEEK_API_KEY || env.ZAI_API_KEY ? "configured" : "disabled",
        amap: env.AMAP_API_KEY ? "configured" : "disabled",
        oneBoundCtrip: env.ONEBOUND_API_KEY && env.ONEBOUND_API_SECRET ? "configured" : "disabled",
        ctripSession: env.CTRIP_SCRAPER_ENABLED === "true" ? "configured" : "disabled",
        ctripFlights: (env.CTRIP_FLIGHT_SCRAPER_ENABLED ?? env.CTRIP_SCRAPER_ENABLED) === "true"
          ? "configured"
          : "disabled",
        tongchengSession: env.TONGCHENG_SCRAPER_ENABLED === "true" ? "configured" : "disabled",
        elongOpenAPI: env.ELONG_USER && env.ELONG_APP_KEY && env.ELONG_SECRET_KEY
          ? "configured"
          : "disabled",
        accorOfficial: "public",
        hiltonOfficial: "public",
        qunarTickets: "public",
        time: new Date().toISOString()
      });
      return;
    }
    if (request.method === "POST" && request.url === "/v1/assistant/interpret") {
      const body = await readJSON(request);
      sendJSON(response, 200, await interpretAssistantRequest(body, { env }));
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
    if (await serveWeb(request, response, webRoot)) return;
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
    if (status === 429) response.setHeader("retry-after", "60");
    sendJSON(response, status, {
      error: error instanceof AssistantError || error instanceof AMapError || error instanceof OverpassError || error instanceof GeocodeError
        ? error.code
        : status === 500 ? "internal_error" : error.message,
      message: error instanceof AssistantError || error instanceof AMapError || error instanceof OverpassError || error instanceof GeocodeError ? error.message : undefined
    });
  }
});
server.requestTimeout = 60_000;
server.headersTimeout = 15_000;
return server;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.PORT || 8787), host = process.env.HOST || "127.0.0.1";
  createApp().listen(port, host, () => {
    process.stdout.write(`AnyTravel listening on http://${host}:${port}\n`);
  });
}

function setSecurityHeaders(request, response, env) {
  response.setHeader("content-type", "application/json; charset=utf-8");
  response.setHeader("cache-control", "no-store");
  response.setHeader("x-content-type-options", "nosniff");
  response.setHeader("referrer-policy", "strict-origin-when-cross-origin");
  const origins = String(env.CORS_ALLOW_ORIGINS || "").split(",").map(value => value.trim()).filter(Boolean);
  if (request.headers.origin && origins.includes(request.headers.origin)) {
    response.setHeader("access-control-allow-origin", request.headers.origin);
    response.setHeader("vary", "Origin");
  }
  response.setHeader("access-control-allow-headers", "content-type");
  response.setHeader("access-control-allow-methods", "GET, POST, OPTIONS");
}

function enforceRateLimit(request, rateBuckets, env) {
  const forwarded = env.TRUST_PROXY === "true" ? String(request.headers["x-forwarded-for"] || "").split(",")[0].trim() : "";
  const ip = forwarded || request.socket.remoteAddress || "unknown";
  const now = Date.now();
  for (const [key, entry] of rateBuckets) if (now - entry.startsAt >= 60_000) rateBuckets.delete(key);
  if (!rateBuckets.has(ip) && rateBuckets.size >= 5_000) {
    const error = new Error("rate_limit"); error.code = "RATE_LIMIT"; throw error;
  }
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
