import { isoNow } from "./lib/normalize.mjs";
import { networkUserAgent } from "./network-identity.mjs";

const DEFAULT_ENDPOINT = "https://overpass-api.de/api/interpreter";
const MAX_RADIUS_M = 60_000;
const MAX_RESULTS = 250;
const CACHE_TTL_MS = 60 * 60 * 1000;
const cache = new Map();

const RAW_LIMIT = 250;
// osm.ch mirrors a Europe-only extract; keep it last as a shape-only fallback.
const MIRRORS = [
  process.env.OVERPASS_ENDPOINT || "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
  "https://overpass.osm.ch/api/interpreter"
].filter((endpoint, index, all) => all.indexOf(endpoint) === index);

const CATEGORY_TAGS = `
  nwr["tourism"~"^(attraction|museum|gallery|zoo|theme_park|aquarium|viewpoint|artwork|observation_tower|walking|boat_rental)$"](around:RADIUS,CENTER);
  nwr["historic"](around:RADIUS,CENTER);
  nwr["leisure"="park"](around:RADIUS,CENTER);
  nwr["leisure"="garden"](around:RADIUS,CENTER);
  nwr["amenity"="restaurant"](around:RADIUS,CENTER);
  nwr["amenity"="cafe"](around:RADIUS,CENTER);
  nwr["amenity"="fast_food"](around:RADIUS,CENTER);
  nwr["amenity"="bar"](around:RADIUS,CENTER);
  nwr["amenity"="pub"](around:RADIUS,CENTER);
  nwr["amenity"="nightclub"](around:RADIUS,CENTER);
  nwr["amenity"="theatre"](around:RADIUS,CENTER);
  nwr["amenity"="cinema"](around:RADIUS,CENTER);
`;

export class OverpassError extends Error {
  constructor(code, message) {
    super(code);
    this.code = code;
    this.message = message;
  }
}

export async function searchPlacesAround(body) {
  const latitude = Number(body?.latitude);
  const longitude = Number(body?.longitude);
  const radius = Math.min(Math.max(Number(body?.radius || 15_000), 1_000), MAX_RADIUS_M);
  const limit = Math.min(Math.max(Number(body?.limit || 120), 20), MAX_RESULTS);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    throw new OverpassError("invalid_request", "需要 latitude 与 longitude");
  }
  const center = `${latitude.toFixed(5)},${longitude.toFixed(5)}`;
  const cacheKey = `${center}|${radius}|${limit}`;
  const cached = cache.get(cacheKey);
  if (cached && cached.expiresAt > Date.now()) {
    if (cached.negative) {
      throw new OverpassError("provider_failed", "地图 POI 源暂时不可用（已缓存，稍后自动恢复）");
    }
    return { ...cached.value, cached: true };
  }
  // Fetch a wide raw set (Overpass returns by element id, not by category),
  // then curate: museums/historic/nature first, restaurants capped.
  const rawLimit = RAW_LIMIT;
  const query = `[out:json][timeout:30];(${CATEGORY_TAGS.replaceAll("RADIUS", String(radius)).replaceAll("CENTER", center)});out center ${rawLimit};`;
  let lastError = null;
  for (let attempt = 0; attempt < 2; attempt++) {
    for (const endpoint of MIRRORS) {
      try {
        const url = new URL(endpoint);
        url.searchParams.set("data", query);
        const response = await fetch(url, {
          headers: { "user-agent": networkUserAgent },
          signal: AbortSignal.timeout(9_000)
        });
        if (!response.ok) {
          lastError = new OverpassError("provider_failed", `Overpass 返回 ${response.status}`);
          continue;
        }
        const payload = await response.json();
        const capturedAt = isoNow();
        const normalized = (payload.elements || [])
          .map((element) => normalizeElement(element, capturedAt))
          .filter(Boolean);
        const curated = curate(normalized, limit);
        if (curated.length === 0) {
          throw new OverpassError("no_matching_places", `中心点附近没有找到可落地的去处（半径 ${Math.round(radius / 1000)} 公里）`);
        }
        const value = { places: curated, capturedAt };
        cache.set(cacheKey, { value, expiresAt: Date.now() + CACHE_TTL_MS });
        return value;
      } catch (error) {
        lastError = error;
      }
    }
    if (attempt === 0) {
      await new Promise((resolve) => setTimeout(resolve, 1_200));
    }
  }
  cache.set(cacheKey, { expiresAt: Date.now() + 90_000, negative: true });
  throw lastError ?? new OverpassError("provider_failed", "没有可用的地图 POI 数据源");
}

