import { expect, it } from "vitest";
import { pickNearbyAccommodation } from "./accommodation-selection";
import type { AccommodationOption } from "./types";
const hotel = (id: string, lng: number | undefined, amountCNY: number): AccommodationOption => ({ id, name: id, coordinate: lng ? { lng, lat: 31.3 } : undefined, quotes: [{ provider: "test", providerTitle: "test", amountCNY, kind: "live", unit: "perNight" }], nameMeters: 0, nameDistanceMeters: 0 });
it("prefers a hotel near the itinerary over a cheap distant county", () => {
  const result = pickNearbyAccommodation([hotel("county", 120, 90), hotel("nearby", 120.631, 250)], [{ lat: 31.3, lng: 120.63 }]);
  expect(result?.item.id).toBe("nearby");
});
it("leaves the choice unset if every price is far away, stale or unlocated", () => {
  const stale = hotel("stale", 120.63, 80); stale.quotes[0].isStale = true;
  expect(pickNearbyAccommodation([hotel("county", 120, 90), hotel("unlocated", undefined, 50), stale], [{ lat: 31.3, lng: 120.63 }])).toBeNull();
});
