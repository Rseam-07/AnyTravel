import type { ProviderQuote, TicketQuote, TransportOption, TripDraft } from "./types";

export function quoteTripKey(draft: TripDraft, planGeneratedAt?: string): string {
  return JSON.stringify([
    draft.origin, draft.destination, draft.startDate, draft.dayCount, draft.travelers,
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

export function pickPreferredTransport(list: TransportOption[], preferred?: string): TransportOption | null {
  if (list.length === 0) return null;
  const price = (item: TransportOption) => item.quotes.find(quote => quote.amountCNY != null && quote.kind !== "demo")?.amountCNY;
  const preferredList = preferred ? list.filter(item => item.mode === preferred) : [];
  const candidates = preferredList.length ? preferredList : list;
  return [...candidates].sort((a, b) => {
    const aPrice = price(a), bPrice = price(b);
    if (aPrice != null && bPrice != null && aPrice !== bPrice) return aPrice - bPrice;
    if (aPrice != null && bPrice == null) return -1;
    if (aPrice == null && bPrice != null) return 1;
    return (a.durationMinutes ?? Number.MAX_SAFE_INTEGER) - (b.durationMinutes ?? Number.MAX_SAFE_INTEGER);
  })[0] ?? null;
}
