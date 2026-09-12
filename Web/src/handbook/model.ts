import type { AppState } from "../store";
import type { Coord } from "../types";
import { bestQuote } from "../planner";

export const MODULES = ["overview", "flights", "route", "itinerary", "tickets", "driving", "todo", "ledger"] as const;
export type Module = typeof MODULES[number];
export const MODULE_TITLES: Record<Module, string> = { overview: "总览", flights: "航班交通", route: "路线地图", itinerary: "每日行程", tickets: "票券夹", driving: "租车自驾", todo: "出发清单", ledger: "同行账本" };
export interface BookPlace { id: string; name: string; region: string; coordinate?: Coord; address: string; url?: string }
export interface BookDay { id: string; date: string; title: string; notes: string[]; items: { id: string; time: string; title: string; note: string; placeIds: string[]; ticketIds: string[] }[] }
export interface BookFlight { id: string; title: string; number: string; from: string; to: string; departure: string; arrival: string; departureOffset: string; arrivalOffset: string; note: string; url?: string; journeyId?: string; journeyTitle?: string; sequence?: number }
export interface BookTicket { id: string; title: string; dayId: string; placeId?: string; purchased: boolean; note: string; url?: string; documentId?: string; documentURL?: string }
export interface BookRental { id: string; company: string; vehicle: string; pickup: string; dropoff: string; pickupOffset: string; dropoffOffset: string; pickupPlace: string; returnPlace: string; price: string; contact: string; checklist: string[]; insurance: string[]; driving: string[]; links: { title: string; url: string }[]; returned: boolean }
export interface BookDocument { id: string; name: string; type: "application/pdf" | "image/png" | "image/jpeg" | "image/webp"; data: string }
export interface LedgerSnapshot { version: number; settings: { baseCurrency: string; commonCurrencies: string[]; lastCurrency: string }; travelers: { id: string; name: string; color: string; initial?: string }[]; bills: { id: string; originalAmountCents: number; baseAmountCents: number; currency: string; category: string; note: string; orderedAt: string; payerId: string; participantIds: string[]; createdAt: string; updatedAt: string }[]; updatedAt: string }
export interface Handbook {
  version: 1; id: string; title: string; timeZone: string; updatedAt: string; modules: Record<Module, boolean>;
  places: BookPlace[]; days: BookDay[]; flights: BookFlight[]; tickets: BookTicket[]; rentals: BookRental[];
  stays: { id: string; title: string; address: string; note: string; url?: string }[];
  todos: { id: string; text: string; completed: boolean }[]; documents: BookDocument[]; ledger: LedgerSnapshot;
  source?: { project: string; importedAt: string }; notes: string[];
}
export const uid = () => crypto.randomUUID();
export const text = (v: unknown, limit = 2000): string => (typeof v === "string" || typeof v === "number") ? String(v).trim().slice(0, limit) : "";
export function safeURL(v: unknown): string | undefined {
  try { const u = new URL(text(v)); return ["https:", "http:"].includes(u.protocol) && !u.username && !u.password ? u.href : undefined; } catch { return undefined; }
}
export function emptyLedger(): LedgerSnapshot { return { version: 1, settings: { baseCurrency: "CNY", commonCurrencies: ["EUR", "USD", "HKD"], lastCurrency: "CNY" }, travelers: [], bills: [], updatedAt: new Date().toISOString() }; }
export function emptyHandbook(id: string = uid(), title = "新的远方"): Handbook {
  return { version: 1, id, title, timeZone: "Asia/Shanghai", updatedAt: new Date().toISOString(), modules: Object.fromEntries(MODULES.map(m => [m, true])) as Record<Module, boolean>, places: [], days: [], flights: [], tickets: [], rentals: [], stays: [], todos: [], documents: [], ledger: emptyLedger(), notes: [] };
}
export function dateAfter(start: string | undefined, days: number): string {
  if (!start) return "";
  const d = new Date(`${start}T12:00:00Z`); if (!Number.isFinite(d.getTime())) return "";
  d.setUTCDate(d.getUTCDate() + days); return d.toISOString().slice(0, 10);
}
function localDateTime(d: Date | string | undefined, zone = "Asia/Shanghai") {
  if (!d) return "";
  const date = new Date(d); if (!Number.isFinite(date.getTime())) return "";
  const parts = new Intl.DateTimeFormat("sv-SE", { timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(date);
  return parts.replace(" ", "T");
}
export function fromPlanner(state: AppState, previous?: Handbook): Handbook {
  const book = emptyHandbook(state.currentTripID, `${state.draft.destination || "新的远方"} · ${state.draft.dayCount} 天`);
  book.days = (state.plan?.days ?? []).map((d, i) => ({ id: `day-${i + 1}`, date: dateAfter(state.draft.startDate, i), title: d.title, notes: [d.assessment, ...d.badges].filter(Boolean), items: d.stops.map((s, j) => ({ id: `${i}-${s.place.id}-${j}`, time: [s.arrivalText, s.departureText].filter(Boolean).join("–"), title: s.place.name, note: [s.note, s.opening].filter(Boolean).join(" · "), placeIds: [s.place.id], ticketIds: state.tickets[s.place.id] || s.ticket ? [`ticket-${s.place.id}`] : [] })) }));
  const places = (state.plan?.days.flatMap(d => d.stops.map(s => s.place)) ?? state.places);
  book.places = [...new Map(places.map(p => [p.id, { id: p.id, name: p.name, coordinate: p.coordinate, address: p.address || "", region: state.draft.destination }])).values()];
  book.tickets = [...new Map((state.plan?.days ?? []).flatMap((d, i) => d.stops.flatMap(s => {
    const q = state.tickets[s.place.id] ?? s.ticket; if (!q) return [];
    return [[s.place.id, { id: `ticket-${s.place.id}`, title: s.place.name, placeId: s.place.id, dayId: `day-${i + 1}`, purchased: false, note: `${q.amountCNY == null ? "价格待确认" : `查询起价 ¥${q.amountCNY}`} · ${q.note}`, url: safeURL(q.bookingURL) }] as const];
  }))).values()];
  const transport = state.transports.filter(t => [state.selectedOutboundID, state.selectedReturnID].includes(t.id));
  book.flights = transport.map(t => ({ id: t.id, title: `${t.direction === "outbound" ? "去程" : "返程"} · ${t.title}`, number: t.title, from: t.originName, to: t.destinationName, departure: localDateTime(t.departureTime), arrival: localDateTime(t.arrivalTime), departureOffset: "+08:00", arrivalOffset: "+08:00", note: [state.bookingConfirmations.some(b => b.itemID === t.id) ? "已确认预订" : "已选方案，预订待确认", ...(t.recommendationReasons || [])].join(" · "), url: safeURL(bestQuote(t.quotes)?.bookingURL) }));
  book.stays = state.accommodations.filter(s => s.id === state.selectedAccommodationID).map(s => ({ id: s.id, title: s.name, address: s.address || "", note: [state.draft.startDate, dateAfter(state.draft.startDate, Math.max(1, state.draft.dayCount - 1)), state.bookingConfirmations.some(b => b.itemID === s.id) ? "已确认预订" : "已选住处，预订待确认"].filter(Boolean).join(" · "), url: safeURL(s.officialWebsiteURL || bestQuote(s.quotes)?.bookingURL) }));
  book.notes = state.plan?.notes ?? [];
  if (previous) {
    book.modules = previous.modules; book.timeZone = previous.timeZone; book.ledger = previous.ledger; book.todos = previous.todos;
    book.rentals = previous.rentals; book.documents = previous.documents;
    const incoming = new Set(book.tickets.map(t => t.id));
    book.tickets = book.tickets.map(t => { const old = previous.tickets.find(p => p.id === t.id); return old ? { ...t, purchased: old.purchased, documentId: old.documentId, documentURL: old.documentURL } : t; }).concat(previous.tickets.filter(t => !incoming.has(t.id)));
    book.flights.push(...previous.flights.filter(f => f.id.startsWith("manual-") && !book.flights.some(n => n.id === f.id)));
  }
  return book;
}

export function instant(local: string, offset: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?$/.test(local) || !/^[+-](?:0\d|1[0-4]):[0-5]\d$/.test(offset)) return null;
  if (offset.slice(1, 3) === "14" && offset.slice(4) !== "00") return null;
  const wall = new Date(`${local}Z`);
  if (!Number.isFinite(wall.getTime()) || wall.toISOString().slice(0, 16) !== local.slice(0, 16)) return null;
  const n = Date.parse(local + offset); return Number.isFinite(n) ? n : null;
}
// Derive the offset for canonical IANA endpoints, with a round-trip check for DST gaps.
export function offsetFor(local: string, timeZone: string): string {
  if (!local || !timeZone || instant(local, "+00:00") == null) return "";
  try {
    const wall = Date.parse(local + "Z");
    const formatter = new Intl.DateTimeFormat("sv-SE", { timeZone, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23" });
    const represented = (n: number) => formatter.format(new Date(n)).replace(" ", "T");
    let guess = wall;
    for (let i = 0; i < 3; i++) guess += wall - Date.parse(represented(guess) + "Z");
    if (represented(guess).slice(0, 16) !== local.slice(0, 16)) return "";
    const minutes = Math.round((wall - guess) / 60000), a = Math.abs(minutes);
    return `${minutes < 0 ? "-" : "+"}${String(Math.floor(a / 60)).padStart(2, "0")}:${String(a % 60).padStart(2, "0")}`;
  } catch { return ""; }
}
const endpointTime = (e: any) => e?.localDateTime || ((e?.date || e?.localDate) && (e?.time || e?.localTime) ? `${e.date || e.localDate}T${e.time || e.localTime}` : "");
const endpointOffset = (e: any) => text(e?.utcOffset) || offsetFor(endpointTime(e), text(e?.timeZone));
export function countdown(target: number, now: number): string {
  const seconds = Math.max(0, Math.floor((target - now) / 1000));
  const days = Math.floor(seconds / 86400);
  return `${days ? `${days}天 ` : ""}${[Math.floor(seconds / 3600) % 24, Math.floor(seconds / 60) % 60, seconds % 60].map(n => String(n).padStart(2, "0")).join(":")}`;
}
export function flightStatus(f: BookFlight, now: number) {
  const dep = instant(f.departure, f.departureOffset), arr = instant(f.arrival, f.arrivalOffset);
  if (dep == null || arr == null || arr < dep) return { label: "时刻或时区待补充", value: "确认后显示倒计时" };
  if (now < dep) return { label: "距离出发", value: countdown(dep, now) };
  if (now < arr) return { label: "途中 · 距抵达", value: countdown(arr, now) };
  return { label: "已抵达", value: "这一程已完成" };
}
export function todayIn(zone: string, now = new Date()): string {
  try { return new Intl.DateTimeFormat("sv-SE", { timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit" }).format(now); } catch { return todayIn("Asia/Shanghai", now); }
}

// Import a renderer trip-data.json or the upstream canonical entity format.
const records = (v: any): any[] => Array.isArray(v) ? v : v && typeof v === "object" ? Object.entries(v).map(([id, record]) => ({ ...(record as object), id })) : [];
const strings = (v: any) => records(v).map(v => typeof v === "string" ? v : text(v.text || v.title || v.note)).filter(Boolean);
export function importTravelPage(raw: any): Handbook {
  if (raw?.format === "anytravel-handbook") return validateHandbook(raw.book);
  if (!raw || typeof raw !== "object" || !Array.isArray(raw.days) || !(raw.metadata || raw.trip)) throw new Error("请选择 Travel-Plan-Page 的 trip-data.json、canonical travel-data.json，或 AnyTravel 手册备份。");
  const meta = raw.trip || raw.metadata, entities = raw.entities || {};
  const b = emptyHandbook(text(meta.id || meta.tripId) || uid(), text(meta.title) || "导入的旅程");
  b.timeZone = text(meta.timeZone) || "Asia/Shanghai";
  if (/^[A-Z]{3}$/.test(meta.baseCurrency)) { b.ledger.settings.baseCurrency = meta.baseCurrency; b.ledger.settings.lastCurrency = meta.baseCurrency; b.ledger.settings.commonCurrencies = b.ledger.settings.commonCurrencies.filter(c => c !== meta.baseCurrency); }
  b.source = { project: "Travel-Plan-Page", importedAt: new Date().toISOString() };
  for (const m of MODULES) if (typeof raw.config?.modules?.[m] === "boolean") b.modules[m] = raw.config.modules[m];
  b.places = records(entities.places || raw.places).map(p => {
    const c = p.geo || p.coordinate || {}; const lat = Number(c.lat ?? c.latitude ?? p.latitude), lng = Number(c.lng ?? c.longitude ?? p.longitude);
    return { id: text(p.id) || uid(), name: text(p.nameZh || p.localizedNames?.[meta.language] || p.name), address: text(p.address), region: text(p.countryCode || p.country || p.cityOrArea) || "本次旅程", coordinate: c.lat != null || c.latitude != null || p.latitude != null ? Number.isFinite(lat) && Math.abs(lat) <= 90 && Number.isFinite(lng) && Math.abs(lng) <= 180 ? { lat, lng } : undefined : undefined, url: safeURL(p.navigation?.url || p.googleMapsUrl) };
  });
  b.days = raw.days.map((d: any, i: number) => ({ id: text(d.id) || `day-${i + 1}`, date: text(d.date), title: text(d.title) || `第 ${i + 1} 天`, notes: [...strings(d.notes), ...records(d.costReferences).map((c: any) => [c.label || c.title, c.currency, c.amount ?? c.standard ?? c.discounted ?? records(c.amountOptions).join(" / ")].map(v => text(v)).filter(Boolean).join(" ")), text(d.sourceDateLabelConflict)].filter(Boolean), items: records(d.items || d.schedule).map((s: any, j: number) => {
    const transport = entities.transport?.[s.transportId];
    const flight = entities.flights?.[s.flightId], stay = entities.stays?.[s.stayId], rental = entities.rentals?.[s.rentalId];
    const placeIds = records(s.placeIds).map(String).concat(s.placeId ? [s.placeId] : [], transport ? [transport.fromPlaceId, transport.toPlaceId].filter(Boolean) : [], flight ? [flight.departure?.placeId, flight.arrival?.placeId].filter(Boolean) : [], stay?.placeId ? [stay.placeId] : [], rental ? [rental.pickup?.placeId, rental.dropoff?.placeId].filter(Boolean) : []);
    const event = s.time?.event, eventSource = flight?.[event] || rental?.[event === "return" ? "dropoff" : event];
    const time = typeof s.time === "object" ? text(s.time.text || s.time.localTime || eventSource?.localTime) : text(s.time || s.startTime);
    const transportNote = transport ? [text(transport.mode), transport.durationMinutes ? `${transport.durationMinutes} 分钟` : "", ...strings(transport.notes)].filter(Boolean).join(" · ") : "";
    return { id: text(s.id) || `item-${i}-${j}`, title: text(s.title || s.text), time, note: [strings(s.notes).join(" · ") || text(s.note), transportNote].filter(Boolean).join(" · "), placeIds: [...new Set(placeIds)], ticketIds: records(s.ticketIds).map(String) };
  }) }));
  b.flights = records(entities.flights || raw.flights).map(f => {
    const dep = f.departure || {}, arr = f.arrival || {};
    const group = records(entities.flightGroups || raw.flightJourneys).find(g => g.id === f.journeyId || g.flightIds?.includes(f.id));
    return { id: text(f.id) || uid(), title: text(f.title || f.airline || entities.carriers?.[f.carrierId]?.name) || "航班", number: text(f.flightNumber || f.number), from: text(dep.city || dep.airportName || dep.airportCode || b.places.find(p => p.id === dep.placeId)?.name), to: text(arr.city || arr.airportName || arr.airportCode || b.places.find(p => p.id === arr.placeId)?.name), departure: endpointTime(dep), arrival: endpointTime(arr), departureOffset: endpointOffset(dep), arrivalOffset: endpointOffset(arr), journeyId: text(group?.id || f.journeyId) || undefined, journeyTitle: text(group?.title || group?.route), sequence: group?.flightIds ? group.flightIds.indexOf(f.id) : f.sequence, note: [...strings(f.notes), text(f.note), ...strings(f.missingFields), text(f.connectionFromPrevious?.note), text(group?.bookingStatus), dep.terminal ? `出发 ${dep.terminal}` : "", arr.terminal ? `抵达 ${arr.terminal}` : ""].filter(Boolean).join(" · "), url: safeURL(f.bookingURL || f.url) };
  });
  for (const group of records(entities.flightGroups || raw.flightJourneys)) {
    if (!b.flights.some(f => f.journeyId === group.id) && (group.placeholder || group.status === "missing" || (!b.flights.length && group.missingFields))) b.flights.push({ id: text(group.id) || uid(), title: text(group.title) || "航班资料待补充", number: "", from: "", to: "", departure: "", arrival: "", departureOffset: "", arrivalOffset: "", note: strings(group.missingFields).join(" · "), url: undefined });
  }
  b.tickets = records(entities.tickets || raw.ticketPlanning?.items).map(t => {
    const linkedIDs = [...records(t.itemIds), ...records(t.scheduleItemIds)].map(String);
    const day = b.days.find(d => d.id === t.dayId) || b.days[Number(t.day) - 1] || b.days.find(d => d.items.some(i => i.ticketIds.includes(t.id) || linkedIDs.includes(i.id)));
    const doc = t.document || t.booking?.document;
    const ticket = { id: text(t.id) || uid(), title: text(t.title || t.attraction?.nameZh || t.attraction?.name || t.localizedNames?.[meta.language] || t.name || b.places.find(p => p.id === t.placeId)?.name) || "门票与预订", dayId: day?.id || "", placeId: text(t.placeId || t.placeIds?.[0]) || undefined, purchased: t.purchaseStatus === "purchased" || t.initialStatus === "booked", note: [text(t.requirement), Array.isArray(t.guidance) ? strings(t.guidance).join(" · ") : text(t.guidance || t.note), ...strings(t.notes), text(doc?.url || doc?.path) && !safeURL(doc?.url) ? `原附件 ${text(doc.url || doc.path)}，请在票券夹重新添加` : ""].filter(Boolean).join(" · "), url: safeURL(t.purchaseUrl || t.purchaseURL || t.bookingUrl || t.officialUrl || t.booking?.officialUrl || t.booking?.purchaseUrl), documentURL: safeURL(doc?.url) };
    b.days.forEach(d => d.items.forEach(i => { if (linkedIDs.includes(i.id) && !i.ticketIds.includes(ticket.id)) i.ticketIds.push(ticket.id); }));
    // Legacy renderer files bind by terms; canonical data always keeps explicit IDs.
    if (!raw.entities && day) day.items.forEach(s => { if (records(t.scheduleMatchTerms).some(term => s.title.toLocaleLowerCase().includes(String(term).toLocaleLowerCase()))) s.ticketIds.push(ticket.id); });
    return ticket;
  });
  b.rentals = records(entities.rentals || (raw.groundTransport?.rentalCar ? [raw.groundTransport.rentalCar] : [])).map(r => {
    const pickupPlace = b.places.find(p => p.id === r.pickup?.placeId), returnPlace = b.places.find(p => p.id === r.dropoff?.placeId);
    const deadline = r.dropoff?.recommendedArrivalTime || r.recommendedArrivalTime;
    return { id: text(r.id) || uid(), company: text(r.company || r.provider), vehicle: text(r.vehicle?.example || r.vehicle?.model || r.vehicle?.class || r.vehicle), pickup: endpointTime(r.pickup), dropoff: endpointTime(r.dropoff), pickupOffset: endpointOffset(r.pickup), dropoffOffset: endpointOffset(r.dropoff), pickupPlace: [r.pickup?.location || pickupPlace?.name, r.pickup?.address || pickupPlace?.address].filter(Boolean).join(" · "), returnPlace: [r.dropoff?.vehicleReturnPoint || r.dropoff?.location || returnPlace?.name, r.dropoff?.deadlineWarning || r.deadlineWarning, deadline ? `建议 ${deadline} 提前抵达` : ""].filter(Boolean).join(" · "), price: [r.price?.currency, r.price?.payAtCounter ?? r.price?.amount ?? (Number.isFinite(r.price?.amountMinor) ? r.price.amountMinor / 100 : undefined)].filter(v => v != null).join(" "), contact: text(r.contact || r.phone), checklist: strings(r.checklist || r.requirements || raw.groundTransport?.rentalChecklist), insurance: strings(r.insurance), driving: [...strings(r.drivingNotes || r.notes || raw.groundTransport?.drivingNotes), r.unlimitedKilometers || r.vehicle?.unlimitedKilometers ? "订单标注不限里程，请核对合同" : ""].filter(Boolean), links: records(r.drivingReferenceLinks || raw.groundTransport?.drivingReferenceLinks).flatMap(l => safeURL(l.url) ? [{ title: text(l.label || l.title), url: safeURL(l.url)! }] : []), returned: Boolean(r.returned) };
  });
  b.stays = records(entities.stays || raw.stays || raw.accommodations).map(s => ({ id: text(s.id) || uid(), title: text(s.name || s.title), address: text(s.address || b.places.find(p => p.id === s.placeId)?.address), note: [text(s.checkIn?.localDate || s.checkIn), text(s.checkOut?.localDate || s.checkOut), ...strings(s.notes)].filter(Boolean).join(" · "), url: safeURL(s.url || s.bookingURL || s.googleMapsUrl || s.booking?.officialUrl) }));
  b.todos = records(raw.preTrip?.todoItems || raw.preTrip?.packingItems || raw.preTrip?.items).map(t => ({ id: text(t.id) || uid(), text: typeof t === "string" ? t : text(t.text || t.title), completed: Boolean(t.completed) })).filter(t => t.text);
  b.notes = strings(raw.notes);
  return validateHandbook(b);
}

export function validateLedger(v: any): LedgerSnapshot {
  if (!v || !Array.isArray(v.travelers) || !Array.isArray(v.bills) || v.travelers.length > 12 || v.bills.length > 5000 || !v.settings || typeof v.settings.baseCurrency !== "string" || !Array.isArray(v.settings.commonCurrencies)) throw new Error("账本格式不完整，同行人最多 12 位。");
  const ids = new Set(v.travelers.map((p: any) => p.id));
  if (ids.size !== v.travelers.length || v.travelers.some((p: any) => typeof p.id !== "string" || !text(p.name))) throw new Error("同行人资料不完整或重复。");
  const billIDs = new Set();
  let total = 0;
  if (!/^[A-Z]{3}$/.test(v.settings.baseCurrency) || !/^[A-Z]{3}$/.test(v.settings.lastCurrency) || v.settings.commonCurrencies.some((c: unknown) => typeof c !== "string" || !/^[A-Z]{3}$/.test(c))) throw new Error("账本币种无效。");
  if (v.travelers.some((p: any) => typeof p.color !== "string" || !/^#[0-9a-fA-F]{6}$/.test(p.color))) throw new Error("同行人颜色格式无效。");
  for (const b of v.bills) {
    if (!text(b.id) || billIDs.has(b.id) || !Number.isSafeInteger(b.baseAmountCents) || b.baseAmountCents <= 0 || !Number.isSafeInteger(b.originalAmountCents) || b.originalAmountCents <= 0 || !ids.has(b.payerId) || !Array.isArray(b.participantIds) || !b.participantIds.length || b.participantIds.some((id: string) => !ids.has(id))) throw new Error("账单金额或分摊成员无效。");
    billIDs.add(b.id);
    total += b.baseAmountCents;
    if (!Number.isSafeInteger(total) || new Set(b.participantIds).size !== b.participantIds.length || ![b.note, b.category, b.orderedAt, b.currency, b.createdAt, b.updatedAt].every(v => typeof v === "string") || !/^[A-Z]{3}$/.test(b.currency)) throw new Error("账单总额、币种或参与人格式无效。");
  }
  return v;
}
export function validateHandbook(v: any): Handbook {
  if (!v || v.version !== 1 || typeof v.id !== "string" || !v.id || v.id.length > 160 || !text(v.title) || !v.modules || MODULES.some(m => typeof v.modules[m] !== "boolean")) throw new Error("旅行手册格式不完整。");
  for (const k of ["places", "days", "flights", "tickets", "rentals", "stays", "todos", "documents", "notes"]) if (!Array.isArray(v[k]) || v[k].length > 5000) throw new Error(`手册 ${k} 内容不完整或过多。`);
  for (const k of ["places", "days", "flights", "tickets", "rentals", "stays", "todos", "documents"]) {
    const ids = new Set(); for (const row of v[k]) { if (!row || typeof row.id !== "string" || !text(row.id) || ids.has(row.id)) throw new Error(`手册 ${k} 有重复或无效标识。`); ids.add(row.id); }
  }
  const fields: Record<string, string[]> = { places: ["name", "region", "address"], days: ["date", "title"], flights: ["title", "number", "from", "to", "departure", "arrival", "departureOffset", "arrivalOffset", "note"], tickets: ["title", "dayId", "note"], rentals: ["company", "vehicle", "pickup", "dropoff", "pickupOffset", "dropoffOffset", "pickupPlace", "returnPlace", "price", "contact"], stays: ["title", "address", "note"], todos: ["text"], documents: ["name", "type", "data"] };
  for (const [collection, names] of Object.entries(fields)) for (const row of v[collection]) if (names.some(name => typeof row[name] !== "string" || (name !== "data" && row[name].length > 15000))) throw new Error(`手册 ${collection} 文本格式无效。`);
  if (typeof v.updatedAt !== "string" || typeof v.timeZone !== "string" || v.notes.some((n: unknown) => typeof n !== "string")) throw new Error("手册时间或提醒格式无效。");
  try { new Intl.DateTimeFormat("zh", { timeZone: v.timeZone }).format(); } catch { throw new Error("手册时区无效。"); }
  v.modules.overview = true;
  if (v.places.some((p: any) => !text(p.name) || (p.coordinate && !(Number.isFinite(p.coordinate.lat) && Math.abs(p.coordinate.lat) <= 90 && Number.isFinite(p.coordinate.lng) && Math.abs(p.coordinate.lng) <= 180)))) throw new Error("地点名称或经纬度无效。");
  for (const d of v.days) if (!Array.isArray(d.items) || d.items.length > 2000 || !Array.isArray(d.notes) || d.notes.some((n: unknown) => typeof n !== "string") || new Set(d.items.map((i: any) => i.id)).size !== d.items.length || d.items.some((i: any) => !i || ![i.id, i.title, i.note, i.time].every(v => typeof v === "string") || !Array.isArray(i.placeIds) || !Array.isArray(i.ticketIds) || [...i.placeIds, ...i.ticketIds].some(id => typeof id !== "string"))) throw new Error("每日行程结构无效。");
  for (const r of v.rentals) { if (![r.checklist, r.insurance, r.driving, r.links].every(Array.isArray) || [...r.checklist, ...r.insurance, ...r.driving].some(n => typeof n !== "string")) throw new Error("租车资料无效。"); r.links = r.links.flatMap((l: any) => l && typeof l.title === "string" && safeURL(l.url) ? [{ title: l.title, url: safeURL(l.url) }] : []); }
  for (const d of v.documents) if (!["application/pdf", "image/png", "image/jpeg", "image/webp"].includes(d.type) || typeof d.data !== "string" || !d.data.startsWith(`data:${d.type};base64,`) || d.data.length > 7_100_000 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(d.data.split(",")[1] || "")) throw new Error("票据须为不超过 5 MB 的有效 PDF 或图片。");
  validateLedger(v.ledger);
  // Imported links are always normalized before rendering; executable URL schemes never enter the document viewer.
  for (const row of [...v.places, ...v.flights, ...v.tickets, ...v.stays]) { row.url = safeURL(row.url); if (row.documentURL) row.documentURL = safeURL(row.documentURL); }
  return v as Handbook;
}
export function ledgerCSV(ledger: LedgerSnapshot): string {
  const name = (id: string) => ledger.travelers.find(p => p.id === id)?.name || id;
  const cell = (v: unknown) => `"${String(v ?? "").replace(/^[=+@-]/, "'$&").replaceAll('"', '""')}"`;
  const rows = [["日期", "分类", "备注", "付款人", "参与人", "原币", "原币金额", ledger.settings.baseCurrency + "结算金额"], ...ledger.bills.map(b => [b.orderedAt, b.category, b.note, name(b.payerId), b.participantIds.map(name).join("、"), b.currency, (b.originalAmountCents / 100).toFixed(2), (b.baseAmountCents / 100).toFixed(2)])];
  return "\uFEFF" + rows.map(r => r.map(cell).join(",")).join("\r\n");
}
