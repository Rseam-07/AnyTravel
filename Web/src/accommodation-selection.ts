import type { AccommodationOption, Coord } from "./types";
import { distanceMeters } from "./planner";

/** City catalogs can include distant county-level cities. Never auto-pick them
 * merely because their nightly rate is the lowest. Keep them browseable. */
export function pickNearbyAccommodation(items: AccommodationOption[], anchors: Coord[]) {
  if (!anchors.length) return null;
  return items.flatMap(item => {
    if (!item.coordinate) return [];
    const distance = Math.min(...anchors.map(anchor => distanceMeters(anchor, item.coordinate!)));
    if (!Number.isFinite(distance) || distance > 18_000) return [];
    const quote = item.quotes.filter(q => !q.isStale && q.kind !== "demo" && (q.amountCNY ?? 0) > 0)
      .sort((a, b) => a.amountCNY! - b.amountCNY!)[0];
    return quote ? [{ item, quote, distance }] : [];
  }).sort((a, b) => Math.floor(a.distance / 3000) - Math.floor(b.distance / 3000) || a.quote.amountCNY! - b.quote.amountCNY!)[0] ?? null;
}
