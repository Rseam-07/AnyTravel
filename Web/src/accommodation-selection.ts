import type { AccommodationOption, Coord } from "./types";
import { distanceMeters } from "./planner";
import { preferredQuote, quoteTotal, type QuoteContext } from "./quotes";

/** City catalogs can include distant county-level cities. Never auto-pick them
 * merely because their nightly rate is the lowest. Keep them browseable. */
export function pickNearbyAccommodation(items: AccommodationOption[], anchors: Coord[], context: QuoteContext = { category: "accommodation", nights: 1, rooms: 1, travelers: 1 }) {
  if (!anchors.length) return null;
  return items.flatMap(item => {
    if (!item.coordinate) return [];
    const distance = Math.min(...anchors.map(anchor => distanceMeters(anchor, item.coordinate!)));
    if (!Number.isFinite(distance) || distance > 18_000) return [];
    const quote = preferredQuote(item.quotes.filter(q => !q.isStale), context);
    return quote ? [{ item, quote, distance }] : [];
  }).sort((a, b) => Math.floor(a.distance / 3000) - Math.floor(b.distance / 3000) || quoteTotal(a.quote, context)! - quoteTotal(b.quote, context)!)[0] ?? null;
}
