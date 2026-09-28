import { effectiveParty, type ProviderQuote, type TripDraft } from "./types";

export type QuoteContext = { category: "accommodation" | "transport"; travelers: number; nights: number; rooms: number };
export function quoteContext(draft: TripDraft, category: QuoteContext["category"]): QuoteContext {
  return { category, travelers: Math.max(draft.travelers, 1), nights: Math.max(draft.dayCount - 1, 1), rooms: effectiveParty(draft).rooms };
}
export function quoteTotal(quote: ProviderQuote | undefined, context: QuoteContext): number | null {
  if (!quote) return null;
  if (quote.totalAmountCNY != null && Number.isFinite(quote.totalAmountCNY)) return quote.totalAmountCNY;
  const price = quote.amountCNY;
  if (price == null || !Number.isFinite(price) || price < 0) return null;
  if (quote.unit === "perPerson") return price * context.travelers;
  if (quote.unit === "perNight") return price * context.nights * context.rooms;
  return price;
}
/** All comparisons use one trip's total, with current live prices ahead of references. */
export function preferredQuote(quotes: ProviderQuote[], context: QuoteContext): ProviderQuote | undefined {
  const rank = (q: ProviderQuote) => q.kind === "live" ? 0 : q.kind === "indicative" ? 1 : 2;
  return quotes.filter(q => q.kind !== "demo" && quoteTotal(q, context) != null).sort((a, b) =>
    Number(Boolean(a.isStale)) - Number(Boolean(b.isStale)) || rank(a) - rank(b) || quoteTotal(a, context)! - quoteTotal(b, context)!
  )[0];
}
export const quoteUnitLabel = (unit: ProviderQuote["unit"]) => unit === "total" ? "/本次总价" : unit === "perPerson" ? "/人" : "/间晚";
