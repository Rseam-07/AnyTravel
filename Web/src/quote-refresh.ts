import type { Plan, ProviderQuote, TicketQuote, TransportOption, TripDraft } from "./types";
import { preferredQuote, quoteContext, quoteTotal } from "./quotes";

export function quoteTripKey(draft: TripDraft, planGeneratedAt?: string): string {
  return JSON.stringify([
    draft.origin, draft.destination, draft.startDate, draft.dayCount, draft.travelers,
    draft.party,
    draft.skipAccommodation, draft.skipTransport, draft.longDistanceMode, planGeneratedAt
  ]);
}

export function hotelCheckOut(startDate: string, dayCount: number): string {
  const date = new Date(`${startDate}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + Math.max(dayCount - 1, 1));
  return date.toISOString().slice(0, 10);
}

function staleQuote(quote: ProviderQuote): ProviderQuote {
  return { ...quote, isStale: true };
}

export function staleItems<T extends { id: string; quotes: ProviderQuote[] }>(items: T[]): T[] {
  return items.map(item => ({ ...item, quotes: item.quotes.map(staleQuote) }));
}

/** A refresh may update prices, but it must not silently erase a user's current choice. */
export function preserveSelectedItem<T extends { id: string; quotes: ProviderQuote[] }>(
  fresh: T[], previous: T[], selectedID: string | null, succeeded: boolean
): T[] {
  if (!succeeded) return staleItems(previous);
  if (!selectedID || fresh.some(item => item.id === selectedID)) return fresh;
  const selected = previous.find(item => item.id === selectedID);
  return selected ? [...fresh, ...staleItems([selected])] : fresh;
}

export function staleTicketQuotes(tickets: Record<string, TicketQuote>): Record<string, TicketQuote> {
  return Object.fromEntries(Object.entries(tickets).map(([id, quote]) => [id, { ...quote, isStale: true }]));
}

/** Keep manually reviewed records when refreshing unrelated live providers. */
export function preserveResearchedTransports(fresh: TransportOption[], previous: TransportOption[], now = Date.now()): TransportOption[] {
  const reviewed = previous.filter(item => item.quotes.some(quote => quote.provider === "web-research"));
  const ids = new Set(reviewed.map(item => item.id));
  return [...fresh.filter(item => !ids.has(item.id)), ...reviewed.map(item => ({ ...item, quotes: item.quotes.map(quote => ({
    ...quote, isStale: !quote.capturedAt || now - Date.parse(quote.capturedAt) > 6 * 3600_000
  })) }))];
}

export function transportTimingConflict(item: TransportOption, draft: TripDraft, plan?: Plan | null): string | null {
  if (!draft.startDate) return null;
  const first = plan?.days[0];
  const last = plan?.days.at(-1);
  const minute = (clock?: string) => clock ? Number(clock.slice(0, 2)) * 60 + Number(clock.slice(3, 5)) : undefined;
  const start = minute(draft.firstDayStart) ?? first?.startMinute;
  const end = minute(draft.lastDayEnd) ?? last?.endMinute;
  const midnight = Date.parse(`${draft.startDate}T00:00:00+08:00`);
  // Conservative transfer allowance, not a real-time airport/station route estimate.
  const buffer = item.mode === "flight" ? (item.direction === "outbound" ? 120 : 180) : 60;
  if (item.direction === "outbound" && start != null && item.arrivalTime && item.arrivalTime.getTime() + buffer * 60_000 > midnight + start * 60_000) {
    return `到达后按 ${buffer} 分钟接驳预留，赶不上首日游览开始。请改班次或推迟首日开始时间。`;
  }
  if (item.direction === "return" && end != null && item.departureTime && item.departureTime.getTime() - buffer * 60_000 < midnight + (draft.dayCount - 1) * 86_400_000 + end * 60_000) {
    return `出发前按 ${buffer} 分钟接驳${item.mode === "flight" ? "与值机" : ""}预留，末日游览结束太晚。请改班次或提前结束时间。`;
  }
  return null;
}

export function pickPreferredTransport(list: TransportOption[], preferred?: string, trip?: { draft: TripDraft; plan?: Plan | null }): TransportOption | null {
  if (list.length === 0) return null;
  const context = trip ? quoteContext(trip.draft, "transport") : { category: "transport" as const, travelers: 1, nights: 1, rooms: 1 };
  const price = (item: TransportOption) => { const quote = preferredQuote(item.quotes, context); return quote ? quoteTotal(quote, context) : undefined; };
  const feasible = trip ? list.filter(item => item.departureTime && item.arrivalTime && !transportTimingConflict(item, trip.draft, trip.plan)) : list;
  const preferredList = preferred ? feasible.filter(item => item.mode === preferred) : [];
  const candidates = preferredList.length ? preferredList : feasible;
  return [...candidates].sort((a, b) => {
    const aPrice = price(a), bPrice = price(b);
    if (aPrice != null && bPrice != null && aPrice !== bPrice) return aPrice - bPrice;
    if (aPrice != null && bPrice == null) return -1;
    if (aPrice == null && bPrice != null) return 1;
    return (a.durationMinutes ?? Number.MAX_SAFE_INTEGER) - (b.durationMinutes ?? Number.MAX_SAFE_INTEGER);
  })[0] ?? null;
}
