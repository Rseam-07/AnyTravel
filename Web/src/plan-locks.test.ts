import { describe, expect, it } from "vitest";
import { applyLockedVisits, draftChangeImpacts, rebaseExistingPlan, toggleVisitLock } from "./plan-locks";
import type { Plan, TravelPlace, TripDraft } from "./types";

const draft = (patch: Partial<TripDraft> = {}): TripDraft => ({
  origin: "上海", destination: "苏州", destinationCoord: { lat: 31.3, lng: 120.6 }, startDate: "2026-09-10",
  dayCount: 2, travelers: 2, budgetPerPerson: 3000, pace: "relaxed", interests: ["gardens"],
  transportMode: "transit", longDistanceMode: "train", skipAccommodation: false, skipTransport: false,
  ...patch
});
const place = (id: string, name: string, lat: number): TravelPlace => ({
  id, name, coordinate: { lat, lng: 120.6 }, interest: "gardens", source: "test"
});
const stop = (item: TravelPlace, arriveMinute: number) => ({
  place: item, arriveMinute, leaveMinute: arriveMinute + 90, arrivalText: "10:00", departureText: "11:30",
  visitMinutes: 90, isPrimary: true
});
const plan = (days: TravelPlace[][]): Plan => ({
  generatedAt: "2026-09-01T00:00:00Z", engine: "web-heuristic", notes: [], days: days.map((items, index) => ({
    dateLabel: `9月${10 + index}日 周四`, title: `9月${10 + index}日 周四 · 第${index + 1}天`,
    stops: items.map((item, stopIndex) => stop(item, 600 + stopIndex * 120)), route: [], totalMinutes: 180,
    visitMinutes: 90 * items.length, travelMinutes: 30, availableMinutes: 480, overCapacity: false, assessment: "松弛", badges: []
  }))
});

describe("plan locks", () => {
  it("keeps a locked visit on its day, order and feasible time after regeneration", () => {
    const a = place("a", "拙政园", 31.31), b = place("b", "苏州博物馆", 31.32), c = place("c", "虎丘", 31.33);
    const previous = plan([[a, b], [c]]);
    const locks = toggleVisitLock({ visits: [] }, previous, 0, 1);
    const rebuilt = applyLockedVisits(plan([[c], [a, b]]), previous, locks, draft());
    expect(rebuilt.days[0].stops[1].place.id).toBe("b");
    expect(rebuilt.days[0].stops[1].arriveMinute).toBeGreaterThanOrEqual(720);
    if ((rebuilt.days[0].stops[1].arriveMinute ?? 0) > 720) {
      expect(rebuilt.days[0].stops[1].note).toMatch(/锁定时段/);
    }
    expect(rebuilt.days.flatMap(day => day.stops).filter(item => item.place.id === "b")).toHaveLength(1);
  });

  it("changes dates and travel time without moving existing places", () => {
    const a = place("a", "拙政园", 31.31), b = place("b", "虎丘", 31.33);
    const previous = plan([[a], [b]]);
    const result = rebaseExistingPlan(previous, draft({ startDate: "2026-10-02", transportMode: "walking" }), { visits: [] });
    expect(result.days.map(day => day.stops[0].place.id)).toEqual(["a", "b"]);
    expect(result.days[0].dateLabel).toContain("10月02日");
  });

  it("explains the affected scope before applying a draft change", () => {
    const impacts = draftChangeImpacts(draft(), draft({ travelers: 3, dayCount: 4 }));
    expect(impacts.map(item => item.title)).toEqual(["同行人数", "旅行天数"]);
    expect(impacts.find(item => item.title === "同行人数")?.scope).toBe("quotes");
    expect(impacts.find(item => item.title === "旅行天数")?.scope).toBe("itinerary");
  });
});
