const endpoint = "https://piao.qunar.com/ticket/list.json";
const maximumExactFallbacks = 8;

export class QunarTicketError extends Error {
  constructor(message) {
    super(message);
    this.name = "QunarTicketError";
    this.status = 400;
  }
}

export async function searchQunarTicketQuotes(request, options = {}) {
  const fetchImpl = options.fetchImpl || globalThis.fetch;
  const now = options.now || (() => new Date());
  const clean = validateRequest(request);
  const capturedAt = now().toISOString();

  let citySights;
  try {
    citySights = await fetchSightList(clean.destination, fetchImpl);
  } catch (error) {
    return {
      quotes: [],
      diagnostics: [{ provider: "qunar", status: "failed", detail: error.message }],
      capturedAt,
      cached: false
    };
  }

  const matched = new Map();
  attachMatches(citySights, clean.attractions, matched);
  const unmatched = clean.attractions
    .filter((attraction) => !matched.has(attraction.id))
    .slice(0, maximumExactFallbacks);

  // The city list covers the most visited sights. Exact public searches fill
  // gaps without paging through an entire destination catalogue.
  const exactResults = await Promise.allSettled(
    unmatched.map((attraction) => fetchSightList(attraction.name, fetchImpl))
  );
  exactResults.forEach((result, index) => {
    if (result.status === "fulfilled") {
      attachMatches(result.value, [unmatched[index]], matched);
    }
  });

  const quotes = [...matched.values()].map(({ attraction, sight }) => makeQuote(
    attraction,
    sight,
    capturedAt,
    clean.visitDate
  ));
  return {
    quotes,
    diagnostics: [{
      provider: "qunar",
      status: quotes.length ? "ok" : "no_matching_quotes",
      resultCount: quotes.length,
      capturedAt
    }],
    capturedAt,
    cached: false
  };
}

export function matchQunarSight(sights, attraction) {
  const requested = normalizeSightName(attraction?.name);
  if (!requested || !Array.isArray(sights)) return null;
  const requestedAddress = normalizeAddress(attraction?.address);
  let best = null;
  let bestScore = 0;

  for (const sight of sights) {
    const candidate = normalizeSightName(sight?.sightName);
    if (!candidate) continue;
    let score = 0;
    if (candidate === requested) score = 100;
    else if (candidate.includes(requested) || requested.includes(candidate)) {
      const ratio = Math.min(candidate.length, requested.length) / Math.max(candidate.length, requested.length);
      if (Math.min(candidate.length, requested.length) >= 2 && ratio >= 0.55) score = 70 + ratio * 20;
    }
    const candidateAddress = normalizeAddress(sight?.address);
    if (score > 0 && requestedAddress && candidateAddress
        && (candidateAddress.includes(requestedAddress) || requestedAddress.includes(candidateAddress))) {
      score += 8;
    }
    if (score > bestScore) {
      bestScore = score;
      best = sight;
    }
  }
  return bestScore >= 70 ? best : null;
}

export function normalizeSightName(value) {
  return String(value || "")
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[（(].*?[）)]/g, "")
    .replace(/国家级|风景名胜区|风景区|旅游景区|景区|旅游区/g, "")
    .replace(/[\s·•・\-_]/g, "")
    .trim();
}

async function fetchSightList(keyword, fetchImpl) {
  const url = new URL(endpoint);
  const parameters = { keyword, region: "", from: "mpl_search_suggest", page: "1" };
  for (const [key, value] of Object.entries(parameters)) url.searchParams.set(key, value);
  const response = await fetchImpl(url, {
    headers: {
      accept: "application/json",
      referer: `https://piao.qunar.com/ticket/list_${encodeURIComponent(keyword)}.html?from=mpl_search_suggest_h`
    },
    signal: AbortSignal.timeout(15_000)
  });
  if (!response.ok) throw new Error(`去哪儿门票公开页返回 ${response.status}`);
  const payload = await response.json();
  const sights = payload?.data?.sightList;
  if (!Array.isArray(sights)) throw new Error("去哪儿门票公开页结构暂时无法识别");
  return sights;
}

function attachMatches(sights, attractions, matched) {
  for (const attraction of attractions) {
    if (matched.has(attraction.id)) continue;
    const sight = matchQunarSight(sights, attraction);
    if (!sight) continue;
    const price = Number(sight.qunarPrice);
    if (!sight.free && (!Number.isFinite(price) || price < 0)) continue;
    // Search pages often attach tours, meals or observation products to open
    // streets and landmarks. Never present those package prices as admission.
    if (!sight.free && !isLikelyTicketedAttraction(attraction)) continue;
    matched.set(attraction.id, { attraction, sight });
  }
}

export function isLikelyTicketedAttraction(attraction) {
  if (["food", "night"].includes(String(attraction?.interest || ""))) return false;
  const name = String(attraction?.name || "").normalize("NFKC");
  if (/街|路|巷|夜市|市集|书店|商场|购物中心|广场|地标|大桥|车站|机场|码头|酒店|餐厅|咖啡|东方之门|博物馆|美术馆|纪念馆|公园|湖(?:风景名胜区|景区)?$/u.test(name)) {
    return false;
  }
  return true;
}

function makeQuote(attraction, sight, capturedAt, visitDate) {
  const rawPrice = sight.free ? 0 : Number(sight.qunarPrice);
  const amountCNY = Math.max(Math.round(rawPrice), 0);
  const exactPrice = Number.isInteger(rawPrice) ? `¥${rawPrice}` : `¥${rawPrice.toFixed(1)}`;
  const dateNote = visitDate
    ? `计划日期${visitDate}的票种与库存仍需在购买页复核`
    : "适用日期、票种与库存仍需在购买页复核";
  return {
    attractionID: attraction.id,
    attractionName: attraction.name,
    provider: "qunar",
    amountCNY,
    displayPriceText: sight.free ? "免费" : `${exactPrice}/人起`,
    unit: "perPerson",
    kind: "live",
    capturedAt,
    bookingURL: `https://piao.qunar.com/ticket/detail_${encodeURIComponent(String(sight.sightId))}.html`,
    note: sight.free
      ? `去哪儿门票公开页当前标注免费；${dateNote}`
      : `去哪儿门票公开页当前展示起价${exactPrice}；${dateNote}`
  };
}

function normalizeAddress(value) {
  return String(value || "").replace(/[\s,，]/g, "").trim();
}

function validateRequest(request) {
  if (!request || typeof request !== "object") throw new QunarTicketError("JSON body is required");
  const destination = String(request.destination || "").trim();
  if (!destination) throw new QunarTicketError("destination is required");
  if (!Array.isArray(request.attractions) || request.attractions.length < 1 || request.attractions.length > 30) {
    throw new QunarTicketError("attractions must contain 1 to 30 candidates");
  }
  const attractions = request.attractions.map((attraction) => ({
    id: String(attraction?.id || "").trim(),
    name: String(attraction?.name || "").trim(),
    address: String(attraction?.address || "").trim(),
    interest: String(attraction?.interest || "").trim()
  }));
  if (attractions.some((attraction) => !attraction.id || !attraction.name)) {
    throw new QunarTicketError("Every attraction needs id and name");
  }
  const visitDate = request.visitDate == null ? null : String(request.visitDate);
  if (visitDate && !/^\d{4}-\d{2}-\d{2}$/.test(visitDate)) {
    throw new QunarTicketError("visitDate must use YYYY-MM-DD");
  }
  return { destination, attractions, visitDate };
}
