import { describe, expect, it } from "vitest";
import { buildExpenseSummary } from "./expense-planner";
import type { AppState } from "./store";
import type { ProviderQuote, TripDraft } from "./types";

const draft: TripDraft = {
  origin: "上海",
  destination: "苏州",
  startDate: "2026-09-10",
  dayCount: 3,
  travelers: 4,
  budgetPerPerson: 3000,
  pace: "relaxed",
  interests: ["gardens"],
  transportMode: "transit",
  skipAccommodation: false,
  skipTransport: false
};

const quote: ProviderQuote = {
  provider: "official",
  providerTitle: "酒店官网",
  amountCNY: 600,
  totalAmountCNY: 1200,
  unit: "perNight",
  kind: "live",
  taxesIncluded: true,
  mealPlan: "含早餐"
};

function state(patch: Partial<AppState> = {}): AppState {
  return {
    draft,
    transports: [],
    selectedOutboundID: null,
    selectedReturnID: null,
    accommodations: [{
      id: "hotel-1",
      name: "测试酒店",
      coordinate: { lat: 31.3, lng: 120.6 },
      quotes: [quote],
      nameDistanceMeters: 0,
      nameMeters: 0
    }],
    selectedAccommodationID: "hotel-1",
    bookingConfirmations: [],
    tickets: {},
    plan: { days: [], generatedAt: "2026-09-05T00:00:00Z", notes: [], engine: "web-heuristic" },
    ...patch
  } as AppState;
}

describe("expense planner", () => {
  it("uses a provider stay total without multiplying it by nights and rooms again", () => {
    const summary = buildExpenseSummary(state());
    const hotel = summary.rows.find((row) => row.id === "accommodation");

    expect(hotel?.amountCNY).toBe(1200);
    expect(hotel?.source).toBe("queried");
    expect(hotel?.note).toContain("本次入住总价");
  });

  it("lets the user's confirmed order total replace a quoted amount", () => {
    const summary = buildExpenseSummary(state({ bookingConfirmations: [{
      id: "booking-1",
      kind: "accommodation",
      itemID: "hotel-1",
      title: "测试酒店",
      confirmedAt: "2026-09-05T00:00:00Z",
      actualAmountCNY: 1688
    }] }));
    const hotel = summary.rows.find((row) => row.id === "accommodation");

    expect(hotel?.amountCNY).toBe(1688);
    expect(hotel?.source).toBe("confirmed");
    expect(summary.confirmedTotalCNY).toBe(1688);
  });

  it("keeps missing prices visible through reserves and explicit pending items", () => {
    const summary = buildExpenseSummary(state({
      accommodations: [{
        id: "hotel-1",
        name: "测试酒店",
        coordinate: { lat: 31.3, lng: 120.6 },
        quotes: [{ ...quote, totalAmountCNY: null, taxesIncluded: false, mealPlan: undefined }],
        nameDistanceMeters: 0,
        nameMeters: 0
      }],
      plan: {
        days: [{
          dateLabel: "9月10日", title: "园林", totalMinutes: 120, visitMinutes: 90, travelMinutes: 30,
          availableMinutes: 480, overCapacity: false, assessment: "松弛", badges: [], route: [], stops: [{
            place: { id: "garden", name: "拙政园", coordinate: { lat: 31.3, lng: 120.6 }, interest: "gardens", source: "test" },
            visitMinutes: 90, isPrimary: true
          }]
        }],
        generatedAt: "2026-09-05T00:00:00Z", notes: [], engine: "web-heuristic"
      }
    }));

    expect(summary.rows.find((row) => row.id === "outbound-transport")?.amountCNY).toBeGreaterThan(0);
    expect(summary.rows.find((row) => row.id === "tickets")?.amountCNY).toBeGreaterThan(0);
    expect(summary.pendingItems).toEqual(expect.arrayContaining(["住宿税费（渠道标记未含）", "早餐", "住宿押金", "1处景点票价"]));
  });
});
