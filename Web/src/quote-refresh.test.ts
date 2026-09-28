import { describe, expect, it } from "vitest";
import { hotelCheckOut, pickPreferredTransport, preserveResearchedTransports, preserveSelectedItem, transportTimingConflict } from "./quote-refresh";
import type { AccommodationOption, TransportOption, TripDraft } from "./types";

const stay = (id: string, amount: number): AccommodationOption => ({
  id, name: id, quotes: [{ provider: "test", providerTitle: "测试", amountCNY: amount, unit: "perNight", kind: "live" }],
  nameDistanceMeters: 0, nameMeters: 0
});

const transport = (id: string, mode: "train" | "flight", amount: number, minutes: number): TransportOption => ({
  id, mode, title: id, originName: "甲", destinationName: "乙", direction: "outbound", durationMinutes: minutes,
  quotes: [{ provider: "test", providerTitle: "测试", amountCNY: amount, unit: "perPerson", kind: "live" }]
});

describe("safe quote refresh", () => {
  it("uses one hotel night for a day trip and two nights for a three-day trip", () => {
    expect(hotelCheckOut("2026-09-10", 1)).toBe("2026-09-11");
    expect(hotelCheckOut("2026-09-10", 3)).toBe("2026-09-12");
  });

  it("keeps a missing selected hotel as a visibly stale option", () => {
    const result = preserveSelectedItem([stay("fresh", 500)], [stay("chosen", 420)], "chosen", true);
    expect(result.map(item => item.id)).toEqual(["fresh", "chosen"]);
    expect(result[1].quotes[0].isStale).toBe(true);
  });

  it("keeps all last-known quotes on a temporary provider failure", () => {
    const result = preserveSelectedItem([], [stay("chosen", 420), stay("other", 510)], "chosen", false);
    expect(result).toHaveLength(2);
    expect(result.every(item => item.quotes.every(quote => quote.isStale))).toBe(true);
  });

  it("honors a chosen travel mode before comparing offers", () => {
    const result = pickPreferredTransport([transport("fast-train", "train", 300, 100), transport("flight", "flight", 200, 80)], "train");
    expect(result?.id).toBe("fast-train");
  });

  it("does not preselect a cheap trip that misses sightseeing or return check-in", () => {
    const draft = { startDate: "2026-10-06", dayCount: 3, travelers: 2, firstDayStart: "13:00", lastDayEnd: "16:00" } as TripDraft;
    const early = { ...transport("early", "flight", 560, 95), departureTime: new Date("2026-10-06T07:20:00+08:00"), arrivalTime: new Date("2026-10-06T08:55:00+08:00") };
    const late = { ...transport("cheap-late", "train", 80, 400), departureTime: new Date("2026-10-06T07:00:00+08:00"), arrivalTime: new Date("2026-10-06T13:40:00+08:00") };
    expect(pickPreferredTransport([early, late], "train", { draft })?.id).toBe("early");
    expect(pickPreferredTransport([late], "train", { draft })).toBeNull();
    const returning = { ...early, direction: "return" as const, departureTime: new Date("2026-10-08T18:00:00+08:00"), arrivalTime: new Date("2026-10-08T20:00:00+08:00") };
    expect(transportTimingConflict(returning, draft)).toMatch(/值机/);
    returning.departureTime = new Date("2026-10-08T19:00:00+08:00");
    expect(transportTimingConflict(returning, draft)).toBeNull();
  });

  it("retains all reviewed flights on live refresh and ages their prices", () => {
    const reviewed = { ...transport("reviewed", "flight", 560, 95), quotes: [{ provider: "web-research", providerTitle: "网页查询记录", kind: "indicative" as const, unit: "perPerson" as const, amountCNY: 560, capturedAt: "2026-09-28T06:00:00Z" }] };
    const refreshed = preserveResearchedTransports([transport("fresh", "train", 200, 120)], [reviewed], Date.parse("2026-09-28T07:00:00Z"));
    expect(refreshed.map(item => item.id)).toEqual(["fresh", "reviewed"]);
    expect(refreshed[1].quotes[0].isStale).toBe(false);
    expect(preserveResearchedTransports(refreshed, [reviewed], Date.parse("2026-09-29T07:00:00Z"))[1].quotes[0].isStale).toBe(true);
  });
});
