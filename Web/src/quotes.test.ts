import { describe, it, expect } from "vitest";
import { preferredQuote, quoteTotal, type QuoteContext } from "./quotes";
import type { ProviderQuote } from "./types";
const context: QuoteContext = { category: "accommodation", travelers: 4, nights: 3, rooms: 2 };
const q = (amountCNY: number, unit: ProviderQuote["unit"], patch: Partial<ProviderQuote> = {}): ProviderQuote => ({ provider: "test", providerTitle: "test", amountCNY, unit, kind: "live", ...patch });
describe("one comparable trip price", () => {
  it("compares per-night, person and stay totals in the same unit", () => {
    const quotes = [q(200, "perNight"), q(1100, "total"), q(250, "perPerson")];
    expect(preferredQuote(quotes, context)?.unit).toBe("perPerson");
    expect(quotes.map(quote => quoteTotal(quote, context))).toEqual([1200, 1100, 1000]);
  });
  it("does not multiply explicit stay totals again or prefer stale/reference prices", () => {
    const live = q(200, "perNight", { totalAmountCNY: 1200 });
    expect(quoteTotal(live, context)).toBe(1200);
    expect(preferredQuote([q(1, "total", { isStale: true }), q(10, "total", { kind: "indicative" }), live], context)).toBe(live);
    expect(preferredQuote([q(NaN, "total"), q(-1, "total")], context)).toBeUndefined();
  });
});
