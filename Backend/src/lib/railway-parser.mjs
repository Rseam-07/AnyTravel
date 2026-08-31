export function parseStationNames(source) {
  const records = new Map();
  for (const raw of source.split("@")) {
    const fields = raw.replace(/^var station_names\s*=\s*['\"]?/, "").split("|");
    if (fields.length < 8 || !fields[1] || !fields[2]) continue;
    const record = { name: fields[1], code: fields[2], city: fields[7] || fields[1] };
    records.set(normalizeStationTerm(record.name), record);
    if (!records.has(normalizeStationTerm(record.city))) {
      records.set(normalizeStationTerm(record.city), record);
    }
  }
  return records;
}

export function findStation(records, query) {
  const normalized = normalizeStationTerm(query);
  const exact = records.get(normalized);
  if (exact) return exact;
  return [...records.values()].find((record) => {
    const name = normalizeStationTerm(record.name);
    const city = normalizeStationTerm(record.city);
    return name.includes(normalized) || normalized.includes(name) || city === normalized;
  }) || null;
}

export function parseTrainRow(row, stationMap = {}) {
  const fields = row.split("|");
  if (fields.length < 36 || !fields[2] || !fields[3]) return null;
  return {
    trainNo: fields[2],
    serviceNumber: fields[3],
    fromCode: fields[6],
    toCode: fields[7],
    fromName: stationMap[fields[6]] || fields[6],
    toName: stationMap[fields[7]] || fields[7],
    departureTime: fields[8],
    arrivalTime: fields[9],
    durationText: fields[10],
    durationMinutes: parseDuration(fields[10]),
    canBuy: fields[11] === "Y",
    fromStationNo: fields[16],
    toStationNo: fields[17],
    seatTypes: fields[35],
    availability: {
      business: fields[32],
      firstClass: fields[31],
      secondClass: fields[30],
      softSleeper: fields[23],
      hardSleeper: fields[28],
      hardSeat: fields[29],
      noSeat: fields[26]
    }
  };
}

export function parseTicketPrice(payload) {
  const data = payload?.data;
  if (!data || typeof data !== "object") return null;
  const priorities = [
    ["O", "二等座"],
    ["M", "一等座"],
    ["A3", "硬座"],
    ["A4", "软座"],
    ["A1", "硬卧"],
    ["A2", "软卧"],
    ["9", "商务座"]
  ];
  for (const [key, fareName] of priorities) {
    const amountCNY = parseYuan(data[key]);
    if (amountCNY != null) return { amountCNY, fareName };
  }
  for (const [key, value] of Object.entries(data)) {
    const amountCNY = parseYuan(value);
    if (amountCNY != null) return { amountCNY, fareName: key };
  }
  return null;
}

export function availabilitySummary(availability) {
  const labels = [
    ["secondClass", "二等座"],
    ["firstClass", "一等座"],
    ["business", "商务座"],
    ["hardSleeper", "硬卧"],
    ["softSleeper", "软卧"],
    ["hardSeat", "硬座"],
    ["noSeat", "无座"]
  ];
  const available = labels
    .filter(([key]) => isAvailable(availability[key]))
    .slice(0, 3)
    .map(([key, label]) => `${label}${availability[key] === "有" ? "有票" : availability[key]}`);
  return available.join(" · ") || "余票以12306页面为准";
}

function normalizeStationTerm(value) {
  return String(value || "")
    .trim()
    .replace(/[\s·]+/g, "")
    .replace(/(?:省|市|自治区|特别行政区)$/u, "")
    .replace(/站$/u, "")
    .toLowerCase();
}

function parseDuration(value) {
  const [hours, minutes] = String(value || "").split(":").map(Number);
  if (!Number.isFinite(hours) || !Number.isFinite(minutes)) return null;
  return hours * 60 + minutes;
}

function parseYuan(value) {
  if (typeof value !== "string") return null;
  const match = value.match(/¥\s*(\d+(?:\.\d+)?)/u);
  if (!match) return null;
  const amount = Number(match[1]);
  return Number.isFinite(amount) && amount > 0 ? Math.round(amount) : null;
}

function isAvailable(value) {
  if (value === "有") return true;
  const count = Number(value);
  return Number.isFinite(count) && count > 0;
}
