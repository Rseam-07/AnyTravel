// Nominatim geocoding proxy. The browser may not set a descriptive User-Agent
// (forbidden header), and Nominatim's usage policy asks for one, so the node
// performs the request with an identifying UA and enforces a small delay
// between searches.

const ENDPOINT = "https://nominatim.openstreetmap.org/search";
let lastRequestAt = 0;

export async function geocodeCity(body) {
  const query = String(body?.query || "").trim();
  if (query.length < 2) throw new GeocodeError("invalid_request", "搜索词太短");
  const limit = Math.min(Math.max(Number(body?.limit || 6), 1), 10);
  const wait = Math.max(lastRequestAt + 1_100 - Date.now(), 0);
  if (wait > 0) {
    await new Promise((resolve) => setTimeout(resolve, wait));
  }
  const url = new URL(ENDPOINT);
  url.searchParams.set("q", query);
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("limit", String(limit));
  url.searchParams.set("accept-language", "zh-CN");
  try {
    const response = await fetch(url, {
      headers: { "user-agent": "AnyTravel-Companion/0.1 (travel planning)" },
      signal: AbortSignal.timeout(12_000)
    });
    lastRequestAt = Date.now();
    if (!response.ok) throw new GeocodeError("provider_failed", `OSM 地理编码返回 ${response.status}`);
    const rows = await response.json();
    return {
      places: rows.map((row) => ({
        name: row.name || (row.display_name || "").split(",")[0],
        display_name: row.display_name || "",
        latitude: Number(row.lat),
        longitude: Number(row.lon),
        type: row.type || "",
        addresstype: row.addresstype || "",
        class: row.class || ""
      }))
    };
  } catch (error) {
    if (error instanceof GeocodeError) throw error;
    throw new GeocodeError("provider_failed", error?.message || "OSM 地理编码暂时不可用");
  }
}

export class GeocodeError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}
