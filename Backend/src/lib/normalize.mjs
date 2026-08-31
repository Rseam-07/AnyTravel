export function normalizeHotelName(value = "") {
  return String(value)
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[（(].*?[）)]/g, "")
    .replace(/酒店|宾馆|旅馆|客栈|民宿|公寓/g, "")
    .replace(/[\s·•・\-_]/g, "")
    .trim();
}

export function matchRequestedHotel(candidateName, requestedHotels) {
  const candidate = normalizeHotelName(candidateName);
  if (!candidate) return null;
  let best = null;
  let bestScore = 0;

  for (const hotel of requestedHotels) {
    const requested = normalizeHotelName(hotel.name);
    if (!requested) continue;
    let score = 0;
    if (candidate === requested) score = 100;
    else if (candidate.includes(requested) || requested.includes(candidate)) {
      score = 80 - Math.abs(candidate.length - requested.length);
    } else {
      const common = [...new Set(candidate)].filter((character) => requested.includes(character)).length;
      score = Math.round((common / Math.max(candidate.length, requested.length)) * 50);
    }
    if (score > bestScore) {
      bestScore = score;
      best = hotel;
    }
  }
  return bestScore >= 32 ? best : null;
}

export function parseCNY(value) {
  if (typeof value === "number" && Number.isFinite(value)) return Math.round(value);
  const match = String(value ?? "").replace(/,/g, "").match(/(?:¥|￥|CNY|RMB)?\s*(\d+(?:\.\d+)?)/i);
  if (!match) return null;
  const amount = Number(match[1]);
  return Number.isFinite(amount) && amount > 0 ? Math.round(amount) : null;
}

export function isoNow() {
  return new Date().toISOString();
}
