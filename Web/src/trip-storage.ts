import type { AccommodationOption, BookingConfirmation, Plan, TicketQuote, TransportOption, TravelPlace, TripDraft } from "./types";

export interface TripSnapshot {
  plan: Plan | null;
  places: TravelPlace[];
  accommodations: AccommodationOption[];
  transports: TransportOption[];
  tickets: Record<string, TicketQuote>;
  selectedDay: number;
  selectedAccommodationID: string | null;
  selectedOutboundID: string | null;
  selectedReturnID: string | null;
  bookingConfirmations: BookingConfirmation[];
}

export interface SavedTrip {
  id: string;
  title: string;
  savedAt: string;
  draft: TripDraft;
  snapshot?: TripSnapshot;
  deletedAt?: string;
}

export const TRIP_KEY = "anytravel-web:trips";
export const AUTOSAVE_KEY = "anytravel-web:current-trip";
type StorageLike = Pick<Storage, "getItem" | "setItem">;
const object = (value: unknown): value is Record<string, any> => value !== null && typeof value === "object" && !Array.isArray(value);
const coordinate = (value: unknown) => object(value) && Number.isFinite(value.lat) && Math.abs(value.lat) <= 90 && Number.isFinite(value.lng) && Math.abs(value.lng) <= 180;
const place = (value: unknown) => object(value) && typeof value.id === "string" && typeof value.name === "string" && coordinate(value.coordinate);
const quotes = (value: unknown) => Array.isArray(value) && value.every(q => object(q) && typeof q.provider === "string" && (q.amountCNY == null || (Number.isFinite(q.amountCNY) && q.amountCNY >= 0)));
const bookingConfirmation = (value: unknown) => object(value) && typeof value.id === "string" &&
  ["accommodation", "transport"].includes(value.kind) && typeof value.itemID === "string" &&
  typeof value.title === "string" && typeof value.confirmedAt === "string" &&
  (value.actualAmountCNY == null || (Number.isFinite(value.actualAmountCNY) && value.actualAmountCNY > 0)) &&
  (value.note == null || typeof value.note === "string");

export function validDraft(value: unknown): value is TripDraft {
  return object(value) && typeof value.destination === "string" && typeof value.origin === "string" &&
    Number.isInteger(value.dayCount) && value.dayCount >= 1 && value.dayCount <= 90 &&
    Number.isInteger(value.travelers) && value.travelers >= 1 && value.travelers <= 100 &&
    ["relaxed", "balanced", "full"].includes(value.pace) && Array.isArray(value.interests) &&
    (value.destinationCoord == null || coordinate(value.destinationCoord));
}

function decodeTrip(value: unknown): SavedTrip {
  if (!object(value) || typeof value.id !== "string" || typeof value.title !== "string" ||
      typeof value.savedAt !== "string" || !validDraft(value.draft)) throw new Error("行程文件格式不完整");
  const snapshot = value.snapshot;
  if (snapshot != null) {
    if (!object(snapshot) || !Array.isArray(snapshot.places) || !snapshot.places.every(place) ||
        !Array.isArray(snapshot.accommodations) || !snapshot.accommodations.every(a => object(a) && typeof a.id === "string" && quotes(a.quotes)) ||
        !Array.isArray(snapshot.transports) || !snapshot.transports.every(t => object(t) && typeof t.id === "string" && quotes(t.quotes)) ||
        !object(snapshot.tickets) || (snapshot.bookingConfirmations != null &&
          (!Array.isArray(snapshot.bookingConfirmations) || !snapshot.bookingConfirmations.every(bookingConfirmation)))) {
      throw new Error("行程快照格式不完整");
    }
    if (snapshot.plan != null && (!object(snapshot.plan) || !Array.isArray(snapshot.plan.days) || !Array.isArray(snapshot.plan.notes) ||
        !snapshot.plan.days.every((day: any) => object(day) && Array.isArray(day.stops) && day.stops.every((stop: any) => object(stop) && place(stop.place)) &&
          Array.isArray(day.route) && day.route.every((segment: any) => coordinate(segment.from) && coordinate(segment.to)) && Array.isArray(day.badges)))) {
      throw new Error("行程安排格式不完整");
    }
    snapshot.transports = snapshot.transports.map(t => ({ ...t,
      departureTime: dateOrUndefined(t.departureTime), arrivalTime: dateOrUndefined(t.arrivalTime) }));
    snapshot.bookingConfirmations = snapshot.bookingConfirmations ?? [];
  }
  return value as SavedTrip;
}

