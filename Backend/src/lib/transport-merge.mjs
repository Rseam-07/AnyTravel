export function mergeTransportOptions(options) {
  const entities = new Map();
  for (const option of options) {
    if (!option || !option.mode || !option.direction || !option.departureTime || !option.arrivalTime) continue;
    const key = transportIdentity(option);
    const offer = offerFromOption(option);
    const existing = entities.get(key);
    if (!existing) {
      entities.set(key, { ...option, offers: [offer], sources: [offer.source] });
      continue;
    }
    mergeOffer(existing.offers, offer);
    if (!existing.sources.includes(offer.source)) existing.sources.push(offer.source);
    if ((!existing.serviceNumber || existing.serviceNumber === existing.provider) && option.serviceNumber) {
      existing.serviceNumber = option.serviceNumber;
    }
    if ((option.durationMinutes || Number.MAX_SAFE_INTEGER) < (existing.durationMinutes || Number.MAX_SAFE_INTEGER)) {
      existing.durationMinutes = option.durationMinutes;
    }
  }

  return [...entities.values()].map((option) => {
    option.offers.sort((lhs, rhs) => {
      const lhsAmount = lhs.amountCNY ?? Number.MAX_SAFE_INTEGER;
      const rhsAmount = rhs.amountCNY ?? Number.MAX_SAFE_INTEGER;
      return lhsAmount - rhsAmount || lhs.provider.localeCompare(rhs.provider);
    });
    const primary = option.offers[0];
    return {
      ...option,
      provider: primary.provider,
      source: primary.source,
      amountCNY: primary.amountCNY,
      fareName: primary.fareName,
      availability: primary.availability,
      bookingURL: primary.bookingURL,
      capturedAt: primary.capturedAt,
      note: primary.note,
      sources: option.sources.sort()
    };
  }).sort((lhs, rhs) => {
    if (lhs.direction !== rhs.direction) return lhs.direction === "outbound" ? -1 : 1;
    if (lhs.mode !== rhs.mode) return lhs.mode === "train" ? -1 : 1;
    const lhsAmount = lhs.amountCNY ?? Number.MAX_SAFE_INTEGER;
    const rhsAmount = rhs.amountCNY ?? Number.MAX_SAFE_INTEGER;
    return lhsAmount - rhsAmount || lhs.departureTime.localeCompare(rhs.departureTime);
  });
}

function transportIdentity(option) {
  const service = normalize(option.serviceNumber);
  const departureMinute = String(option.departureTime).slice(0, 16);
  const arrivalMinute = String(option.arrivalTime).slice(0, 16);
  return [
    option.mode,
    option.direction,
    normalize(option.originName),
    normalize(option.destinationName),
    service,
    departureMinute,
    arrivalMinute
  ].join("|");
}

function offerFromOption(option) {
  return {
    provider: String(option.provider || "unknown").toLowerCase(),
    source: String(option.source || option.provider || "unknown").toLowerCase(),
    amountCNY: Number.isFinite(option.amountCNY) ? option.amountCNY : null,
    unit: "perPerson",
    kind: Number.isFinite(option.amountCNY) ? "live" : "checkOnProvider",
    fareName: option.fareName || "票价待确认",
    availability: option.availability || "库存待确认",
    bookingURL: option.bookingURL || null,
    capturedAt: option.capturedAt || new Date().toISOString(),
    note: option.note || "班次、库存与价格请在提交前复核"
  };
}

function mergeOffer(offers, offer) {
  const key = [offer.provider, normalize(offer.fareName)].join("|");
  const index = offers.findIndex((candidate) => [candidate.provider, normalize(candidate.fareName)].join("|") === key);
  if (index < 0) offers.push(offer);
  else if (offer.amountCNY != null && (offers[index].amountCNY == null || offer.amountCNY < offers[index].amountCNY)) {
    offers[index] = offer;
  }
}

function normalize(value) {
  return String(value || "").normalize("NFKC").toLowerCase().replace(/[\s·•・_\-—]/g, "");
}
