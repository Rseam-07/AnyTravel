import { AMapError, searchAMapPlaces } from "../src/amap-service.mjs";
import { AssistantError, interpretAssistantRequest } from "../src/assistant-service.mjs";
import { GeocodeError, geocodeCity } from "../src/geocode-service.mjs";
import { OverpassError, searchPlacesAround } from "../src/overpass-service.mjs";
import { RequestError, searchAccommodationCatalog, searchAccommodationQuotes, searchTransportOptions } from "../src/quote-service.mjs";
import { QunarTicketError, searchQunarTicketQuotes } from "../src/qunar-ticket-service.mjs";
export { HandbookRoom } from "./handbook-room.mjs";

const handlers = {
  "/v1/assistant/interpret": (body, env) => interpretAssistantRequest(body, { env }),
  "/v1/places/search": (body, env) => searchAMapPlaces(body, { env }),
  "/v1/places/poi": searchPlacesAround,
  "/v1/places/geocode": geocodeCity,
  "/v1/quotes/accommodations": searchAccommodationQuotes,
  "/v1/accommodations/search": searchAccommodationCatalog,
  "/v1/quotes/transport": searchTransportOptions,
  "/v1/quotes/tickets": searchQunarTicketQuotes
};

export default {
  async fetch(request, env) {
    const origin = request.headers.get("origin"), url = new URL(request.url);
    const origins = String(env.CORS_ALLOW_ORIGINS || "").split(",").map(v => v.trim());
    const headers = new Headers({ "cache-control": "no-store", "x-content-type-options": "nosniff", "referrer-policy": "no-referrer", "vary": "Origin" });
    if (origin && origins.includes(origin)) headers.set("access-control-allow-origin", origin);
    headers.set("access-control-allow-methods", "GET, POST, OPTIONS");
    headers.set("access-control-allow-headers", "content-type, authorization");
    const json = (body, status = 200) => Response.json(body, { status, headers });
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers });
    if (origin && !origins.includes(origin)) return json({ error: "origin_not_allowed" }, 403);
    if (request.method === "GET" && url.pathname === "/health") return json({
      status: "ok", service: "anytravel-companion", schemaVersion: 1, runtime: "cloudflare-workers",
      rollinggo: env.ROLLINGGO_API_KEY ? "configured" : "disabled", railway12306: "public", fliggyFlights: "public",
      assistant: env.AI || env.DEEPSEEK_API_KEY || env.ZAI_API_KEY ? "configured" : "local", assistantFallback: "local-intent-v1",
      assistantModel: env.AI ? env.WORKERS_AI_MODEL || "@cf/qwen/qwen3-30b-a3b-fp8" : undefined,
      amap: env.AMAP_API_KEY ? "configured" : "public", amapFallback: "OpenStreetMap",
      oneBoundCtrip: env.ONEBOUND_API_KEY && env.ONEBOUND_API_SECRET ? "configured" : "disabled",
      elongOpenAPI: env.ELONG_USER && env.ELONG_APP_KEY && env.ELONG_SECRET_KEY ? "configured" : "disabled",
      ctripSession: "disabled", ctripFlights: "disabled", tongchengSession: "disabled",
      accorOfficial: "public", hiltonOfficial: "public", qunarTickets: "public", handbookSync: env.HANDBOOKS ? "enabled" : "disabled",
      time: new Date().toISOString()
    });
    if (!url.pathname.startsWith("/v1/")) return json({ error: "not_found" }, 404);
    try {
      const limit = await env.API_RATE_LIMITER.limit({ key: request.headers.get("cf-connecting-ip") || "local" });
      if (!limit.success) { headers.set("retry-after", "60"); return json({ error: "rate_limit" }, 429); }
      if (/^\/v1\/handbooks(?:\/[\w-]+)?$/.test(url.pathname)) {
        if (!env.HANDBOOKS) return json({ error: "handbook_sync_disabled" }, 503);
        // One small, persistent database caps room count and makes concurrent
        // revision checks atomic. It sleeps when idle; no server to keep running.
        const result = await env.HANDBOOKS.get(env.HANDBOOKS.idFromName("shared-handbooks-v1")).fetch(request);
        headers.set("content-type", "application/json; charset=utf-8");
        return new Response(result.body, { status: result.status, headers });
      }
      const handler = handlers[url.pathname];
      if (!handler) return json({ error: "not_found" }, 404);
      if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
      const body = await readJSON(request, 256_000);
      return json(await handler(body, env));
    } catch (error) {
      const known = error instanceof RequestError || error instanceof QunarTicketError || error instanceof OverpassError || error instanceof GeocodeError;
      const status = error.status || (known ? 400 : 500);
      return json({ error: status === 500 ? "internal_error" : error.code || error.message,
        message: error instanceof AMapError || error instanceof AssistantError ? error.message : undefined }, status);
    }
  }
};

export async function readJSON(request, maxBytes) {
  const tooLarge = () => Object.assign(new Error("body_too_large"), { status: 413 });
  if (Number(request.headers.get("content-length")) > maxBytes) throw tooLarge();
  const reader = request.body?.getReader();
  if (!reader) throw Object.assign(new Error("invalid_json"), { status: 400 });
  const chunks = []; let size = 0;
  for (;;) {
    const { done, value } = await reader.read(); if (done) break;
    size += value.byteLength;
    if (size > maxBytes) { await reader.cancel(); throw tooLarge(); }
    chunks.push(value);
  }
  try { return JSON.parse(await new Blob(chunks).text()); }
  catch { throw Object.assign(new Error("invalid_json"), { status: 400 }); }
}
