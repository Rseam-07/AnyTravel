import { describe, expect, it } from "vitest";
import { addDays, planItinerary } from "./planner";
import type { Interest, TravelPlace, TripDraft } from "./types";

function draft(overrides: Partial<TripDraft> = {}): TripDraft {
  return {
    origin: "上海",
    destination: "测试城",
    destinationCoord: { lat: 31.23, lng: 121.47 },
    startDate: "2026-09-10",
    dayCount: 2,
    travelers: 2,
    budgetPerPerson: 3000,
    pace: "relaxed",
    interests: ["gardens", "culture", "nature", "family", "food", "night"],
    transportMode: "transit",
    longDistanceMode: "train",
    skipAccommodation: false,
    skipTransport: false,
    ...overrides
  };
}

function place(id: string, interest: Interest, offset: number, name = `地点${id}`): TravelPlace {
  return {
    id,
    name,
    interest,
    coordinate: { lat: 31.23 + offset * 0.01, lng: 121.47 + offset * 0.008 },
    source: "test",
    planningPriority: offset < 2 ? "primary" : "supplemental"
  };
}

describe("itinerary planner", () => {
  it("keeps date arithmetic stable across browser time zones", () => {
    expect(addDays("2026-09-06", 0)).toBe("2026-09-06");
    expect(addDays("2026-09-06", 2)).toBe("2026-09-08");
    expect(addDays("2026-12-31", 1)).toBe("2027-01-01");
  });

  it("limits relaxed days to two main visits plus at most one meal and one night stop", () => {
    const candidates = [
      place("a", "gardens", 0),
      place("b", "culture", 1),
      place("c", "nature", 2),
      place("d", "family", 3),
      place("e", "food", 0.4, "本地午餐"),
      place("f", "food", 2.4, "老街晚餐"),
      place("g", "night", 0.8, "滨江夜景"),
      place("h", "night", 2.8, "古城夜游")
    ];

    const plan = planItinerary(candidates, draft());
    expect(plan.days).toHaveLength(2);
    for (const day of plan.days) {
      const mainCount = day.stops.filter((stop) => !["food", "night"].includes(stop.place.interest)).length;
      expect(mainCount).toBeLessThanOrEqual(2);
      expect(day.stops.filter((stop) => stop.place.interest === "food")).toHaveLength(1);
      expect(day.stops.filter((stop) => stop.place.interest === "night")).toHaveLength(1);
      expect(day.stops.at(-1)?.place.interest).toBe("night");
      expect(day.visitMinutes).toBe(day.stops.reduce((sum, stop) => sum + stop.visitMinutes, 0));
    }
  });

  it("leaves excess attractions out instead of cramming them into the same days", () => {
    const interests: Interest[] = ["gardens", "culture", "nature", "family"];
    const candidates = Array.from({ length: 12 }, (_, index) => place(String(index), interests[index % interests.length], index));
    const plan = planItinerary(candidates, draft());
    const scheduledMain = plan.days.flatMap((day) => day.stops).filter((stop) => !["food", "night"].includes(stop.place.interest));

    expect(scheduledMain).toHaveLength(4);
    expect(plan.notes.some((note) => note.includes("8 个候选点没有硬塞进日程"))).toBe(true);
  });

  it("keeps a full-day destination on its own", () => {
    const themePark = {
      ...place("park", "family", 0, "测试主题乐园"),
      planningPriority: "primary" as const
    };
    const plan = planItinerary(
      [themePark, place("museum", "culture", 1, "测试博物馆"), place("lake", "nature", 2, "测试湖")],
      draft()
    );
    const parkDay = plan.days.find((day) => day.stops.some((stop) => stop.place.id === "park"));

    expect(parkDay?.stops).toHaveLength(1);
    expect(parkDay?.badges).toContain("整日主线");
  });
});
