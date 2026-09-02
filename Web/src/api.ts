// AnyTravel Web API layer.
// Browser never holds platform secrets: prices and plans go through the
// companion backend when configured. DeepSeek chat may run browser-direct with
// the user's own key (stored locally only); Nominatim / Open-Meteo / OSRM are
// open services used for search, weather and route geometry.

import type { ChannelStatus, Coord, ProviderIssue, WeatherDay } from "./types";

export const DEFAULT_BACKEND_URL = "http://127.0.0.1:8787/";
export const DEEPSEEK_BASE_URL = "https://api.deepseek.com";

const settingsKey = "anytravel-web:settings";

export interface WebSettings {
  backendURL: string;
  deepseekKey: string;
  deepseekModel: string;
}

export function loadSettings(): WebSettings {
  try {
    const raw = localStorage.getItem(settingsKey);
    if (raw) return { ...defaultSettings(), ...JSON.parse(raw) };
  } catch {
    /* ignore */
  }
  return defaultSettings();
}

export function defaultSettings(): WebSettings {
  return {
    backendURL: DEFAULT_BACKEND_URL,
    deepseekKey: import.meta.env.VITE_DEEPSEEK_API_KEY || "",
    deepseekModel: "deepseek-chat"
  };
}

export function saveSettings(settings: WebSettings) {
  localStorage.setItem(settingsKey, JSON.stringify(settings));
}

// ---------- companion backend ----------

