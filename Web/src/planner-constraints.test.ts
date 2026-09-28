import { describe, expect, it } from "vitest";
import { estimateTravelMinutes, heatScore, openingWindows, planItinerary, scheduleDay } from "./planner";
import { famousStayMinutes } from "./knowledge";
import { rebaseExistingPlan } from "./plan-locks";
import type { TravelPlace, TripDraft } from "./types";

const center = { lat: 31.3, lng: 120.6 };
const draft = (patch: Partial<TripDraft> = {}): TripDraft => ({ origin: "上海", destination: "测试城", destinationCoord: center, dayCount: 2, startDate: "2026-09-28", travelers: 2, pace: "balanced", interests: ["culture", "nature", "food"], transportMode: "transit", skipAccommodation: true, skipTransport: true, ...patch });
const place = (id: string, patch: Partial<TravelPlace> = {}): TravelPlace => ({ id, name: `测试地点${id}`, coordinate: center, interest: "culture", source: "test", suggestedVisitMinutes: 90, ...patch });
const ids = (plan: ReturnType<typeof planItinerary>) => plan.days.flatMap(d => d.stops.map(s => s.place.id));

describe("constraint-based planning", () => {
  it("visits one venue once across source aliases, honoring required and excluded aliases", () => {
    const short = place("short", { name: "三峡博物馆" });
    const full = place("full", { name: "重庆中国三峡博物馆" });
    const gallery = place("gallery", { name: "三峡博物馆书画馆" });
    const d = draft({ destination: "重庆", dayCount: 3, mustVisitIDs: ["full", "gallery"] });
    expect(ids(planItinerary([short, full, gallery], d)).sort()).toEqual(["full", "gallery"]);
    expect(ids(planItinerary([short, full, gallery], { ...d, mustVisitIDs: [], excludedPlaceIDs: ["full"] }))).toEqual(["gallery"]);
    const far = place("another", { name: "三峡博物馆", coordinate: { lat: center.lat + 0.02, lng: center.lng } });
    expect(ids(planItinerary([short, far], { ...d, mustVisitIDs: ["short", "another"] }))).toHaveLength(2);
  });
  it("preserves all requested dates, including empty days and a single candidate", () => {
    const result = planItinerary([place("a")], draft({ dayCount: 4 }));
    expect(result.days).toHaveLength(4);
    expect(ids(result)).toEqual(["a"]);
    expect(result.days[3].dateLabel).toContain("10月01日");
  });
  it("respects late arrival and early departure without truncating visits", () => {
    const result = planItinerary([place("a"), place("b"), place("c")], draft({ dayCount: 1, firstDayStart: "15:00", lastDayEnd: "17:00" }));
    expect(ids(result)).toHaveLength(1);
    expect(result.days[0].stops[0].arriveMinute).toBeGreaterThanOrEqual(900);
    expect(result.days[0].totalMinutes).toBeLessThanOrEqual(120);
    expect(result.alternatives).toHaveLength(2);
  });
  it("keeps a required but infeasible visit visible as a conflict", () => {
    const result = planItinerary([place("a", { suggestedVisitMinutes: 300 }), place("b")], draft({ dayCount: 1, firstDayStart: "16:00", lastDayEnd: "17:00", mustVisitIDs: ["a"] }));
    expect(ids(result)).toHaveLength(0);
    expect(result.alternatives?.find(p => p.place.id === "a")?.required).toBe(true);
    expect(result.notes.join()).toContain("必去地点无法满足");
  });
  it("places a Monday-closed museum on an open day", () => {
    const museum = place("museum", { opening: "Tu-Su 09:00-17:00; Mo off" });
    const result = planItinerary([museum, place("park", { interest: "nature" })], draft({ mustVisitIDs: ["museum"] }));
    expect(result.days[0].stops.map(s => s.place.id)).not.toContain("museum");
    expect(result.days[1].stops.map(s => s.place.id)).toContain("museum");
  });
  it("rejects an afternoon visit to a morning-only venue", () => {
    const result = planItinerary([place("museum", { opening: "09:00-12:00" })], draft({ dayCount: 1, firstDayStart: "14:00" }));
    expect(ids(result)).toHaveLength(0);
    expect(result.alternatives).toHaveLength(1);
  });
  it("does not invent a Monday closure where opening data is unknown", () => {
    const result = planItinerary([place("museum", { name: "未知博物馆" })], draft({ dayCount: 1 }));
    expect(ids(result)).toContain("museum");
    expect(result.days[0].stops[0].note).toContain("开放时间待核实");
  });
  it("does not bridge a venue's midday closing interval", () => {
    const result = planItinerary([place("a", { opening: "09:00-11:00,14:00-17:00", suggestedVisitMinutes: 120 })], draft({ dayCount: 1, firstDayStart: "10:00" }));
    expect(result.days[0].stops[0].arriveMinute).toBeGreaterThanOrEqual(840);
    expect(result.days[0].stops[0].leaveMinute).toBeLessThanOrEqual(1020);
  });
  it("counts lunch and contingency in feasibility", () => {
    const day = scheduleDay([place("a", { suggestedVisitMinutes: 180 }), place("b", { suggestedVisitMinutes: 180 })], draft(), 0);
    expect(day.mealMinutes).toBeGreaterThan(0);
    expect(day.bufferMinutes).toBeGreaterThan(0);
    expect(day.totalMinutes).toBeGreaterThan(day.visitMinutes + day.travelMinutes);
  });
  it("does not insert a second lunch when a food stop already serves it", () => {
    const day = scheduleDay([place("a", { suggestedVisitMinutes: 90 }), place("lunch", { interest: "food", suggestedVisitMinutes: 75 }), place("b")], draft(), 0);
    expect(day.breaks?.filter(b => b.kind === "meal")).toHaveLength(0);
  });
  it("uses a morning visit instead of waiting for a nearby lunch stop to open", () => {
    const result = planItinerary([place("lunch", { interest: "food", suggestedVisitMinutes: 75 }), place("morning", { suggestedVisitMinutes: 120 })], draft({ dayCount: 1, pace: "relaxed" }));
    expect(result.days[0].stops.map(s => s.place.id)).toEqual(["morning", "lunch"]);
    expect(result.days[0].breaks?.filter(b => b.kind === "wait")).toHaveLength(0);
  });
  it("allows a morning visit to finish before a slightly later lunch", () => {
    const day = scheduleDay([place("a", { suggestedVisitMinutes: 180 })], draft({ firstDayStart: "10:30" }), 0);
    expect(day.stops[0].arriveMinute).toBe(630);
    expect(day.breaks?.find(b => b.kind === "meal")?.startMinute).toBeLessThanOrEqual(14 * 60);
  });
  it("eats during an opening wait instead of scheduling lunch after an afternoon visit", () => {
    const day = scheduleDay([place("a", { opening: "14:00-20:00", suggestedVisitMinutes: 240 })], draft({ pace: "full" }), 0);
    const meals = day.breaks?.filter(b => b.kind === "meal") ?? [];
    expect(meals).toHaveLength(1);
    expect(meals[0].endMinute).toBeLessThanOrEqual(14 * 60);
    expect(day.stops[0].arriveMinute).toBe(14 * 60);
  });
  it("adds a meal inside an all-day visit and isolates it", () => {
    const result = planItinerary([place("park", { interest: "family", suggestedVisitMinutes: 360 }), place("a")], draft({ mustVisitIDs: ["park"] }));
    const day = result.days.find(d => d.stops.some(s => s.place.id === "park"))!;
    expect(day.stops).toHaveLength(1);
    expect(day.mealMinutes).toBeGreaterThan(0);
    expect(day.stops[0].leaveMinute! - day.stops[0].arriveMinute!).toBeGreaterThan(day.stops[0].visitMinutes);
  });
  it("treats a guide's best time as a preference, not a hard opening window", () => {
    const result = planItinerary([place("view", { interest: "nature", bestTime: "傍晚" })], draft({ dayCount: 1, lastDayEnd: "14:00" }));
    expect(ids(result)).toContain("view");
    expect(result.days[0].stops[0].leaveMinute).toBeLessThanOrEqual(840);
  });
  it("reserves lunch even when the final visit runs to lunchtime", () => {
    const day = scheduleDay([place("a", { suggestedVisitMinutes: 180 })], draft(), 0);
    expect(day.mealMinutes).toBeGreaterThan(0);
  });
  it("never clips implausibly long walking time to two hours", () => {
    expect(estimateTravelMinutes(center, { lat: 32.3, lng: 120.6 }, "walking")).toBeGreaterThan(1000);
  });
  it("does not join distant areas on a walking itinerary", () => {
    const result = planItinerary([place("near"), place("far", { coordinate: { lat: 31.6, lng: 120.6 } })], draft({ dayCount: 1, transportMode: "walking" }));
    expect(ids(result)).toEqual(["near"]);
    expect(result.alternatives?.[0].reason).toContain("接驳偏长");
  });
  it("gives personal interests more weight than an editorial primary badge", () => {
    expect(heatScore(place("quiet", { interest: "nature" }), ["nature"])).toBeGreaterThan(heatScore(place("famous", { interest: "culture", planningPriority: "primary", rating: 5 }), ["nature"]));
  });
  it("prioritizes the user's choice even when its category is not selected", () => {
    const result = planItinerary([place("a"), place("required", { interest: "gardens" })], draft({ dayCount: 1, firstDayStart: "15:00", lastDayEnd: "17:00", mustVisitIDs: ["required"] }));
    expect(ids(result)).toEqual(["required"]);
  });
  it("never adds an explicitly excluded candidate", () => {
    const result = planItinerary([place("a"), place("b")], draft({ excludedPlaceIDs: ["a"] }));
    expect(ids(result)).not.toContain("a");
    expect(result.alternatives?.map(p => p.place.id)).not.toContain("a");
  });
  it("reserves more recovery time for young children and seniors", () => {
    const p = [place("a"), place("b")];
    const ordinary = scheduleDay(p, draft(), 0);
    const family = scheduleDay(p, draft({ party: { adults: 2, childrenAges: [4], rooms: 1, seniorTravelers: 1, mobilityNeed: "stroller" } }), 0);
    expect(family.bufferMinutes).toBeGreaterThan(ordinary.bufferMinutes!);
  });
  it("uses verified route duration in the same feasibility calculation", () => {
    const away = place("a", { coordinate: { lat: 31.305, lng: 120.6 } });
    const result = planItinerary([away], draft({ dayCount: 1, firstDayStart: "15:00", lastDayEnd: "17:00" }), [{ from: center, to: away.coordinate, minutes: 150 }]);
    expect(ids(result)).toHaveLength(0);
  });
  it("preserves a locked day while scheduling other places around it", () => {
    const initial = planItinerary([place("a"), place("b")], draft());
    const old = initial.days[1].stops[0];
    const result = planItinerary([place("c"), place("a"), place("b")], draft(), [], { previous: initial, locks: { visits: [{ placeID: old.place.id, placeName: old.place.name, dayIndex: 1, orderIndex: 0, arriveMinute: old.arriveMinute, leaveMinute: old.leaveMinute }] } });
    expect(result.days[1].stops[0].place.id).toBe(old.place.id);
    expect(result.days[1].stops[0].arriveMinute).toBe(old.arriveMinute);
  });
  it("rechecks opening hours after applying a later locked slot", () => {
    const p = place("a", { opening: "09:00-12:00" });
    const day = scheduleDay([p], draft(), 0, [], { visits: [{ placeID: "a", placeName: p.name, dayIndex: 0, orderIndex: 0, arriveMinute: 840, leaveMinute: 930 }] });
    expect(day.overCapacity).toBe(true);
    expect(day.warnings?.join()).toContain("超出开放时间");
  });
  it("does not add a second onsite meal when recalculating a locked all-day visit", () => {
    const p = place("park", { suggestedVisitMinutes: 360 });
    const first = scheduleDay([p], draft(), 0);
    const old = first.stops[0];
    const second = scheduleDay([p], draft(), 0, [], { visits: [{ placeID: p.id, placeName: p.name, dayIndex: 0, orderIndex: 0, arriveMinute: old.arriveMinute, leaveMinute: old.leaveMinute }] });
    expect(second.stops[0].leaveMinute).toBe(old.leaveMinute);
    expect(second.mealMinutes).toBe(first.mealMinutes);
  });
  it("date-only changes still validate closures and retain meal/rest accounting", () => {
    const p = place("a", { opening: "Tu-Su 09:00-17:00; Mo off", suggestedVisitMinutes: 210 });
    const initial = planItinerary([p], draft({ dayCount: 1, startDate: "2026-09-29" }));
    const changed = rebaseExistingPlan(initial, draft({ dayCount: 1 }), { visits: [] });
    expect(changed.days[0].warnings?.join()).toContain("当天不开放");
    expect(changed.days[0].bufferMinutes).toBeGreaterThan(0);
  });
  it("does not borrow a same-name landmark's facts from another city", () => {
    expect(famousStayMinutes(place("x", { name: "苏州博物馆", coordinate: { lat: 40, lng: 116 }, suggestedVisitMinutes: undefined }), 75)).toBe(75);
  });
  it("has no duplicated place between days and alternatives", () => {
    const candidates = Array.from({ length: 20 }, (_, i) => place(String(i)));
    const result = planItinerary(candidates, draft());
    const all = [...ids(result), ...(result.alternatives ?? []).map(p => p.place.id)];
    expect(new Set(all).size).toBe(candidates.length);
    expect(all).toHaveLength(candidates.length);
    expect(result.days.every(d => !d.overCapacity)).toBe(true);
  });
});

describe("bounded opening rules", () => {
  it.each(["Mo off", "周一闭馆", "星期一休馆"])("honors explicit closures: %s", text => {
    expect(openingWindows(text, "2026-09-28").windows).toHaveLength(0);
  });
  it("handles a weekly range that crosses Sunday", () => {
    expect(openingWindows("Fr-Mo 09:00-17:00", "2026-09-28").windows).toEqual([[540, 1020]]);
    expect(openingWindows("Fr-Mo 09:00-17:00", "2026-09-29").windows).toHaveLength(0);
  });
  it("does not read a Monday-only closure note as closed all week", () => {
    expect(openingWindows("Mo off", "2026-09-29")).toEqual({ windows: [[0, 1440]], known: false });
  });
  it("keeps unknown descriptions explicitly unverified", () => {
    expect(openingWindows("按预约场次入场", "2026-09-28").known).toBe(false);
  });
});
