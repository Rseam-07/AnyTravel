export async function searchAMapPlaces(request, options = {}) {
  const env = options.env || process.env;
  const fetchImpl = options.fetchImpl || globalThis.fetch;
  const now = options.now || (() => new Date());
  const apiKey = String(env.AMAP_API_KEY || "").trim();
  if (!apiKey) throw new AMapError("amap_not_configured", 503, "高德 Web 服务尚未配置");
  const clean = validateRequest(request);
  const baseURL = normalizeBaseURL(env.AMAP_BASE_URL || "https://restapi.amap.com");
  const endpoint = new URL("v3/place/text", baseURL);
  endpoint.searchParams.set("keywords", clean.keywords);
  if (clean.city) {
    endpoint.searchParams.set("city", clean.city);
    endpoint.searchParams.set("citylimit", "true");
  }
  endpoint.searchParams.set("offset", String(clean.limit));
  endpoint.searchParams.set("page", "1");
  endpoint.searchParams.set("extensions", "base");
  endpoint.searchParams.set("key", apiKey);

  let response;
  try {
    response = await fetchImpl(endpoint, { signal: AbortSignal.timeout(15_000) });
  } catch {
    throw new AMapError("amap_network_error", 502, "高德地点服务暂时没有回应");
  }
  if (!response.ok) throw new AMapError("amap_upstream_error", 502, `高德地点服务返回 ${response.status}`);

  let payload;
  try { payload = await response.json(); }
  catch { throw new AMapError("amap_invalid_response", 502, "高德地点服务返回了无法读取的内容"); }
  if (payload.status !== "1") {
    const code = String(payload.infocode || "unknown");
    const platformMismatch = code === "10009";
    throw new AMapError(
      platformMismatch ? "amap_key_platform_mismatch" : "amap_upstream_rejected",
      platformMismatch ? 422 : 502,
      platformMismatch ? "当前 Key 不是高德 Web 服务 Key" : `高德服务拒绝请求（${code}）`
    );
  }

  const places = (Array.isArray(payload.pois) ? payload.pois : [])
    .map(normalizePOI)
    .filter(Boolean)
    .slice(0, clean.limit);
  return {
    places,
    source: "AMap Web Service",
    sourceCRS: "GCJ-02",
    outputCRS: "WGS84 approximate inverse",
    capturedAt: now().toISOString()
  };
}

export function normalizePOI(poi) {
  const [longitude, latitude] = String(poi?.location || "").split(",").map(Number);
  if (!Number.isFinite(longitude) || !Number.isFinite(latitude)) return null;
  const wgs84 = gcj02ToWGS84(longitude, latitude);
  return {
    id: String(poi.id || ""),
    name: String(poi.name || "").trim(),
    address: normalizeAddress(poi.address),
    type: String(poi.type || "").trim(),
    coordinate: { latitude: wgs84.latitude, longitude: wgs84.longitude },
    sourceCoordinate: { latitude, longitude },
    sourceCoordinateSystem: "GCJ-02"
  };
}

export function gcj02ToWGS84(longitude, latitude) {
  if (outsideChina(longitude, latitude)) return { longitude, latitude };
  let estimateLongitude = longitude;
  let estimateLatitude = latitude;
  for (let index = 0; index < 3; index += 1) {
    const shifted = wgs84ToGCJ02(estimateLongitude, estimateLatitude);
    estimateLongitude -= shifted.longitude - longitude;
    estimateLatitude -= shifted.latitude - latitude;
  }
  return { longitude: estimateLongitude, latitude: estimateLatitude };
}

function wgs84ToGCJ02(longitude, latitude) {
  if (outsideChina(longitude, latitude)) return { longitude, latitude };
  const axis = 6378245.0;
  const eccentricity = 0.00669342162296594323;
  let latitudeDelta = transformLatitude(longitude - 105, latitude - 35);
  let longitudeDelta = transformLongitude(longitude - 105, latitude - 35);
  const radians = latitude / 180 * Math.PI;
  let magic = Math.sin(radians);
  magic = 1 - eccentricity * magic * magic;
  const sqrtMagic = Math.sqrt(magic);
  latitudeDelta = latitudeDelta * 180 / ((axis * (1 - eccentricity)) / (magic * sqrtMagic) * Math.PI);
  longitudeDelta = longitudeDelta * 180 / (axis / sqrtMagic * Math.cos(radians) * Math.PI);
  return { longitude: longitude + longitudeDelta, latitude: latitude + latitudeDelta };
}

function transformLatitude(x, y) {
  let result = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * Math.sqrt(Math.abs(x));
  result += (20 * Math.sin(6 * x * Math.PI) + 20 * Math.sin(2 * x * Math.PI)) * 2 / 3;
  result += (20 * Math.sin(y * Math.PI) + 40 * Math.sin(y / 3 * Math.PI)) * 2 / 3;
  result += (160 * Math.sin(y / 12 * Math.PI) + 320 * Math.sin(y * Math.PI / 30)) * 2 / 3;
  return result;
}

function transformLongitude(x, y) {
  let result = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * Math.sqrt(Math.abs(x));
  result += (20 * Math.sin(6 * x * Math.PI) + 20 * Math.sin(2 * x * Math.PI)) * 2 / 3;
  result += (20 * Math.sin(x * Math.PI) + 40 * Math.sin(x / 3 * Math.PI)) * 2 / 3;
  result += (150 * Math.sin(x / 12 * Math.PI) + 300 * Math.sin(x / 30 * Math.PI)) * 2 / 3;
  return result;
}

function outsideChina(longitude, latitude) {
  return longitude < 72.004 || longitude > 137.8347 || latitude < 0.8293 || latitude > 55.8271;
}

function normalizeAddress(value) {
  if (Array.isArray(value)) return value.join("");
  const address = String(value || "").trim();
  return address || "地址以高德详情为准";
}

function validateRequest(request) {
  if (!request || typeof request !== "object") throw new AMapError("invalid_request", 400, "JSON body is required");
  const keywords = String(request.keywords || "").trim();
  if (!keywords) throw new AMapError("invalid_request", 400, "keywords is required");
  return {
    keywords: keywords.slice(0, 120),
    city: String(request.city || "").trim().slice(0, 80),
    limit: Math.min(Math.max(Math.round(Number(request.limit || 12)), 1), 20)
  };
}

function normalizeBaseURL(value) {
  let url;
  try { url = new URL(String(value)); }
  catch { throw new AMapError("amap_not_configured", 503, "高德服务地址无效"); }
  if (url.protocol !== "https:") throw new AMapError("amap_not_configured", 503, "高德服务必须使用 HTTPS");
  if (!url.pathname.endsWith("/")) url.pathname += "/";
  return url;
}

export class AMapError extends Error {
  constructor(code, status, message) {
    super(message);
    this.code = code;
    this.status = status;
  }
}
