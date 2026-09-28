import { describe, expect, it } from "vitest";
import { knowledgeCitiesRef, knowledgePlaces } from "./knowledge";
import { planItinerary } from "./planner";
import { readTripStorage, restoredSnapshot, snapshotTrip, writeTripStorage } from "./trip-storage";
import type { Interest, TripDraft } from "./types";

class MemoryStorage {
  values = new Map<string, string>();
  getItem(key: string) { return this.values.get(key) ?? null; }
  setItem(key: string, value: string) { this.values.set(key, value); }
}

/**
 * Seeded journey samples keep release checks varied without making failures
 * impossible to reproduce. This is deliberately separate from the small,
 * fixed unit fixtures used to explain individual planner rules.
 */
function random(seed: number): () => number {
  let value = seed >>> 0;
  return () => {
    value = (value * 1664525 + 1013904223) >>> 0;
    return value / 0x1_0000_0000;
  };
}

const cities = knowledgeCitiesRef().filter((city) =>
  city.country === "中国" && city.coord && knowledgePlaces(city.city).length >= 2
);
const interests: Interest[] = ["gardens", "culture", "nature", "family", "food", "night"];
// Consecutive seeds produce correlated first values with this PRNG. Mix the
// case index so the release sample actually traverses different origins.
const seeds = Array.from({ length: 30 }, (_, index) => Math.imul(index + 1, 0x9e3779b9) >>> 0);

function pickCityPair(next: () => number) {
  const origin = cities[Math.floor(next() * cities.length)];
  let destination = cities[Math.floor(next() * cities.length)];
  while (destination.city === origin.city) destination = cities[Math.floor(next() * cities.length)];
  return { origin, destination };
}

describe("seeded random 1.0 journey audit", () => {
  it(`has enough domestic coverage for ${seeds.length} varied cases`, () => {
    expect(cities.length).toBeGreaterThan(80);
    const pairs = seeds.map((seed) => pickCityPair(random(seed)));
    expect(new Set(pairs.map((pair) => pair.origin.city)).size).toBeGreaterThanOrEqual(20);
    expect(new Set(pairs.map((pair) => pair.destination.city)).size).toBeGreaterThanOrEqual(20);
    expect(new Set(pairs.map((pair) => `${pair.origin.city}>${pair.destination.city}`)).size).toBe(seeds.length);
  });

  for (const seed of seeds) {
    it(`keeps plan invariants for seed ${seed}`, () => {
      const next = random(seed);
      const { origin, destination } = pickCityPair(next);
      const dayCount = 1 + Math.floor(next() * 5);
      const preferred = interests.filter(() => next() > 0.45);
      const selectedInterests = preferred.length ? preferred : [interests[Math.floor(next() * interests.length)]];
      const places = knowledgePlaces(destination.city, selectedInterests).slice(0, 8);
      const draft: TripDraft = {
        origin: origin.city,
        destination: destination.city,
        destinationCoord: destination.coord,
        startDate: `2026-${String(9 + Math.floor(next() * 3)).padStart(2, "0")}-${String(1 + Math.floor(next() * 25)).padStart(2, "0")}`,
        dayCount,
        travelers: 1 + Math.floor(next() * 4),
        budgetPerPerson: 1500 + Math.floor(next() * 5000),
        pace: (["relaxed", "balanced", "full"] as const)[Math.floor(next() * 3)],
        interests: selectedInterests,
        transportMode: (["transit", "walking", "driving"] as const)[Math.floor(next() * 3)],
        longDistanceMode: (["train", "flight", "bus", "self-driving"] as const)[Math.floor(next() * 4)],
        skipAccommodation: false,
        skipTransport: false
      };
      const plan = planItinerary(places, draft);
      const stops = plan.days.flatMap((day) => day.stops);
      const ids = stops.map((stop) => stop.place.id);

      expect(plan.days.length).toBeGreaterThan(0);
      expect(plan.days.length).toBeLessThanOrEqual(dayCount);
      expect(new Set(ids).size).toBe(ids.length);
      for (const day of plan.days) {
        expect(day.route).toHaveLength(day.stops.length);
        expect(day.travelMinutes).toBeGreaterThanOrEqual(0);
        expect(day.totalMinutes).toBeGreaterThanOrEqual(0);
        expect(day.stops.every((stop) => Number.isFinite(stop.arriveMinute ?? 0))).toBe(true);
        if (day.stops.length > 0) {
          expect(day.route[0].from).toEqual(destination.coord);
          expect(day.route.at(-1)?.to).toEqual(day.stops.at(-1)?.place.coordinate);
        }
      }

      const storage = new MemoryStorage();
      const saved = snapshotTrip({
        draft,
        plan,
        places,
        accommodations: [],
        transports: [],
        tickets: {},
        selectedDay: 0,
        selectedAccommodationID: null,
        selectedOutboundID: null,
        selectedReturnID: null,
        bookingConfirmations: [],
        planLocks: { visits: [] }
      }, `seed-${seed}`);
      writeTripStorage(storage, [saved]);
      const restored = readTripStorage(storage);
      expect(restored.issue).toBeNull();
      expect(restored.trips[0].id).toBe(`seed-${seed}`);
      expect(restored.trips[0].draft.origin).toBe(origin.city);
      expect(restored.trips[0].draft.destination).toBe(destination.city);
      expect(restoredSnapshot(restored.trips[0]).plan?.days.flatMap((day) => day.stops).map((stop) => stop.place.id)).toEqual(ids);
    });
  }
});