function dateOrUndefined(value: unknown): Date | undefined {
  if (value == null) return undefined;
  const date = new Date(String(value));
  if (!Number.isFinite(date.getTime())) throw new Error("班次时间格式不完整");
  return date;
}

function decode(raw: string): SavedTrip[] {
  const value: unknown = JSON.parse(raw);
  // Read the old draft-only library without discarding it during the upgrade.
  const trips = Array.isArray(value) ? value : object(value) && value.version === 2 ? value.trips : null;
  if (!Array.isArray(trips)) throw new Error("不支持的旅册版本");
  return trips.map(decodeTrip);
}

export function readTripStorage(storage: StorageLike, key = TRIP_KEY): { trips: SavedTrip[]; issue: string | null } {
  try {
    const raw = storage.getItem(key);
    if (raw == null) return { trips: [], issue: null };
    try { return { trips: decode(raw), issue: null }; } catch {
      const backup = storage.getItem(key + ":backup");
      if (backup) return { trips: decode(backup), issue: "最近一次记录未能读取，已找回上次备份。原文件仍保留在本机。" };
      return { trips: [], issue: "本机旅册未能读取，原文件仍保留。请先导出浏览器数据，不要清理站点存储。" };
    }
  } catch { return { trips: [], issue: "浏览器暂时不允许读取本机记录，请检查隐私设置。" }; }
}

/** Keep one known-good backup. A corrupt/future record is never silently overwritten. */
export function writeTripStorage(storage: StorageLike, trips: SavedTrip[], key = TRIP_KEY): void {
  const encoded = JSON.stringify({ version: 2, trips });
  decode(encoded);
  const old = storage.getItem(key);
  if (old != null) {
    try { decode(old); } catch { throw new Error("原记录无法读取，为保护数据没有覆盖；请先导出本机数据。 "); }
    if (old === encoded) return;
    storage.setItem(key + ":backup", old);
  }
  storage.setItem(key, encoded);
}

export function snapshotTrip(state: TripSnapshot & { draft: TripDraft }, id: string): SavedTrip {
  return {
    id, title: `${state.draft.destination} · ${state.draft.dayCount}天${state.draft.travelers}人`, savedAt: new Date().toISOString(),
    draft: state.draft,
    snapshot: {
      plan: state.plan, places: state.places, accommodations: state.accommodations, transports: state.transports,
      tickets: state.tickets, selectedDay: state.selectedDay, selectedAccommodationID: state.selectedAccommodationID,
      selectedOutboundID: state.selectedOutboundID, selectedReturnID: state.selectedReturnID,
      bookingConfirmations: state.bookingConfirmations
    }
  };
}

export function restoredSnapshot(trip: SavedTrip): TripSnapshot {
  const saved = trip.snapshot;
  const stale = <T extends { quotes: import("./types").ProviderQuote[] }>(item: T): T => ({ ...item, quotes: item.quotes.map(q => ({ ...q, isStale: true })) });
  return {
    plan: saved?.plan ?? null, places: saved?.places ?? [], accommodations: saved?.accommodations.map(stale) ?? [],
    transports: saved?.transports.map(stale) ?? [],
    tickets: Object.fromEntries(Object.entries(saved?.tickets ?? {}).map(([id, q]) => [id, { ...q, isStale: true }])),
    selectedDay: Math.max(0, Math.min(saved?.selectedDay ?? 0, (saved?.plan?.days.length ?? 1) - 1)),
    selectedAccommodationID: saved?.selectedAccommodationID ?? null,
    selectedOutboundID: saved?.selectedOutboundID ?? null,
    selectedReturnID: saved?.selectedReturnID ?? null,
    bookingConfirmations: saved?.bookingConfirmations ?? []
  };
}
