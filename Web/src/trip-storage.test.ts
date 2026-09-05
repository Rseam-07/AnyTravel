import { describe, expect, it } from "vitest";
import { readTripStorage, restoredSnapshot, snapshotTrip, writeTripStorage } from "./trip-storage";
import { effectiveParty, type Plan, type TripDraft } from "./types";

class MemoryStorage {
  values = new Map<string, string>();
  getItem(key: string) { return this.values.get(key) ?? null; }
  setItem(key: string, value: string) { this.values.set(key, value); }
}

const draft: TripDraft = {
  origin: "上海", destination: "苏州", destinationCoord: { lat: 31.3, lng: 120.6 }, startDate: "2026-09-10",
  dayCount: 3, travelers: 2, budgetPerPerson: 3000, pace: "relaxed", interests: ["gardens"],
  transportMode: "transit", longDistanceMode: "train", skipAccommodation: false, skipTransport: false
};
const plan: Plan = {
  generatedAt: "2026-09-05T00:00:00Z", engine: "web-heuristic", notes: [], days: [{
    dateLabel: "9月10日", title: "园林", totalMinutes: 120, visitMinutes: 90, travelMinutes: 30,
    availableMinutes: 480, overCapacity: false, assessment: "松弛", badges: [], route: [], stops: [{
      place: { id: "garden", name: "拙政园", coordinate: { lat: 31.32, lng: 120.62 }, interest: "gardens", source: "test" },
      visitMinutes: 90, isPrimary: true
    }]
  }]
};

function fullTrip() {
  return snapshotTrip({
    draft, plan, places: plan.days[0].stops.map(stop => stop.place), accommodations: [], tickets: {}, selectedDay: 0,
    transports: [{ id: "G1", mode: "train", title: "G1", originName: "上海", destinationName: "苏州", direction: "outbound",
      departureTime: new Date("2026-09-10T00:00:00Z"), quotes: [{ provider: "rail", providerTitle: "铁路", amountCNY: 39.5, unit: "perPerson", kind: "live" }] }],
    selectedAccommodationID: null, selectedOutboundID: "G1", selectedReturnID: null,
    planLocks: { visits: [{ placeID: "garden", placeName: "拙政园", dayIndex: 0, orderIndex: 0, arriveMinute: 600, leaveMinute: 690 }], outboundTransportID: "G1" },
    bookingConfirmations: [{ id: "booking-1", kind: "transport", itemID: "G1", title: "G1", confirmedAt: "2026-09-05T00:00:00Z", startDate: "2026-09-10", actualAmountCNY: 158, note: "订单尾号 1234" }]
  }, "trip-1");
}

describe("trip storage", () => {
  it("normalizes a structured party and keeps legacy drafts usable", () => {
    expect(effectiveParty({ travelers: 4 }).adults).toBe(4);
    expect(effectiveParty({ travelers: 4, party: { adults: 2, childrenAges: [5, 12], rooms: 2, seniorTravelers: 1, mobilityNeed: "stroller" } })).toEqual({
      adults: 2, childrenAges: [5, 12], rooms: 2, seniorTravelers: 1, mobilityNeed: "stroller"
    });
  });

  it("restores the actual route, selections and Date values", () => {
    const storage = new MemoryStorage();
    writeTripStorage(storage, [fullTrip()]);
    const result = readTripStorage(storage);
    expect(result.issue).toBeNull();
    expect(result.trips[0].snapshot?.plan?.days[0].stops[0].place.name).toBe("拙政园");
    expect(result.trips[0].snapshot?.selectedOutboundID).toBe("G1");
    expect(result.trips[0].snapshot?.transports[0].departureTime).toBeInstanceOf(Date);
    expect(result.trips[0].snapshot?.bookingConfirmations[0].note).toBe("订单尾号 1234");
    expect(result.trips[0].snapshot?.bookingConfirmations[0].actualAmountCNY).toBe(158);
    expect(result.trips[0].snapshot?.planLocks.outboundTransportID).toBe("G1");
    expect(result.trips[0].snapshot?.planLocks.visits[0].arriveMinute).toBe(600);
  });

  it("marks restored prices stale until the user refreshes them", () => {
    expect(restoredSnapshot(fullTrip()).transports[0].quotes[0].isStale).toBe(true);
  });

  it("falls back to the last readable backup without deleting corrupt data", () => {
    const storage = new MemoryStorage();
    writeTripStorage(storage, [fullTrip()]);
    storage.setItem("anytravel-web:trips:backup", storage.getItem("anytravel-web:trips")!);
    storage.setItem("anytravel-web:trips", "{broken");
    const result = readTripStorage(storage);
    expect(result.trips[0].id).toBe("trip-1");
    expect(result.issue).toContain("上次备份");
    expect(storage.getItem("anytravel-web:trips")).toBe("{broken");
  });

  it("refuses to overwrite an unreadable primary record", () => {
    const storage = new MemoryStorage();
    storage.setItem("anytravel-web:trips", "{broken");
    expect(() => writeTripStorage(storage, [fullTrip()])).toThrow(/没有覆盖/);
    expect(storage.getItem("anytravel-web:trips")).toBe("{broken");
  });
});
