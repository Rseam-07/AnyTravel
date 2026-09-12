import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { emptyHandbook, emptyLedger, flightStatus, importTravelPage, instant, offsetFor, ledgerCSV, validateHandbook, validateLedger, type LedgerSnapshot } from "./model";
import canonical from "./fixtures/travel-page.json";

const module = { exports: {} as any };
new Function("module", readFileSync(new URL("../../public/vendor/travel-plan-page/ledger.js", import.meta.url), "utf8"))(module);
const stats = (ledger: LedgerSnapshot) => module.exports.calculateStatistics(ledger);
const ledger = () => ({ ...emptyLedger(), travelers: ["a", "b", "c"].map(id => ({ id, name: id, color: "#126E66" })) });
function bill(id: string, payerId: string, amount: number, participantIds = ["a", "b", "c"]) { return { id, payerId, participantIds, baseAmountCents: amount, originalAmountCents: amount, currency: "CNY", category: "餐饮", note: "", orderedAt: "2027-07-01T12:00", createdAt: "2027-07-01T12:00Z", updatedAt: "2027-07-01T12:00Z" }; }
describe("Travel-Plan-Page integration", () => {
  it("imports canonical dates, IANA offsets, explicit tickets, stays, rental prices and to-dos", () => {
    const b = importTravelPage(canonical);
    expect(b.flights[0]).toMatchObject({ departure: "2027-07-01T00:30", departureOffset: "+08:00", arrivalOffset: "+02:00", journeyId: "journey-outbound" });
    expect(b.tickets[0]).toMatchObject({ title: "卢浮宫预约（测试）", purchased: true, dayId: "day-paris", url: "https://www.louvre.fr/" });
    expect(b.days[0].items[1].ticketIds).toContain("ticket-louvre");
    expect(b.rentals[0]).toMatchObject({ company: "验收租车（测试）", pickupOffset: "+02:00", price: "CHF 120", checklist: ["拍照记录车况", "确认油量"] });
    expect(b.stays[0].note).toContain("2027-07-01"); expect(b.todos).toHaveLength(2);
    expect(b.days[1].items[0].placeIds).toEqual(["place-louvre", "place-zurich"]);
    expect(b.days[1].items[0].note).toContain("250 分钟");
  });
  it("imports renderer references without dropping IDs or missing-flight placeholders", () => {
    const b = importTravelPage({ metadata: { title: "Renderer" }, flights: [], flightJourneys: [{ id: "j", placeholder: true, title: "返程待定", missingFields: ["起飞时间"] }], places: [{ id: "p", nameZh: "测试", geo: { lat: 31, lng: 121 } }], days: [{ day: 1, date: "2027-07-01", title: "一天", schedule: [{ id: "i", text: "测试", placeId: "p" }] }], ticketPlanning: { items: [{ id: "t", name: "票", scheduleItemIds: ["i"], purchaseStatus: "purchased" }] }, preTrip: { todoItems: [{ id: "x", text: "准备", completed: true }] } });
    expect(b.days[0].items[0].ticketIds).toEqual(["t"]); expect(b.flights[0].note).toContain("起飞时间"); expect(b.todos[0].completed).toBe(true);
  });
  it("roundtrips portable backups and rejects malformed data and executable links", () => {
    const b = importTravelPage(canonical); expect(importTravelPage({ format: "anytravel-handbook", book: structuredClone(b) })).toEqual(b);
    b.tickets[0].url = "javascript:alert(1)"; b.rentals[0].links = [{ title: "bad", url: "data:text/html,bad" }];
    expect(validateHandbook(b).tickets[0].url).toBeUndefined(); expect(b.rentals[0].links).toEqual([]);
    expect(() => validateHandbook({ ...b, days: [{ ...b.days[0], notes: [{}] }] })).toThrow();
    expect(() => importTravelPage({ days: [] })).toThrow();
    expect(() => validateHandbook({ ...b, places: [...b.places, b.places[0]] })).toThrow();
  });
  it("does not invent zero coordinates for missing/null coordinates", () => {
    const b = importTravelPage({ trip: { title: "No map" }, entities: { places: { p: { name: "未知地点", geo: { lat: null, lng: null } } } }, days: [] });
    expect(b.places[0].coordinate).toBeUndefined();
  });
  it("rejects invalid dates and DST gaps and uses different local offsets across a journey", () => {
    expect(instant("2027-02-30T10:00", "+08:00")).toBeNull(); expect(instant("2027-07-01T24:00", "+08:00")).toBeNull(); expect(instant("2027-07-01T10:00", "+14:30")).toBeNull();
    expect(offsetFor("2027-03-28T02:30", "Europe/Paris")).toBe("");
    expect(offsetFor("2027-01-01T08:00", "Europe/Paris")).toBe("+01:00");
    const f = importTravelPage(canonical).flights[0];
    expect(flightStatus(f, Date.parse("2027-06-30T16:00Z"))).toEqual({ label: "距离出发", value: "00:30:00" });
    expect(flightStatus(f, Date.parse("2027-07-01T05:00Z"))).toEqual({ label: "途中 · 距抵达", value: "01:00:00" });
    expect(flightStatus(f, Date.parse("2027-07-01T07:00Z")).label).toBe("已抵达");
  });
  it("preserves every cent and conserves balances in three-way splits", () => {
    const l = ledger(); l.bills = [bill("b1", "a", 100)]; validateLedger(l);
    const s = stats(l); expect(s.members.map((m: any) => m.owedCents)).toEqual([34, 33, 33]); expect(s.members.reduce((n: number, m: any) => n + m.netCents, 0)).toBe(0);
    expect(s.transfers).toHaveLength(2);
  });
  it("nets reciprocal spending before choosing the minimum settlement transfers", () => {
    const l = ledger(); l.bills = [bill("b1", "a", 1000, ["b"]), bill("b2", "b", 1000, ["a"]), bill("b3", "c", 600, ["a", "b", "c"])];
    const s = stats(l); expect(s.members.map((m: any) => m.netCents)).toEqual([-200, -200, 400]); expect(s.transfers).toHaveLength(2);
  });
  it("rejects duplicate participants, dangling payer IDs and unsafe totals", () => {
    const l = ledger(); l.bills = [bill("b", "missing", 100)]; expect(() => validateLedger(l)).toThrow();
    l.bills = [bill("b", "a", 100, ["a", "a"])]; expect(() => validateLedger(l)).toThrow();
    l.bills = [bill("b", "a", Number.MAX_SAFE_INTEGER), bill("c", "a", 1)]; expect(() => validateLedger(l)).toThrow();
  });
  it("escapes formula-like CSV text and includes original and settlement currency amounts", () => { const l = ledger(); l.bills = [{ ...bill("b", "a", 333), note: '=HYPERLINK("bad")', currency: "EUR", originalAmountCents: 44 }]; const csv = ledgerCSV(l); expect(csv).toContain("'=HYPERLINK"); expect(csv).toContain('"0.44","3.33"'); });
  it("uses an empty real ledger without sample expenses for a fresh user", () => { expect(emptyHandbook().ledger.bills).toEqual([]); expect(stats(emptyLedger()).members).toEqual([]); });
});