function curate(places, limit) {
  const caps = { food: Math.min(Math.round(limit / 4), 30), night: 8, nature: 24, culture: 40, gardens: 60, family: 20 };
  const buckets = new Map();
  for (const place of places) {
    if (nameQuality(place.name) < 0) continue; // skip chain hotels & generic lots
    const bucket = buckets.get(place.interest) ?? [];
    bucket.push(place);
    buckets.set(place.interest, bucket);
  }
  const ordered = ["culture", "gardens", "nature", "family", "night", "food"];
  const out = [];
  for (const interest of ordered) {
    const bucket = (buckets.get(interest) ?? [])
      .sort((a, b) => nameQuality(b.name) - nameQuality(a.name))
      .slice(0, caps[interest] ?? 20);
    out.push(...bucket);
  }
  return out.slice(0, limit);
}

function nameQuality(name) {
  const text = String(name ?? "");
  if (/宾馆|酒店|快捷|旅馆|招待所|民宿|公寓|宿舍|寓|旅舍|大厦|写字楼|地产|汽车|加油站|银行|超市|便利店|小区|新村|花园城|广场南|地铁站|公交|停车场/.test(text)) return -100;
  // English-only names without a known theme tend to be noisy imports.
  const chinese = (text.match(/[\u4e00-\u9fff]/g) ?? []).length;
  const english = (text.match(/[a-zA-Z]/g) ?? []).length;
  let score = chinese * 2;
  if (/馆|园|寺|塔|桥|古镇|老街|宫|楼|庙|阁|遗迹|祠|碑|墓/.test(text)) score += 8;
  if (/博物馆|美术馆|科技馆|纪念馆|展览/.test(text)) score += 6;
  if (/公园|湖|山|湿地|森林|步道|岛|湾/.test(text)) score += 4;
  if (/夜市|演出|剧场|剧院|夜景/.test(text)) score += 3;
  if (english > chinese * 3 && chinese === 0) score -= 4;
  return score;
}

export function normalizeElement(element, capturedAt) {
  const tags = element.tags || {};
  const name = String(tags["name:zh"] || tags["name"] || "").trim();
  if (name.length < 2) return null;
  const latitude = element.lat ?? element.center?.lat;
  const longitude = element.lon ?? element.center?.lon;
  if (typeof latitude !== "number" || typeof longitude !== "number") return null;
  const interest = classifyInterest(tags);
  const street = tags["addr:street"] ? `${tags["addr:street"]}${tags["addr:housenumber"] ? tags["addr:housenumber"] : ""}` : "";
  return {
    id: `osm-${element.type}-${element.id}`,
    name,
    address: street || null,
    latitude,
    longitude,
    interest,
    source: "OpenStreetMap · Overpass",
    opening: tags.opening_hours || null,
    rating: null,
    capturedAt
  };
}

function classifyInterest(tags) {
  const tourism = tags.tourism || "";
  const amenity = tags.amenity || "";
  const leisure = tags.leisure || "";
  const historic = tags.historic || "";
  const name = String(tags.name || "");
  if (/restaurant|cafe|fast_food|bar|pub|food|餐|面|菜|茶/.test(`${amenity} ${name}`)) return "food";
  if (/museum|gallery|art|馆|美术|博物/.test(`${tourism} ${name}`)) return "culture";
  if (/zoo|theme_park|aquarium|亲子|游乐|科技馆|游乐园|动物/.test(`${tourism} ${name}`)) return "family";
  if (/夜|夜市|灯|演出|live|nightclub|cinema|theatre/.test(`${amenity} ${tourism} ${name}`)) return "night";
  if (leisure === "park" || /公园|湖|山|湿地|森林|步道/.test(name)) return "nature";
  if (leisure === "garden" || /园|寺|塔|桥|古镇|街|宫|楼|庙|阁|遗迹/.test(`${historic} ${name}`)) return "gardens";
  return "gardens";
}