async function backendFetch<T>(baseURL: string, path: string, body?: unknown): Promise<T> {
  const url = new URL(path, baseURL.endsWith("/") ? baseURL : baseURL + "/");
  const response = await fetch(url, {
    method: body === undefined ? "GET" : "POST",
    headers: body === undefined ? undefined : { "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  if (!response.ok) {
    const text = await response.text().catch(() => "");
    throw new Error(`节点返回 ${response.status}：${text.slice(0, 200)}`);
  }
  return (await response.json()) as T;
}

export interface BackendCatalogHotel {
  providerHotelID: string;
  providerHotelIDs?: Record<string, string>;
  provider?: string;
  source?: string;
  sources?: string[];
  name: string;
  brand?: string;
  address?: string;
  latitude?: number | null;
  longitude?: number | null;
  starRating?: number | null;
  guestRating?: number | null;
  description?: string;
  imageURL?: string;
  amenities: string[];
  tags: string[];
  amountCNY?: number | null;
  unit?: string;
  kind?: string;
  capturedAt?: string;
  note?: string;
  offers?: BackendAccommodationOffer[];
}

export interface BackendAccommodationOffer {
  provider: string;
  source?: string;
  amountCNY?: number | null;
  totalAmountCNY?: number | null;
  unit?: string;
  kind?: string;
  capturedAt?: string;
  bookingURL?: string;
  note?: string;
  roomName?: string;
  bedType?: string;
  mealPlan?: string;
  cancellationPolicy?: string;
  taxesIncluded?: boolean;
  availability?: string;
}

export interface BackendCatalogResponse {
  hotels: BackendCatalogHotel[];
  diagnostics: { provider: string; status: string; detail?: string }[];
  capturedAt: string;
  cached: boolean;
}

export interface BackendTransportOption {
  provider: string;
  source?: string;
  mode: string;
  direction?: string;
  serviceNumber?: string;
  originName?: string;
  destinationName?: string;
  departureTime?: string;
  arrivalTime?: string;
  durationMinutes?: number | null;
  amountCNY?: number | null;
  unit?: string;
  kind?: string;
  capturedAt?: string;
  bookingURL?: string;
  note?: string;
  fareName?: string;
  availability?: string;
  stops?: string;
  offers?: {
    provider: string;
    source?: string;
    amountCNY?: number | null;
    kind?: string;
    fareName?: string;
    availability?: string;
    bookingURL?: string;
    capturedAt?: string;
    note?: string;
  }[];
}

export interface BackendTransportResponse {
  options: BackendTransportOption[];
  diagnostics: { provider: string; status: string; detail?: string }[];
  capturedAt: string;
  cached: boolean;
}

export interface BackendTicketResponse {
  quotes: { attractionID: string; name: string; amountCNY?: number | null; capturedAt?: string; bookingURL?: string; note?: string }[];
  diagnostics: { provider: string; status: string; detail?: string }[];
  capturedAt: string;
}

export function providerDisplayName(provider: string): string {
  switch (provider) {
    case "rollinggo": return "道旅 RollingGo";
    case "ctrip": return "携程";
    case "ctrip-flight": return "携程航班";
    case "onebound-ctrip": return "万邦携程目录";
    case "elong-open-api": return "艺龙开放平台";
    case "qunar": return "去哪儿";
    case "tongcheng":
    case "ly": return "同程旅行";
    case "trip.com":
    case "tripcom": return "Trip.com";
    case "railway12306":
    case "12306": return "铁路 12306";
    case "budget": return "预算预留";
    case "estimate": return "本地估算";
    default: return provider;
  }
}

export function mapProviderIssue(issue: { provider: string; status: string; detail?: string }): ProviderIssue {
  return { provider: issue.provider, providerTitle: providerDisplayName(issue.provider), status: issue.status, detail: issue.detail };
}

export async function fetchAccommodationCatalog(
  baseURL: string,
  request: { destination: string; checkIn?: string; checkOut?: string; adults: number; rooms: number; size: number; anchors: string[] }
): Promise<BackendCatalogResponse> {
  return backendFetch<BackendCatalogResponse>(baseURL, "v1/accommodations/search", request);
}

export async function fetchTransport(
  baseURL: string,
  request: { origin: string; destination: string; departureDate?: string; returnDate?: string; adults: number; modes: string[] }
): Promise<BackendTransportResponse> {
  return backendFetch<BackendTransportResponse>(baseURL, "v1/quotes/transport", request);
}

export async function fetchTickets(
  baseURL: string,
  request: { destination: string; visitDate?: string; attractions: { id: string; name: string; address?: string }[] }
): Promise<BackendTicketResponse> {
  return backendFetch<BackendTicketResponse>(baseURL, "v1/quotes/tickets", request);
}

export async function fetchHealth(baseURL: string): Promise<Record<string, string>> {
  try {
    return await backendFetch<Record<string, string>>(baseURL, "health");
  } catch {
    return {};
  }
}

export interface BackendPOI {
  id: string;
  name: string;
  address?: string | null;
  latitude: number;
  longitude: number;
  interest: string;
  source: string;
  opening?: string | null;
  rating?: number | null;
}

export async function fetchPlacesAround(
  baseURL: string,
  request: { latitude: number; longitude: number; radius?: number; limit?: number }
): Promise<BackendPOI[]> {
  const response = await backendFetch<{ places: BackendPOI[] }>(baseURL, "v1/places/poi", request);
  return response.places ?? [];
}

export function channelStatusFromHealth(health: Record<string, string>): ChannelStatus[] {
  const known: [string, string, string][] = [
    ["rollinggo", "rollinggo", "RollingGo 酒店"],
    ["ctripSession", "ctrip", "携程酒店（登录会话）"],
    ["ctripFlights", "ctrip-flight", "携程航班（登录会话）"],
    ["tongchengSession", "tongcheng", "同程/艺龙（登录会话）"],
    ["elongOpenAPI", "elong-open-api", "艺龙开放平台"],
    ["oneBoundCtrip", "onebound-ctrip", "万邦携程目录"],
    ["amap", "amap", "高德地点/路线"],
    ["assistant", "assistant", "伴随智能向导"],
    ["qunarTickets", "qunar", "去哪儿门票"]
  ];
  return known.map(([key, name, label]) => {
    const value = health[key];
    if (value === "configured") return { name, status: "configured" as const, detail: label };
    if (value === "public") return { name, status: "configured" as const, detail: label + "（公开源）" };
    return { name, status: "disabled" as const, detail: label + "（未配置）" };
  });
}

// ---------- DeepSeek chat (browser-direct, user-owned key) ----------

export interface ChatMessage {
  role: "system" | "user" | "assistant";
  content: string;
}

export async function deepseekChat(
  settings: WebSettings,
  messages: ChatMessage[],
  onDelta?: (text: string) => void
): Promise<string> {
  const key = settings.deepseekKey.trim();
  if (!key) throw new Error("还没有配置 DeepSeek API Key。");

  // Streaming path: JSONL lines with `data:` prefixes.
  const response = await fetch(`${DEEPSEEK_BASE_URL}/chat/completions`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${key}` },
    body: JSON.stringify({ model: settings.deepseekModel, messages, stream: onDelta !== undefined })
  });
  if (!response.ok) {
    const text = await response.text().catch(() => "");
    throw new Error(`DeepSeek 返回 ${response.status}：${text.slice(0, 160)}`);
  }
  if (onDelta === undefined || !response.body) {
    const payload = await response.json();
    return payload.choices?.[0]?.message?.content ?? "";
  }
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let full = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed.startsWith("data:")) continue;
      const data = trimmed.slice(5).trim();
      if (data === "[DONE]") continue;
      try {
        const payload = JSON.parse(data);
        const delta = payload.choices?.[0]?.delta?.content ?? "";
        if (delta) {
          full += delta;
          onDelta(full);
        }
      } catch {
        /* skip malformed line */
      }
    }
  }
  return full;
}

// ---------- open services ----------

const NOMINATIM_HEADERS = { "User-Agent": "AnyTravel-Web/0.1 (travel planning demo)" };

export interface NominatimPlace {
  name: string;
  display_name: string;
  latitude: number;
  longitude: number;
  type?: string;
  addresstype?: string;
  class?: string;
}

export async function nominatimSearch(
  baseURL: string,
  query: string,
  limit = 8
): Promise<NominatimPlace[]> {
  // Preferred path: through the companion node (sets an identifying User-Agent
  // which browsers cannot send). Falls back to a direct request.
  try {
    return await backendFetch<{ places: NominatimPlace[] }>(baseURL, "v1/places/geocode", {
      query,
      limit
    }).then((payload) => payload.places ?? []);
  } catch {
    // Direct fallback for when the node is unreachable.
    const url = new URL("https://nominatim.openstreetmap.org/search");
    url.searchParams.set("q", query);
    url.searchParams.set("format", "jsonv2");
    url.searchParams.set("limit", String(limit));
    url.searchParams.set("accept-language", "zh-CN");
    const response = await fetch(url, { headers: NOMINATIM_HEADERS });
    if (!response.ok) throw new Error(`OSM 搜索返回 ${response.status}`);
    const rows = (await response.json()) as Array<Record<string, unknown>>;
    return rows.map((row) => ({
      name: String(row.name ?? ""),
      display_name: String(row.display_name ?? ""),
      latitude: Number(row.lat),
      longitude: Number(row.lon),
      type: String(row.type ?? ""),
      addresstype: String(row.addresstype ?? ""),
      class: String(row.class ?? "")
    }));
  }
}

export interface WeatherForecast {
  days: WeatherDay[];
}

const WMO: Record<number, { symbol: string; label: string; indoor: boolean }> = {
  0: { symbol: "☀️", label: "晴", indoor: false },
  1: { symbol: "🌤️", label: "大致晴", indoor: false },
  2: { symbol: "⛅", label: "多云", indoor: false },
  3: { symbol: "☁️", label: "阴", indoor: false },
  45: { symbol: "🌫️", label: "雾", indoor: true },
  48: { symbol: "🌫️", label: "雾凇", indoor: true },
  51: { symbol: "🌦️", label: "毛毛雨", indoor: true },
  61: { symbol: "🌧️", label: "小雨", indoor: true },
  63: { symbol: "🌧️", label: "中雨", indoor: true },
  65: { symbol: "🌧️", label: "大雨", indoor: true },
  80: { symbol: "🌦️", label: "阵雨", indoor: true },
  95: { symbol: "⛈️", label: "雷雨", indoor: true }
};

export async function weatherForecast(coordinate: Coord, days = 10): Promise<WeatherForecast> {
  const url = new URL("https://api.open-meteo.com/v1/forecast");
  url.searchParams.set("latitude", String(coordinate.lat));
  url.searchParams.set("longitude", String(coordinate.lng));
  url.searchParams.set(
    "daily",
    "weathercode,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
  );
  url.searchParams.set("timezone", "Asia/Shanghai");
  url.searchParams.set("forecast_days", String(days));
  const response = await fetch(url);
  if (!response.ok) throw new Error(`天气服务返回 ${response.status}`);
  const payload = await response.json();
  const daily = payload.daily ?? {};
  const daysOut: WeatherDay[] = (daily.time ?? []).map((date: string, index: number) => ({
    date,
    code: daily.weathercode?.[index] ?? 0,
    maxTemp: daily.temperature_2m_max?.[index] ?? 0,
    minTemp: daily.temperature_2m_min?.[index] ?? 0,
    precipitationProbability: daily.precipitation_probability_max?.[index] ?? 0
  }));
  return { days: daysOut };
}

export function weatherMeta(day: WeatherDay) {
  return WMO[day.code] ?? { symbol: "🌡️", label: "天气变化", indoor: false };
}

// ---------- OSRM route geometry (driving/walking, open server) ----------

export interface RouteResult {
  distanceMeters: number;
  durationMinutes: number;
  geometry: [number, number][]; // [lng, lat]
}

export async function osrmRoute(waypoints: Coord[], mode: "driving" | "walking"): Promise<RouteResult | null> {
  if (waypoints.length < 2) return null;
  const path = waypoints.map((p) => `${p.lng.toFixed(6)},${p.lat.toFixed(6)}`).join(";");
  const url = `https://router.project-osrm.org/route/v1/${mode}/${path}?overview=full&geometries=geojson`;
  try {
    const response = await fetch(url);
    if (!response.ok) return null;
    const payload = await response.json();
    const route = payload.routes?.[0];
    if (!route) return null;
    return {
      distanceMeters: route.distance,
      durationMinutes: Math.round(route.duration / 60),
      geometry: route.geometry?.coordinates ?? []
    };
  } catch {
    return null;
  }
}
