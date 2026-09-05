import { describe, expect, it } from "vitest";
import { hotelCheckOut, pickPreferredTransport, preserveSelectedItem } from "./quote-refresh";
import type { AccommodationOption, TransportOption } from "./types";

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
});
